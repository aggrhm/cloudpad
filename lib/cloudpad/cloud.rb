require 'yaml'
require 'fileutils'

module Cloudpad

  class Cloud

    def initialize(env)
      @env = env
      @hosts = []
      @containers = []
    end

    def hosts
      @hosts
    end

    def containers
      @containers
    end

    def update
      @hosts = []
      @containers = []
      case @env.fetch(:cloud_provider)
      when :boxchief
        data = get_boxchief_cloud
      else
        data = get_cached_cloud
      end
      data[:containers] ||= []
      @hosts = data[:hosts]
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
        f.write({"hosts" => @hosts.collect(&:data), "containers" => @containers.collect(&:data)}.to_yaml)
      end
    end

    def get_cached_cloud
      return {hosts: [], containers: []} if !File.exists?(cache_file_path)
      data = YAML.load_file(cache_file_path)
      #puts data
      data["hosts"] ||= []
      data["containers"] ||= []
      return {
        hosts: data["hosts"].collect{|h| Host.new(h)},
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

      servers = resp["data"].collect do |sd|
        server = {}
        server[:name] = sd["hostname"]
        server[:external_ip] = sd["ip"]
        server[:roles] = sd["roles"]
        server[:cloud_provider] = "boxchief"
        Host.new(server)
      end
      return {hosts: servers}
    end

  end

  ## CLOUDELEMENT
  class CloudElement

    def initialize(opts)
      @data = opts.with_indifferent_access
      #puts self.methods.inspect
      #puts "#{self.respond_to?(:roles)} - #{@data["roles"]}"
    end

    def data
      @data.to_hash
    end

    def [](field)
      @data[field]
    end

    def method_missing(name, *args)
      if name.to_s.ends_with?("=")
        @data[name.to_s] = args[0]
      else
        @data[name.to_s]
      end
    end

  end

  class Host < CloudElement

    def internal_ip
      self[:internal_ip] || self[:external_ip]
    end

    def roles
      (@data[:roles] || []).collect(:&to_sym)
    end

    def has_id?(val)
      val = [val] unless val.is_a?(Array)
      ([internal_ip, external_ip, name] & val).length > 0
    end

  end

  class Container < CloudElement

  end

end
