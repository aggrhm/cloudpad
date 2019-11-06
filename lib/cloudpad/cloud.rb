require 'yaml'
require 'fileutils'
require 'shellwords'

module Cloudpad

  class Cloud

    def initialize(env)
      @env = env
      @nodes = []
      @containers = []
    end

    def nodes
      @nodes
    end

    def hosts
      @nodes.select {|n| n.has_role?(:host)}
    end

    def containers
      @containers
    end

    def update
      @nodes = []
      @containers = []
      case @env.fetch(:cloud_provider)
      when :boxchief
        data = get_boxchief_cloud
      else
        data = get_cached_cloud
      end
      data[:containers] ||= []
      @nodes = data[:nodes]
      @containers = data[:containers]
      update_cache
    end

    def cache_file_path
      File.join(cloud_dir_path, "#{@env.fetch(:stage)}.yml")
    end

    def cloud_dir_path
      File.join(Dir.pwd, "config", "cloud")
    end

    def update_cache
      if !File.directory?(cloud_dir_path)
        FileUtils.mkdir_p(cloud_dir_path)
      end

      File.open(cache_file_path, "w") do |f|
        f.write({"nodes" => @nodes.collect(&:data), "containers" => @containers.collect(&:data)}.to_yaml)
      end
    end

    def get_cached_cloud
      return {nodes: [], containers: []} if !File.exists?(cache_file_path)
      data = YAML.load_file(cache_file_path)
      #puts data
      data["nodes"] ||= []
      data["containers"] ||= []
      return {
        nodes: data["nodes"].collect{|h| Node.new(h)},
        containers: data["containers"].collect{|h| Container.new(h)}
      }
    end

    def get_boxchief_cloud
      conn = Faraday.new(url: "http://boxchief.com") do |f|
        #f.response :logger
        f.adapter Faraday.default_adapter
      end

      ret = conn.get "/api/servers/list", {app_token: @env.fetch(:boxchief_app_token)}
      #puts ret.inspect
      #puts "BODY = #{ret.body}"
      resp = JSON.parse(ret.body)
      if resp["success"] == false
        raise "Boxchief Error: #{resp["error"]}"
      end

      hosts = resp["data"].collect do |sd|
        host = Node.new
        host[:name] = sd["hostname"]
        host[:external_ip] = sd["ip"]
        host[:roles] = sd["roles"]
        host[:cloud_provider] = "boxchief"
        host
      end
      return {nodes: servers}
    end

  end

  ## CLOUDELEMENT
  class CloudElement

    def initialize(opts={})
      @data = opts.stringify_keys
      #puts self.methods.inspect
      #puts "#{self.respond_to?(:roles)} - #{@data["roles"]}"
    end

    def data
      @data.to_hash
    end

    def [](field)
      @data[field.to_s]
    end

    def []=(field, val)
      @data[field.to_s] = val
    end

    def method_missing(name, *args)
      if name.to_s.ends_with?("=")
        @data[name.to_s[0..-2]] = args[0]
      else
        @data[name.to_s]
      end
    end

  end


  ## NODE
  class Node < CloudElement

    def self.prompt_add_node(c, opts={})
      cloud = c.fetch(:cloud)
      node = Cloudpad::Node.new
      node.name = c.prompt("Enter node name")
      node.external_ip = c.prompt("Enter external ip")
      node.internal_ip = c.prompt("Enter internal ip")
      node.roles = opts[:roles] || c.prompt("Enter roles (comma-separated)", "host").split(",").collect{|r| r.downcase.to_sym}
      node.user = c.prompt("Enter login user", "ubuntu")
      node.os = c.prompt("Enter node OS", "ubuntu")
      cloud.nodes << node
      cloud.update_cache
      puts "Node #{node.name} added."
    end

    def internal_ip
      self["internal_ip"] || self["external_ip"]
    end

    def roles
      (@data["roles"] || []).collect(&:to_sym)
    end

    def has_role?(rl)
      rl = [rl] unless rl.is_a?(Array)
      (self.roles & rl).length > 0
    end

    def has_id?(val)
      val = [val] unless val.is_a?(Array)
      ([internal_ip, external_ip, name] & val).length > 0
    end

    def status
      @status ||= {}
    end

  end

  ## CONTAINER
  class Container

    attr_accessor :host, :name, :instance, :type, :ports, :options, :image_options, :app_key, :state, :status, :ip_address

    def self.prepare(params, copts, img_opts, host)
      ct = self.new
      ct.type = params[:type]
      ct.instance = params[:instance]
      ct.app_key = params[:app_key]
      ct.host = host
      ct.options = copts
      ct.image_options = img_opts
      ct.state = :ready
      return ct
    end

    def name
      @name ||= "#{app_key}.#{type}.#{instance}"
    end

    def image_name
      "#{self.image_options[:name]}:latest"
    end

    def meta
      @meta ||= {}.with_indifferent_access
    end

    def ports
      @ports ||= begin
        # parse ports
        pts = []
        self.options[:ports].each do |if_name, po|
          host_port = po[:hport] || po[:cport]
          ctnr_port = po[:cport]
          unless po[:no_range] == true
            host_port += instance
          end
          pts << {name: if_name, container: ctnr_port, host: host_port}
        end unless self.options[:ports].nil?
        pts
      end
    end

    def volumes
      @volumes ||= begin
        vols = []
        self.options[:volumes].each do |name, vo|
          if vo[:cpath] && vo[:hpath]
            vols << {name: name, container: vo[:cpath], host: vo[:hpath]}
          elsif vo[:cpath]
            vols << {name: name, container: vo[:cpath], host: "/volumes/#{name}.#{instance}"}
          elsif vo[:hpath]
            vols << {name: name, container: vo[:hpath], host: vo[:hpath]}
          end
        end unless self.options[:volumes].nil?
        vols
      end
    end

    def container_env_data
      ret = {
        "name" => name,
        "type" => type,
        "instance" => instance,
        "image" => image_name,
        "host" => host.name,
        "host_ip" => host.internal_ip,
        "ports" => ports.collect{|p| p[:name].to_s}.join(","),
      }
      ret["services"] = options[:services].join(",") if options[:services]
      ports.each do |p|
        ret["port_#{p[:name]}_c"] = p[:container]
        ret["port_#{p[:name]}_h"] = p[:host]
      end
      return ret
    end

    def env_data(ctx=nil)
      ret = options[:env] || {}
      if ctx
        vars = ctx.fetch(:container_env_vars)
        vars.each do |nm, var|
          ret[nm] = ctx.fetch(var)
        end
      end
      return ret
    end

    def run_args(env)
      cname = self.name
      cimg = "#{env.fetch(:registry)}/#{self.image_name}"
      fname = "--name #{cname}"
      frst = "--restart=always"
      fports = self.ports.collect { |port|
        cp = port[:container]
        hp = port[:host]
        "-p #{hp}:#{cp}"
      }.join(" ")
      fvols = self.volumes.collect{ |vol|
        cp = vol[:container]
        hp = vol[:host]
        "-v #{hp}:#{cp}"
      }.join(" ")
      fcenv = self.container_env_data.collect do |key, val|
        "--env CNTR_#{key.upcase}=#{val}"
      end.join(" ")
      fenv = self.env_data(env).collect do |key, val|
        qval = Shellwords.escape(val)
        "--env #{key}=#{qval}"
      end.join(" ")
      custargs = options[:custom_args] || ""
      return "#{fname} #{frst} #{fports} #{fvols} #{fcenv} #{fenv} #{custargs} #{cimg}"
    end

    def start_command(env)
      "sudo docker run -d #{run_args(env)}"
    end

    def stop_command(env)
      "sudo docker stop #{name} && sudo docker rm #{name}"
    end

    def to_hash
      ret = {}
      ret[:name] = name
      ret[:host] = host
      ret[:instance] = instance
      ret[:type] = type
      ret[:options] = options
      ret[:meta] = meta
      ret[:app_key] = app_key
      ret[:state] = state
      ret[:ip_address] = ip_address
      return ret
    end

  end

  ## CONFIG CLASSES

  class ConfigElement

    attr_reader :options

    def self.map
      Cloudpad.context.fetch(self.config_name)
    end

    def self.add(id, opts)
      opts[:id] = id
      self.map[id] = self.new(opts)
    end

    def self.with_ids(ids)
      ids ||= []
      self.map.values.select {|e| ids.include?(e.id)}
    end

    def initialize(opts={})
      @context = Cloudpad.context
      @options = opts.with_indifferent_access
      prepare_options
    end

    def id
      @options[:id]
    end

    def [](field)
      @options[field]
    end

    def []=(field, val)
      @options[field] = val
    end

    def prepare_options
    end

  end
  class Group < ConfigElement
    def self.map
      Cloudpad.context.fetch(:groups)
    end
    def prepare_options
      opts = @options
      opts[:env] ||= {}
    end
  end
  
  class Image < ConfigElement
    def self.map
      Cloudpad.context.fetch(:images)
    end
    def prepare_options
      opts = @options
      opts[:env] ||= {}
      opts[:files] ||= []
      opts[:writable_dirs] ||= []
      opts[:df_post_scripts] ||= []
      opts[:files].each do |f|
        f[:context] ||= f[:local]
      end
    end
    def tag
      self[:tag]
    end
    def name_with_tag
      "#{self[:name]}:#{self[:tag]}"
    end
    def image_uri(opts={})
      c = Cloudpad.context
      reg = c.fetch(:registry_url)
      ns = c.fetch(:registry_namespace)
      nt = name_with_tag
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

    def build!(opts={})
      tag = opts[:tag]
      no_cache = opts[:no_cache] == true

      c = Cloudpad.context
      puts "Building #{id} image...".yellow
      c.set :building_image, self

      # clear context dir
      c.sh "rm -rf #{c.context_path}"
      c.sh "mkdir #{c.context_path}"
      File.write(File.join(c.context_path, ".build-info"), Time.now.to_s)

      # install extensions
      c.install_context_extensions

      # install context files
      self[:files].each do |fopts|
        next if fopts[:local].blank?
        cp = File.join(c.context_path, (fopts[:context] || fopts[:local]))
        if fopts[:template] == true
          c.write_template_file(fopts[:local], cp)
        else
          puts "Adding context file #{cp}"
          c.sh "mkdir -p `dirname #{cp}` && cp -a #{fopts[:local]} #{cp}"
        end
      end

      # if repo, clone and append git hash to tag
      if self[:repos]
        self[:repos].each do |rid, ropts|
          repo = Cloudpad::Repo.map[rid]
          repo.add_to_context!
        end
        rid = self[:repos].keys.first
        repo = Cloudpad::Repo.map[rid]
        if repo[:type] == :git || repo[:type].nil?
          repo_path = repo.context_path
          sha1 = `git --git-dir #{repo_path}/.git rev-parse --short HEAD`.strip
          tag += "-#{sha1}"
        end
      end

      if !self[:tag_forced]
        self[:tag] = tag
        self[:name_with_tag] = "#{self[:name]}:#{self[:tag]}"
      end

      # write service files
      FileUtils.mkdir_p( File.join(c.context_path, 'services') )
      svs = (self[:services] || []) | (self[:available_services] || [])
      svs.each do |svcid|
        svc = Cloudpad::Service.map[svcid]
        raise "Service not found: #{svcid}!" if svc.nil?
        svc.add_to_context!
      end

      # write dockerfile to context
      mt = self[:manifest] || type
      df_path = File.join(c.manifests_path, "#{mt.to_s}.dockerfile")
      df_str = c.build_template_file(df_path)
      cdf_path = File.join(c.context_path, "Dockerfile")
      File.open(cdf_path, "w") {|fp| fp.write(df_str)}
      cache_opts = no_cache ? "--no-cache " : ""

      c.sh "sudo docker build -t #{self[:name_with_tag]} --network host #{cache_opts}#{c.context_path}"

      # write image info to build
      FileUtils.mkdir_p( c.build_image_path ) if !File.directory?(c.build_image_path)
      img_build_path = File.join(c.build_image_path, self[:name])
      File.write(img_build_path, {id: id, tag: self[:tag]}.to_json)

      c.set :building_image, nil
    end

    def push_to_registry!
      c = Cloudpad.context
      dvm = c.docker_version_meta
      tag_cmd = (dvm[:major] == 1 && dvm[:minor] < 13) ? 'tag  -f' : 'tag'
      reg_uri = self.image_uri
      c.sh "sudo docker #{tag_cmd} #{name_with_tag} #{reg_uri}"
      c.sh "sudo docker push #{reg_uri}"
    end
  end

  class Repo < ConfigElement
    def self.map
      Cloudpad.context.fetch(:repos)
    end
    def context_path
      File.join(Cloudpad.context.repos_path, id)
    end
    def add_to_context!(opts={})
      c = Cloudpad.context
      rpath = context_path
      puts "Downloading #{id} repository to context...".yellow
      if self[:type] == :tar
        tar_path = "/tmp/#{id}#{File.extname(self[:url])}"
        c.sh "wget #{self[:url]} -O #{tar_path}"
        c.sh "tar -C /tmp -zxvf #{tar_path}"
        c.sh "mkdir -p #{c.repos_path} && mv /tmp/#{self[:root]} #{rpath}"
      else
        c.sh "git clone --depth 1 --branch #{self[:branch] || 'master'} #{self[:url]} #{rpath}"
      end
      # run scripts
      if self[:scripts]
        self[:scripts].each do |script|
          c.clean_shell "cd #{rpath} && #{script}"
        end
      end

    end
  end

  class Service < ConfigElement
    def self.map
      Cloudpad.context.fetch(:services)
    end
    def context_path
      File.join(context_path, 'services', "#{id}.sh")
    end
    def add_to_context!(opts={})
      ofp = context_path
      cmd = self[:command]
      ostr = "#!/bin/bash\n#{cmd}"
      if !File.exists?(ofp) || ostr != File.read(ofp)
        File.write(ofp, ostr)
        File.chmod(0755, ofp)
      end
    end
  end

end
