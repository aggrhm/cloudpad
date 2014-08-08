namespace :hosts do

  task :load do
    set :cloud, Cloudpad::Cloud.new(env)
    cloud = fetch(:cloud)
    cloud.update
    hosts = cloud.hosts
    puts "#{hosts.length} hosts found.".green

    hosts.each do |s|
      #puts "ROLES: #{s.roles.inspect}"
      puts "- Registering #{s.external_ip}(#{s.name}) as #{s.roles.join(",")}".green
      server s.external_ip, roles: s.roles, user: s.user, source: s
    end
  end

  task :ensure_docker do
    on roles(:host) do |host|
      path = capture "sudo which docker"
      if path.strip.length == 0
        # docker not installed
        info "Docker not installed, installing..."
        execute "curl -sSL https://get.docker.io/ubuntu/ | sudo sh"
      end
    end
  end

  task :ensure_etcd do
    hosts = fetch(:cloud).hosts
    on roles(:host), in: :sequence do |server|
      host = server.properties.source
      within "~" do
        if !test("[ -d etcd ]")
          info "Etcd not installed. installing"
          execute "curl -L https://github.com/coreos/etcd/releases/download/v0.4.6/etcd-v0.4.6-linux-amd64.tar.gz | tar -zxf -"
          execute "mv etcd-* etcd"
        end
        if !process_running?("etcd/etcd")
          peers_str = hosts.select{|h| h.internal_ip != host.internal_ip}.collect{|h| "#{h.internal_ip}:7001"}.join(",")
          execute "~/etcd/etcd --peers #{peers_str} &"
        end
      end
    end
  end

end

Capistrano::DSL.stages.each do |stage|
  after stage, 'hosts:load'
end
