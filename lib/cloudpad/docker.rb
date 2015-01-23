module Cloudpad

  module Docker

    module Context

      def self.install_docker(c)
        ver_meta = c.docker_version_meta
        insecure = c.fetch(:insecure_registry)
        registry = c.fetch(:registry)
        insecure_flag = insecure ? "--insecure-registry #{registry}" : ""

        # install docker if needed
        if !c.test("sudo which docker")
          c.info "Docker not installed, installing..."
          c.execute "sudo apt-get update"
          c.execute "sudo apt-get install -y linux-image-extra-`uname -r` apt-transport-https"
          c.execute "sudo sh -c \"wget -qO- https://get.docker.io/gpg | apt-key add -\""
          c.execute "sudo sh -c \"echo deb http://get.docker.io/ubuntu docker main > /etc/apt/sources.list.d/docker.list\""
          c.execute "sudo apt-get update"
          c.execute "sudo apt-get install -y lxc-docker-#{ver_meta[:version]}"
        end
        if ver_meta[:major] > 1 || ver_meta[:minor] > 2
          # update docker config
          c.replace_file_line("/etc/default/docker", "DOCKER_OPTS=", "DOCKER_OPTS='#{insecure_flag}'", {sudo: true})
          # restart docker properly
          c.execute "sudo service docker restart"
        end
      end

      def self.remove_docker(c)
        c.execute "sudo apt-get -y purge lxc-docker-*"
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
