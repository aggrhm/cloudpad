module Cloudpad
  module TaskUtils

    def manifests_path
      File.join(Dir.pwd, "manifests")
    end
    def context_path
      File.join(Dir.pwd, "context")
    end
    def cloud_path
      File.join(Dir.pwd, "config", "cloud")
    end
    def repos_path
      File.join(context_path, "src")
    end

    def prompt(question)
      $stdout.print "> #{question}: ".yellow
      return $stdin.gets.chomp
    end

    def build_template_file(name)
      ERB.new(File.read(name)).result(binding)
    end

    def clear_cache
      "RUN echo \"#{Time.now.to_s}\""
    end

    def image_opts
      fetch(:images)[fetch(:building_image)]
    end

    def building_image?(img)
      fetch(:building_image) == img
    end

    def container_public_key
      kp = File.join(context_path, "keys", "container.pub")
      return File.read(kp).gsub("\n", "")
    end

    def next_available_server
      hm = {}
      servers = roles(:host)
      servers.each do |server|
        hm[server.properties.source.name] = 0
      end

      fetch(:running_containers).each do |ci|
        hm[ci["host"]] += 1
      end

      mv = hm.values.min
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

    def next_available_container_instance(type)
      taken = fetch(:running_containers).select{|c| c["type"] == type}.collect{|c| c["instance"]}.sort
      num = 1
      while(taken.include?(num)) do
        num += 1
      end
      return num
    end

    ## on host

    def process_running?(name)
      ret = capture("ps -ef | grep #{name} | grep -v \"grep\"")
      return ret.strip.length > 0
    end

  end
end

