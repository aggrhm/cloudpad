require 'securerandom'

module Cloudpad
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
      ERB.new(File.read(name)).result(binding)
    end

    def clear_cache
      "RUN echo \"#{Time.now.to_s}\""
    end

    def image(name, opts)
      s = (fetch(:images)[name.to_sym] ||= {})
      s.merge!(opts)
    end
    def container_type(name, opts)
      s = (fetch(:container_types)[name.to_sym] ||= {})
      s.merge!(opts)
    end
    def repo(name, opts)
      s = (fetch(:repos)[name.to_sym] ||= {})
      s.merge!(opts)
    end
    def service(name, val)
      fetch(:services)[name.to_sym] = val
    end
    def dockerfile_helper(name, val)
      fetch(:dockerfile_helpers)[name.to_sym] = val
    end
    def container_env_vars(*vars)
      cvs = fetch(:container_env_vars)
      vars.flatten.each do |v|
        cvs[v.upcase] = v
      end
      return cvs
    end
    def container_env_var(name, var)
      s = (fetch(:container_env_vars)[name.to_sym] ||= {})
      s.merge!(opts)
    end

    def image_opts
      fetch(:images)[fetch(:building_image)]
    end

    def building_image?(img)
      fetch(:building_image) == img
    end

    def container_public_key
      kp = File.join(context_path, "keys", "container.key.pub")
      return File.read(kp).gsub("\n", "")
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
      tf = ENV['type'].split(',').collect(&:to_sym)
    end

    def filtered_image_types
      ims = fetch(:images)
      cts = fetch(:container_types)
      if !(img_names = ENV['image']).nil?
        return img_names.split(',').collect(&:to_sym)
      else
        return filtered_container_types.collect{|t| cts[t][:image]}.uniq
      end
    end

    def filtered_repo_names
      rv = parse_env('repo') || parse_env('repos')
      if rv
        return rv.split(',').collect(&:to_sym)
      else
        repos = fetch(:repos)
        images = fetch(:images)
        return filtered_image_types.collect{|t| 
          rs = images[t][:repos]
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

  end
end

