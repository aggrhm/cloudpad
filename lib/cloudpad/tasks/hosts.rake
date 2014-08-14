namespace :hosts do

  task :load do
    set :cloud, Cloudpad::Cloud.new(env)
    cloud = fetch(:cloud)
    cloud.update
    hosts = cloud.hosts
    puts "#{hosts.length} hosts found.".green

    hosts.each do |s|
      #puts "ROLES: #{s.roles.inspect}"
      puts "- Registering #{s.internal_ip}(#{s.name}) as #{s.roles.join(",")}".green
      server s.internal_ip, roles: s.roles, user: s.user, source: s
    end
  end

  task :provision do
    invoke "hosts:ensure_docker"
    invoke "hosts:ensure_etcd"
  end

  task :ensure_docker do
    on roles(:host) do |host|
      if !test("sudo which docker")
        # docker not installed
        info "Docker not installed, installing..."
        execute "curl -sSL https://get.docker.io/ubuntu/ | sudo sh"
      end
    end
  end

  task :ensure_etcd do
    hosts = fetch(:cloud).hosts
    sidx = 0
    on roles(:host), in: :sequence do |server|
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
            execute "nohup ~/etcd/etcd --peer-addr #{ip}:7001 --addr #{ip}:4001 > etcd.log &"
          else
            execute "nohup ~/etcd/etcd --peer-addr #{ip}:7001 --addr #{ip}:4001 --peers #{leader_addr} > etcd.log &"
          end
        end
      end
      sidx += 1
    end
  end

end

Capistrano::DSL.stages.each do |stage|
  after stage, 'hosts:load'
end
