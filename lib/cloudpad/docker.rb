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
