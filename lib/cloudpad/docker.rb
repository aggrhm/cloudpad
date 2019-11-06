module Cloudpad

  module Docker

    def self.install_docker(r)
      c = Cloudpad.context
      ver_meta = c.docker_version_meta
      insecure = c.fetch(:insecure_registry)
      registry = c.fetch(:registry)
      insecure_flag = insecure ? "--insecure-registry #{registry}" : ""
      cfr = "/etc/default/docker"
      cfl = File.join(c.context_path, "conf", "docker.conf")

      # install docker if needed
      if !r.test("sudo which docker")
        r.info "Docker not installed, installing..."
        r.execute "sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D"
        r.execute "sudo sh -c \"echo deb https://apt.dockerproject.org/repo ubuntu-trusty main > /etc/apt/sources.list.d/docker.list\""
        r.execute "sudo apt-get update"
        r.execute "sudo apt-get install -y linux-image-extra-`uname -r` apt-transport-https"
        r.execute "sudo apt-get install -y docker-engine=#{ver_meta[:version]}"
      end

      # check if configuration changed
      cflc = c.local_file_content(cfl, parse_erb: true)
      cfrc = c.remote_file_content(cfr)
      if cflc && cflc.strip != cfrc.strip
        r.info "Docker configuration changed. Updating and restarting docker..."
        r.upload_string!(cflc, "/tmp/docker.conf")
        r.execute "sudo cp /tmp/docker.conf #{cfr}"
        r.execute "sudo service docker restart"
      end
    end

    def self.remove_docker(r)
      c = Cloudpad.context
      r.execute "sudo apt-get -y purge lxc-docker-*"
      r.execute "sudo apt-get -y purge docker-engine"
    end

    def self.check_running(opts={})
      c = Cloudpad.context
      containers = []
      c.on(c.roles(:host)) do |server|
        host = server.properties.source
        host.status[:free_mem] = capture("free -m | grep Mem | awk '{print $4}'").to_i
        host.status[:free_root_disk] = (capture("df -k / | tail -n 1 | awk '{print $4}'").to_i / 1024.0 / 1024.0).round(1)
        ids = capture("sudo docker ps -q").strip
        if ids.length > 0
          hd = capture("sudo docker inspect $(sudo docker ps -q)")
        else
          hd = "[]"
        end
        img_ids = []
        # parse container info
        JSON.parse(hd).each do |cs|
          cn = cs["Name"].gsub("/", "")
          ip = cs["NetworkSettings"]["IPAddress"]
          img_id = cs["Image"]
          img_ids << img_id
          ak, type, inst = cn.split(".")
          if ak == c.fetch(:app_key)
            ci = Cloudpad::Container.new
            # this is a container we manage, add it to list
            unless ci.options = c.fetch(:container_types)[type.to_sym]
              puts "Type #{type} not found in deploy".red
              next
            end

            ci.host = host
            ci.app_key = ak
            ci.image_options = c.fetch(:images)[ci.options[:image]]
            ci.name = cn
            ci.type = type.to_sym
            ci.instance = inst.to_i
            ci.ip_address = ip
            ci.state = :running
            ci.meta["image_id"] = img_id
            containers << ci
          end
        end
        # fetch image info
        img_ids = img_ids.uniq.compact
        if img_ids.length > 0
          img_data = capture("sudo docker inspect #{img_ids.join(" ")}")
          JSON.parse(img_data).each do |inf|
            containers.select{|c| c.meta["image_id"] == inf["Id"]}.each do |c|
              c.meta["image_info"] = inf
              c.meta["image_created"] = inf["Created"]
            end
          end
        end
      end
      puts "#{containers.length} containers running in #{c.fetch(:stage)} for this application.".green
      puts containers.collect{|c| "- #{c.name} (on #{c.host.name} at #{c.ip_address}) : #{c.type}"}.join("\n").green
      c.set :running_containers, containers
      # host info
      puts "Host Summary:".green
      c.fetch(:cloud).hosts.each do |host|
        cs = c.containers_on_host(host)
        puts "- #{host.name}: #{cs.length} containers running | #{host.status[:free_mem]} MB RAM free".green
        if host.status[:free_root_disk] < 1
          puts "Warning: #{host.name} disk space remaining: #{host.status[:free_root_disk]} GB".red
        end
      end
      # check launcher
      launcher_root_free = nil
      run_locally do
        launcher_root_free = (capture("df -k / | tail -n 1 | awk '{print $4}'").to_i / 1024.0 / 1024.0).round(1)
      end
      if launcher_root_free && launcher_root_free < 1
        puts "Warning: Launcher disk space remaining: #{launcher_root_free} GB".red
      end
      return containers

    end

    def self.check_launcher_images
      c = Cloudpad.context
      images = c.fetch(:images)
      images.each do |type, iopts|
        img_id = `sudo docker images -q #{iopts[:name_with_tag]}`.strip
        if img_id != ""
          iopts[:latest_id] = img_id
          info = JSON.parse(`sudo docker inspect #{img_id}`).first
          iopts[:latest_info] = info
          iopts[:latest_created] = info["Created"]
        end
      end
    end

    def self.clean_images(r)
      c = Cloudpad.context
      dvm = c.docker_version_meta
      if dvm[:major] == 1 && dvm[:minor] < 13
        r.execute "sudo docker images --quiet --filter=dangling=true | sudo xargs --no-run-if-empty docker rmi"
      else
        r.execute "sudo docker image prune -f"
      end
    end

    def self.compute_container_changes
      c = Cloudpad.context
      changes = []
      app_key = c.fetch(:app_key)
      cts = c.fetch(:running_containers)
      ctopts = c.fetch(:container_types)
      cloud = c.fetch(:cloud)
      images = c.fetch(:images)
      excs = []
      atcs = {}
      # determine expected containers
      ctopts.each do |type, copts|
        ic = copts[:instance_count] || 0
        ifls = copts[:instance_flags] || []
        hosts = copts[:hosts] || cloud.hosts.collect{|h| h.name}
        image_id = images[copts[:image]][:latest_created]
        if ifls.include?(:count_per_host)
          hinst = 0
          inst = 0
          hosts.each do |h|
            hinst = inst
            ic.times do |idx|
              inst = hinst + idx + 1
              name = "#{app_key}.#{type}.#{inst}"
              excs << {type: type, instance: inst, hosts: [h], name: name, image_id: image_id, accounted: false}
            end
          end
        else
          ic.times do |idx|
            inst = idx + 1
            name = "#{app_key}.#{type}.#{inst}"
            excs << {type: type, instance: inst, hosts: hosts, name: name, image_id: image_id, accounted: false}
          end
        end
      end

      # compile actual containers
      cts.each do |c|
        ck = "#{c.host.name}+#{c.type}+#{c.instance}"
        atcs[ck] = {type: c.type, instance: c.instance, host: c.host.name, name: c.name, image_id: c.meta["image_created"], accounted: false}
      end

      # account containers
      excs.each do |c|
        c[:hosts].each do |h|
          ck = "#{h}+#{c[:type]}+#{c[:instance]}"
          if (atc = atcs[ck])
            c[:accounted] = true
            c[:actual] = atc
            atc[:accounted] = true
            break
          end
        end
      end

      # update accounted expected
      excs.select{|c| c[:accounted] == true}.each do |c|
        if c[:image_id] != c[:actual][:image_id]
          # needs to update instance
          changes << {action: :update, spec: c[:actual]}
        end
      end

      # create unaccounted expected
      excs.select{|c| c[:accounted] != true}.each do |c|
        changes << {action: :create, spec: c}
      end

      # delete unaccounted actual
      atcs.values.select{|c| c[:accounted] != true}.each do |c|
        changes << {action: :delete, spec: c}
      end

      c.set :pending_container_changes, changes
      return changes
    end

    def self.add_container(opts)
      c = Cloudpad.context
      type = opts[:type]
      count = opts[:count] || 1
      inst = opts[:instance] || c.next_available_container_instance(type)
      host_filter = opts[:hosts]

      copts = c.fetch(:container_types)[type]
      img_opts = c.fetch(:images)[copts[:image]]
      app_key = c.fetch(:app_key)
      (1..count).each do
        server = c.next_available_server(type, host_filter)
        if server.nil?
          puts "No server available (check image host parameters)".red
          break
        end
        c.on server do |server|
          host = server.properties.source
          ct = Cloudpad::Container.prepare({type: type, instance: inst, app_key: app_key}, copts, img_opts, host)
          execute ct.start_command(c)
        end
        puts "Waiting for container to initialize...".yellow
        sleep 3
      end

    end

    def self.remove_container(opts={})
      c = Cloudpad.context
      name = opts[:name]
      type = opts[:type]

      c.on c.roles(:host) do |server|
        host = server.properties.source
        c.containers_on_host(host).each do |ct|
          execute ct.stop_command(c) if ( (type && ct.type == type.to_sym) || (name && ct.name == name) )
        end
      end
    end

    def self.update_container(opts={})
      c = Cloudpad.context
      name = opts[:name]
      type = opts[:type]

      c.on c.roles(:host) do |server|
        host = server.properties.source
        c.containers_on_host(host).each do |ct|
          if (type && ct.type == type.to_sym) || (name && ct.name == name)
            execute ct.stop_command(c)
            execute ct.start_command(c)
          end
        end
      end
    end

    def self.execute_container_change(change)
      c = Cloudpad.context
      case change[:action].to_sym
      when :create
        Cloudpad::Docker.add_container(change[:spec])
      when :delete
        Cloudpad::Docker.remove_container({name: change[:spec][:name]})
      when :update
        Cloudpad::Docker.update_container({name: change[:spec][:name]})
      end
    end


    def self.container_record(type, img_opts, inst_num, host)
      env = Cloudpad.context
      cr = {}
      app_key = env.fetch(:app_key)
      cr["name"] = "#{app_key}.#{type.to_s}.#{inst_num}"
      cr["image"] = "#{img_opts[:name_with_tag]}"
      cr["instance"] = inst_num
      cr["host"] = host.name
      cr["host_ip"] = host.internal_ip
      cr["ports"] = []
      # ports
      img_opts[:ports].each do |if_name, po|
        cr["ports"] << if_name
        host_port = po[:hport] || po[:cport]
        ctnr_port = po[:cport]
        unless po[:no_range] == true
          host_port += inst_num
        end
        cr["port_#{if_name}_c"] = "#{ctnr_port}"
        cr["port_#{if_name}_h"] = "#{host_port}"
      end unless img_opts[:ports].nil?
      return cr
    end

  end

end
