module Cloudpad

  module Docker

    def self.container_record(env, type, img_opts, inst_num, host)
      cr = {}
      cr["name"] = "#{img_opts[:name]}#{inst_num}"
      cr["image"] = "#{img_opts[:name]}:latest"
      cr["host"] = host.name
      # ports
      img_opts[:ports].each do |if_name, po|
        host_ip = host.internal_ip
        host_port = po[:hport] || po[:cport]
        ctnr_port = po[:cport]
        unless po[:no_range] == true
          host_port += inst_num
        end
        cr["#{if_name}_cport"] = "#{ctnr_port}"
        cr["#{if_name}_interface"] = "#{host_ip}:#{host_port}"
      end unless img_opts[:ports].nil?
      return cr
    end

  end

end
