module Cloudpad

  module Docker

    module Context

      def self.install_docker(c)
        ver_meta = c.docker_version_meta
        insecure = c.fetch(:insecure_registry)
        registry = c.fetch(:registry)
        insecure_flag = insecure ? "--insecure-registry #{registry}" : ""
        cfr = "/etc/default/docker"
        cfl = File.join(c.context_path, "conf", "docker.conf")

        # install docker if needed
        if !c.test("sudo which docker")
          c.info "Docker not installed, installing..."
          c.execute "sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D"
          c.execute "sudo sh -c \"echo deb https://apt.dockerproject.org/repo ubuntu-trusty main > /etc/apt/sources.list.d/docker.list\""
          c.execute "sudo apt-get update"
          c.execute "sudo apt-get install -y linux-image-extra-`uname -r` apt-transport-https"
          c.execute "sudo apt-get install -y docker-engine=#{ver_meta[:version]}"
        end

        # check if configuration changed
        cflc = c.local_file_content(cfl, parse_erb: true)
        cfrc = c.remote_file_content(cfr)
        if cflc && cflc != cfrc
          c.info "Docker configuration changed. Updating and restarting docker..."
          c.upload_string!(cflc, "/tmp/docker.conf")
          c.execute "sudo cp /tmp/docker.conf #{cfr}"
          c.execute "sudo service docker restart"
        end
      end

      def self.remove_docker(c)
        c.execute "sudo apt-get -y purge lxc-docker-*"
        c.execute "sudo apt-get -y purge docker-engine"
      end

      def self.check_running(c, opts={})
        containers = []
        c.on(c.roles(:host)) do |server|
          host = server.properties.source
          host.status[:free_mem] = capture("free -m | grep Mem | awk '{print $4}'").to_i
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
              ci.host = host
              ci.app_key = ak
              ci.options = c.fetch(:container_types)[type.to_sym]
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
            img_data = capture("sudo docker ps #{img_ids.join(" ")}")
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
        end
        return containers

      end

      def self.check_launcher_images(c)
        images = c.fetch(:images)
        images.each do |type, iopts|
          img_id = `sudo docker images -q #{iopts[:name]}:latest`.strip
          if img_id != ""
            iopts[:latest_id] = img_id
            info = JSON.parse(`sudo docker inspect #{img_id}`).first
            iopts[:latest_info] = info
            iopts[:latest_created] = info["Created"]
          end
        end
      end

      def self.compute_container_changes(c)
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
            hosts.each do |h|
              ic.times do |idx|
                inst = idx + 1
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
        excs.select{|c| c[:accounted == true} each do |c|
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

      def self.add_container(c, opts)
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

      def self.remove_container(c, opts={})
        name = opts[:name]
        type = opts[:type]

        c.on c.roles(:host) do |server|
          host = server.properties.source
          c.containers_on_host(host).each do |ct|
            execute ct.stop_command(c) if ( (type && ct.type == type.to_sym) || (name && ct.name == name) )
          end
        end
      end

      def self.update_container(c, opts={})
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

      def self.execute_container_change(c, change)
        case change[:action].to_sym
        when :create
          Cloudpad::Docker::Context.add_container(c, change[:spec])
        when :delete
          Cloudpad::Docker::Context.remove_container(c, {name: change[:spec][:name]})
        when :update
          Cloudpad::Docker::Context.update_container(c, {name: change[:spec][:name]})
        end
      end
      

    end

    def self.container_record(env, type, img_opts, inst_num, host)
      cr = {}
      app_key = env.fetch(:app_key)
      cr["name"] = "#{app_key}.#{type.to_s}.#{inst_num}"
      cr["image"] = "#{img_opts[:name]}:latest"
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
