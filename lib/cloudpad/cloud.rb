require 'yaml'
require 'fileutils'

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

  class Node < CloudElement

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

    def env_data
      options[:env] || {}
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
      fenv = self.env_data.collect do |key, val|
        "--env #{key}=#{val}"
      end.join(" ")
      return "#{fname} #{frst} #{fports} #{fvols} #{fcenv} #{fenv} #{cimg}"
    end

    def start_command(env)
      "sudo docker run -d --env APP_KEY=#{app_key} #{run_args(env)}"
    end

    def stop_command(env)
      "sudo docker stop #{name} && sudo docker rm #{name}"
    end

  end

end
