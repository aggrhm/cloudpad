module Cloudpad
  module TaskUtils

    def root_path
      Dir.pwd
    end
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
      insts[inst].call(*args)
    end

    def filtered_container_types
      cts = fetch(:container_types)
      return cts.keys if ENV['type'].nil?
      tf = ENV['type'].split(',').collect(&:to_sym)
    end

    def filtered_image_types
      ims = fetch(:images)
      cts = fetch(:container_types)
      return filtered_container_types.collect{|t| cts[t][:image]}.uniq
    end

    ## on host

    def process_running?(name)
      test("ps -ef | grep #{name} | grep -v \"grep\"")
    end
    def clean_shell(cmd)
      sh "env -i /bin/bash -l -c \"#{cmd}\""
    end

  end
end

