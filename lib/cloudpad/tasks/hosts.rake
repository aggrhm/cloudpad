namespace :hosts do

  task :load do
    set :cloud, Cloudpad::Cloud.new(env)
    cloud = fetch(:cloud)
    cloud.update
    hosts = cloud.hosts
    host_key = File.join(context_path, "keys", "host.key")
    has_host_key = File.exists?(host_key)
    puts "#{hosts.length} hosts found.".green
    role_filter = ENV['ROLES'] || ENV['NODE_ROLES']
    if role_filter
      role_filter = role_filter.split(",").collect{|r| r.downcase.to_sym}
    end

    hosts.each do |s|
      next if role_filter && (s.roles & role_filter).length == 0
      puts "- Registering #{s.internal_ip}(#{s.name}) as #{s.roles.join(",")}".green
      sopts = {}
      sopts[:roles] = s.roles
      sopts[:user] = s.user
      sopts[:source] = s
      sopts[:ssh_options] = {keys: [host_key]} if has_host_key
      server s.internal_ip, sopts
    end
  end

  task :add do
    Cloudpad::Context.prompt_add_node(self, roles: [:host])
  end

  task :provision do
    invoke "hosts:ensure_ntp"
    invoke "hosts:ensure_docker"
    #invoke "hosts:ensure_etcd"   # now ran at launcher
    invoke "hosts:ensure_nfs"
  end

  task :ensure_docker do
    on roles(:host) do |host|
      Cloudpad::Docker::Context.install_docker(self)
    end
  end

  task :remove_docker do
    on roles(:host) do |host|
      Cloudpad::Docker::Context.remove_docker(self)
    end
  end

  task :local_docker do
    insecure = fetch(:insecure_registry)
    registry = fetch(:registry)
    insecure_flag = insecure ? "--insecure-registry #{registry}" : ""
    run_locally do
      # update docker config
      replace_file_line("/etc/default/docker", "DOCKER_OPTS=", "DOCKER_OPTS='#{insecure_flag}'", {sudo: true})
      # restart docker properly
      execute "sudo service docker restart"
    end
  end

  task :ensure_etcd do
    hosts = fetch(:cloud).hosts
    sidx = 0
    on roles(:host), in: :sequence, wait: 5 do |server|
      host = server.properties.source
      within "~" do
        if !test("[ -d etcd ]")
          info "Etcd not installed, installing..."
          execute "curl -L https://github.com/coreos/etcd/releases/download/v0.4.6/etcd-v0.4.6-linux-amd64.tar.gz | tar -zxf -"
          execute "mv etcd-* etcd"
        end
        if !process_running?("etcd/etcd")
          info "Etcd not running, starting..."
          leader_addr = "#{hosts.first.internal_ip}:7001"
          ip = host.internal_ip
          if host == hosts.first
            peers_f = ""
          else
            peers_f = "--peers #{leader_addr}"
          end
          execute "nohup ~/etcd/etcd --peer-addr #{ip}:7001 --peer-bind-addr 0.0.0.0:7001 --addr #{ip}:4001 --bind-addr 0.0.0.0:4001 #{peers_f} -f > etcd.log &"
        end
      end
      sidx += 1
    end
  end

  task :ensure_nfs do
    shared_path = fetch(:nfs_shared_path)
    if shared_path.nil?
      next
    end
    host_subnet = fetch(:host_subnet)
    deploy_ip = local_ip_address

    # install server locally
    run_locally do
      execute "sudo apt-get install -qy nfs-kernel-server"
      if !test("[ -d #{shared_path} ]")
        execute "sudo mkdir #{shared_path}" 
        execute "sudo chmod a+w #{shared_path}"
      end
      execute "echo \"#{shared_path} #{host_subnet}(rw,all_squash)\" | sudo tee /etc/exports > /dev/null"
      execute "sudo service nfs-kernel-server restart"
    end

    # mount path remotely
    on roles(:host) do
      if !test("mount -l | grep #{shared_path}")
        execute "sudo apt-get install -qy nfs-common"
        execute "sudo mkdir #{shared_path}" unless test("[ -d #{shared_path} ]")
        execute "sudo mount #{deploy_ip}:#{shared_path} #{shared_path}"
      end
    end

  end

  task :ensure_ntp do
    on roles(:host) do
      if !is_package_installed?("ntp")
        execute "sudo apt-get install -qy ntp"
      end
    end
  end

  task :clean do
    on roles(:host) do
      execute "sudo docker rmi $(sudo docker images -q --filter \"dangling=true\")"
    end
  end

end

Capistrano::DSL.stages.each do |stage|
  after stage, 'hosts:load'
end
