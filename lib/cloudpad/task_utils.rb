require 'securerandom'

module Cloudpad

  class ConfigBuilder
    attr_reader :file, :options
    def initialize(file, opts={})
      @file = file
      @options = opts
      @multi_document = false
    end
    def result
      eval(File.read(@file))
    rescue => ex
      puts "Error processing file #{@file}".red
      raise ex
    end
    def to_yaml
      r = {'config' => result}.deep_stringify_keys['config']
      #puts r
      if @multi_document == true && r.is_a?(Array)
        Psych.dump_stream(*r)
      else
        Psych.dump(r)
      end
    end
    def to_json
      result.to_json
    end
  end

  module TaskUtils

    def define(key, &block)
      set(key, block)
    end

    def post_settings_blocks
      @blocks ||= []
    end

    def with_settings(&block)
      post_settings_blocks << block
    end

    def app_key
      fetch(:app_key)
    end

    def root_path
      Dir.pwd
    end
    def manifests_path
      File.join(Dir.pwd, "manifests")
    end
    def context_path
      File.join(Dir.pwd, "context")
    end
    def context_extensions_path
      File.join(Dir.pwd, "context", "ext")
    end
    def cloud_path
      File.join(Dir.pwd, "config", "cloud")
    end
    def repos_path
      File.join(context_path, "src")
    end
    def config_path
      File.join root_path, "config"
    end
    def puppet_path
      File.join root_path, "puppet"
    end
    def static_path
      File.join root_path, "static"
    end
    def kube_path
      File.join root_path, "kube"
    end
    def build_path
      File.join root_path, "build"
    end
    def build_image_path
      File.join root_path, "build", "image"
    end
    def build_kube_path
      File.join root_path, "build", "kube"
    end

    def prompt(question, default=nil)
      def_str = default ? " [#{default}] " : " "
      $stdout.print "> #{question}#{def_str}: ".yellow
      ret = $stdin.gets.chomp.strip
      if ret.length == 0
        return default
      else
        return ret
      end
    end

    def build_template_file(name)
      if name.ends_with?(".yml.rb")
        return ConfigBuilder.new(name).to_yaml
      elsif name.ends_with?(".json.rb")
        return ConfigBuilder.new(name).to_json
      else
        return ERB.new(File.read(name)).result(binding)
      end
    end

    def write_template_file(infile, outfile)
      out = build_template_file(infile)
      dir = File.dirname(outfile)
      FileUtils.mkdir_p(dir)
      File.write(outfile, out)
      return outfile
    end

    def clear_cache
      "RUN echo \"#{Time.now.to_s}\""
    end

    def image(id, opts)
      opts[:id] = id
      opts[:env] ||= {}
      opts[:files] ||= []
      opts[:writable_dirs] ||= []
      opts[:df_post_scripts] ||= []
      fetch(:images)[id] = opts
    end

    def images
      fetch(:images)
    end

    def component(id, opts={})
      opts[:id] = id
      opts[:name] = id
      opts[:groups] ||= [id]
      opts[:images] ||= []
      opts[:containers] ||= []
      opts[:file_name] ||= id
      opts[:file_subdir] ||= ""
      opts[:env] ||= {}
      fp = File.join(kube_path, opts[:file_subdir], opts[:file_name])
      [".yml", ".yml.rb"].each do |ext|
        file = fp + ext
        if File.exists?(file)
          opts[:file] = file
          break
        end
      end
      if opts[:file].blank?
        raise "Kube config file could not be found."
      end
      opts[:build_file] = File.join(build_kube_path, opts[:file_subdir], "#{opts[:id]}.yml")
      opts[:env_map] = opts[:env].collect{|k,v| {name: k, value: v}}

      opts[:containers] = opts[:containers].collect {|copts| opts.merge(copts)}
      opts[:containers] = [opts] if opts[:containers].length == 0
      opts[:containers].each do |copts|
        if copts[:full_command].is_a?(String)
          cps = copts[:full_command].split(" ")
          copts[:command] = [cps[0]]
          copts[:args] = cps[1..-1]
        end
      end
      fetch(:components)[id] = Hash[opts]
    end

    def components
      fetch(:components)
    end

    def container_type(id, opts)
      opts[:id] = id
      fetch(:container_types)[id] = Hash[opts]
    end
    def repo(id, opts)
      opts[:id] = id
      fetch(:repos)[id] = Hash[opts]
    end
    def service(id, opts)
      opts[:id] = id
      fetch(:services)[id] = Hash[opts]
    end
    def dockerfile_helper(name, opts)
      opts[:id] = id
      fetch(:dockerfile_helpers)[id] = Hash[opts]
    end
    def container_env_vars(*vars)
      cvs = fetch(:container_env_vars)
      vars.flatten.each do |v|
        cvs[v.upcase] = v
      end
      return cvs
    end
    def container_env_var(name, var)
      cvs = fetch(:container_env_vars)
      cvs[name] = var
    end

    def building_image(name=nil)
      if name.nil?
        fetch(:images)[fetch(:building_image_id)]
      else
        fetch(:images)[name]
      end
    end
    def image_opts(name=nil)
      building_image(name)
    end

    def image_uri(name, opts={})
      reg = fetch(:registry_url)
      ns = fetch(:registry_namespace)
      nt = image_opts(name)[:name_with_tag]
      if ns.present?
        path = "#{ns}/#{nt}"
      else
        path = nt
      end
      if opts[:full] == false
        return path
      else
        return "#{reg}/#{path}"
      end
    end

    def building_image?(img)
      fetch(:building_image) == img
    end

    def container_public_key
      kp = File.join(context_path, "keys", "container.key.pub")
      return File.read(kp).gsub("\n", "")
    end

    def comp_opts(name=nil)
      if name.nil?
        fetch(:components)[fetch(:building_component_id)]
      else
        fetch(:components)[name]
      end
    end

    def building_component_id
      fetch(:building_component_id)
    end

    def next_available_server(type, filt=nil)
      hm = {}
      servers = roles(:host)
      img_opts = fetch(:container_types)[type]
      # filter hosts
      hosts = servers.collect{|s| s.properties.source}.select{|host|
        check = true
        if img_opts[:hosts] && !host.has_id?(img_opts[:hosts])
          check = false
        end
        if filt && !host.has_id?(filt)
          check = false
        end
        check
      }
      return nil if hosts.empty?

      hosts.each do |host|
        hm[host.name] = host.status[:free_mem]
      end

      mv = hm.values.max
      rn = hm.invert[mv]
      servers.select {|server|
        server.properties.source.name == rn
      }.first
    end

    def server_running_container(ci)
      ci = container_with_name(ci) unless ci.is_a?(Cloudpad::Container)
      return nil if ci.nil?
      roles(:host).select{|s| s.properties.source == ci.host}.first
    end

    def container_with_name(name)
      return fetch(:running_containers).select{|c| c.name == name}.first
    end

    def containers_on_host(host)
      return fetch(:running_containers).select{|c| c.host == host}
    end

    def next_available_container_instance(type)
      taken = fetch(:running_containers).select{|c| c.type == type}.collect{|c| c.instance}.sort
      num = 1
      while(taken.include?(num)) do
        num += 1
      end
      return num
    end

    def dfi(inst, *args)
      insts = fetch(:dockerfile_helpers)
      callable = insts[inst]
      raise StandardError, "#{inst} is not a registered dfi" if callable.nil?
      callable.call(*args)
    end

    def filtered_container_types
      cts = fetch(:container_types)
      return cts.keys if ENV['type'].nil?
      tf = ENV['type'].split(',')
    end

    def filtered_images
      ims = fetch(:images)
      cts = fetch(:container_types)
      cmps = fetch(:components)
      if !(img_names = ENV['image']).nil?
        return img_names.split(',').collect{|n| ims[n]}.compact
      elsif ENV['type'].present?
        return filtered_container_types.collect{|t| cts[t][:image]}.uniq.collect{|n| ims[n]}
      elsif ENV['comp'].present?
        return filtered_components.collect{|opts| opts[:images]}.flatten.uniq.compact.collect{|n| ims[n]}
      else
        return ims.values
      end
    end

    def filtered_image_types
      filtered_images.collect{|opts| opts[:id]}
    end

    def filtered_components
      cmps = fetch(:components)
      if ENV['comp'].present?
        ENV['comp'].split(',').collect{|n| cmps[n]}.compact
      elsif ENV['image'].present?
        imgs = filtered_image_types
        cmps.select{|c| (filtered_image_types & c[:images]).length > 0}
      else
        return cmps.values
      end
    end

    def filtered_repo_names
      rv = parse_env('repo') || parse_env('repos')
      if rv
        return rv.split(',')
      else
        return filtered_images.collect{|img| 
          rs = img[:repos]
          if rs
            rs.keys
          else
            []
          end
        }.flatten.uniq
      end
    end

    def docker_version_meta
      ver = fetch(:docker_version)
      vs = ver.split(".")
      ret = {}
      ret[:version] = ver
      ret[:major] = vs[0].to_i
      ret[:minor] = vs[1].to_i
      ret[:patch] = vs[2].to_i
      ret[:number] = ret[:major] * 1000000 + ret[:minor] * 1000 + ret[:patch]
      return ret
    end

    def random_temp_file
      return "/tmp/#{SecureRandom.hex(5)}"
    end

    ## on host

    def process_running?(name)
      test("ps -ef | grep #{name} | grep -v \"grep\"")
    end

    def container_running?(name)
      nr = capture("sudo docker ps -a --filter \"name=#{name}\" -q | wc -l")
      return nr.to_i > 0
    end

    def remote_file_exists?(name)
      test("[ -f #{name} ]")
    end

    def is_package_installed?(name)
      test("dpkg -s #{name}")
    end

    def remote_file_content(name)
      return nil if !remote_file_exists?(name)
      capture("cat #{name}")
    end

    def local_file_content(name, opts={parse_erb: false})
      return nil if !File.exists?(name)
      c = File.read(name)
      if opts[:parse_erb] == true
        return build_template_file(name)
      else
        return c
      end
    end

    def upload_string!(str, rf, opts={})
      lf = random_temp_file
      File.open(lf, "w") {|fp| fp.write(str)}
      upload!(lf, rf, opts)
      File.delete(lf)
    end

    def copy_directory(local, remote, opts={})
      if opts[:update_checksum]
        update_directory_checksum(local)
      end
      lf = random_temp_file
      `tar zcf #{lf} -C #{local} .`
      upload!(lf, lf)
      execute "mkdir -p #{remote}"
      execute "tar zxf #{lf} -C #{remote}"
      `rm -f #{lf}`
      execute "rm -f #{lf}"
      info "Directory #{local} compressed and copied to #{remote} on host."
    end

    def directory_checksums_match?(local, remote, opts={})
      lsum_file = File.join(local, ".cloudpad-md5")
      if opts[:update_local] || !File.exists?(lsum_file)
        update_directory_checksum(local)
      end
      lsum = File.read(lsum_file)
      #puts "LSUM: " + lsum
      rsum = remote_file_content(File.join(remote, ".cloudpad-md5"))
      #puts "RSUM: " + rsum
      #raise "test"
      return lsum && rsum && lsum.strip == rsum.strip
    end

    def update_directory_checksum(local)
      `tar cf - --exclude='.cloudpad-md5' -C #{local} . | md5sum > #{File.join(local, ".cloudpad-md5")}`
    end

    def replace_file_line(file, find_exp, rep, opts={sudo: false})
      pfx = opts[:sudo] ? "sudo " : ""
      bn = File.basename(file)
      execute "#{pfx} cp -n #{file} ~/#{bn}.old"
      # remove old line
      execute "#{pfx} sed -i '/^#{find_exp}.*/d' #{file}"
      execute "echo \"#{rep}\" | #{pfx} tee -a #{file}"
    end

    def clean_shell(cmd)
      Bundler.with_clean_env do
        #sh "env -i /bin/bash -l -c \"#{cmd}\""
        sh cmd
      end
    end

    def local_ip_address(dev="eth0")
      `ifconfig #{dev} | grep inet | awk '{print $2}' | sed 's/addr://'`.strip
    end

    def parse_env(var)
      val = ENV[var]
      if val.nil?
        return nil
      elsif val == "true"
        return true
      elsif val == "false"
        return false
      elsif val.match(/^\d+$/)
        return val.to_i
      else
        return val
      end
    end

    def docker_version_number
      fetch(:docker_version).to_f
    end

    def install_context_extensions
      # make extensions dir
      sh "\\mkdir -p #{context_extensions_path}" if !File.directory?(context_extensions_path)
      ctx_exts = fetch(:context_extensions)
      ctx_exts.each do |name_sym, eopts|
        name = name_sym.to_s
        # create path if doesn't exist
        ep = File.join(context_extensions_path, name)
        gep = eopts[:path]
        # check if paths are the same
        sh "\\rm -rf #{ep}"
        sh "\\cp -a #{gep} #{ep}"
        puts "Installed context extension '#{name}'.".green
      end
    end

    def kubecmd
      ns = fetch(:kube_namespace)
      raise "Kube namespace not defined." if ns.blank?
      if fetch(:kube_dist) == :openshift
        return "oc -n #{ns}"
      else
        return "kubectl -n #{ns}"
      end
    end

    def load_yaml_file(path)
      YAML.load_file(File.join(root_path, path))
    end

    def kube_env_map(val)
      val.collect {|k, v| {name: k, value: v}}
    end

    def inline_yaml(val)
      if val.is_a?(Symbol)
        return inline_yaml(fetch(val))
      elsif val.is_a?(Array)
        return "[#{val.collect {|v| inline_yaml(v)}.join(',')}]"
      elsif val.is_a?(Hash)
        return "{#{val.collect {|k, v| "#{k}: #{inline_yaml(v)}"}.join(',')}}"
      else
        return val.to_json
      end
    end

  end
end

