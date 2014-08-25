namespace :docker do

  ### ADD
  desc "Add docker containers on most available host"
  task :add do
    type = ENV['type'].to_sym
    count = ENV['count'] ? ENV['count'].to_i : 1
    filt = ENV['chost'] ? ENV['chost'].split(',') : nil
    copts = fetch(:container_types)[type]
    img_opts = fetch(:images)[copts[:image]]
    app_key = fetch(:app_key)
    (1..count).each do
      server = next_available_server(type, filt)
      if server.nil?
        puts "No server available (check image host parameters)".red
        break
      end
      on server do |server|
        host = server.properties.source
        inst = next_available_container_instance(type)
        ct = Cloudpad::Container.prepare({type: type, instance: inst, app_key: app_key}, copts, img_opts, host)
        execute ct.start_command(env)
      end
      puts "Waiting for container to initialize...".yellow
      sleep 3
      Rake::Task["docker:check_running"].execute
    end
  end


  ### REMOVE
  desc "Stop and remove all containers running on hosts for this application"
  task :remove do
    name = ENV['name']
    type = ENV['type']

    on roles(:host) do |server|
      host = server.properties.source
      containers_on_host(host).each do |ct|
        execute ct.stop_command(env) if ( (type && ct.type == type.to_sym) || (name && ct.name == name) )
      end
    end
    Rake::Task["docker:check_running"].execute
  end


  ### UPDATE
  desc "Update running containers"
  task :update do
    tf = ENV['type'].split(',') if ENV['type']
    cts = fetch(:running_containers).select {|c|
      tf.nil? || tf.include?(c.type.to_s)
    }

    on roles(:host) do |server|
      host = server.properties.source
      cts.each do |ct|
        if ct.host == host
          # stop container
          execute ct.stop_command(env)
          execute ct.start_command(env)
        end
      end
    end
    Rake::Task["docker:check_running"].execute
  end

  ### DEPLOY
  task :deploy do
    invoke "docker:build"
    invoke "docker:update"
  end


  ### CHECK_RUNNING
  desc "Check running containers"
  task :check_running do
    containers = []
    on roles(:host) do |server|
      host = server.properties.source
      host.status[:free_mem] = capture("free -m | grep Mem | awk '{print $4}'").to_i
      ids = capture("sudo docker ps -q").strip
      if ids.length > 0
        hd = capture("sudo docker inspect $(sudo docker ps -q)")
      else
        hd = "[]"
      end
      # parse container info
      JSON.parse(hd).each do |cs|
        cn = cs["Name"].gsub("/", "")
        ip = cs["NetworkSettings"]["IPAddress"]
        ak, type, inst = cn.split(".")
        if ak == fetch(:app_key)
          ci = Cloudpad::Container.new
          # this is a container we manage, add it to list
          ci.host = host
          ci.app_key = ak
          ci.options = fetch(:container_types)[type.to_sym]
          ci.image_options = fetch(:images)[ci.options[:image]]
          ci.name = cn
          ci.type = type.to_sym
          ci.instance = inst.to_i
          ci.ip_address = ip
          ci.state = :running
          containers << ci
        end
      end
    end
    puts "#{containers.length} containers running in #{fetch(:stage)} for this application.".green
    puts containers.collect{|c| "- #{c.name} (on #{c.host.name} at #{c.ip_address}) : #{c.type}"}.join("\n").green
    set :running_containers, containers
    # host info
    puts "Host Summary:".green
    fetch(:cloud).hosts.each do |host|
      cs = containers_on_host(host)
      puts "- #{host.name}: #{cs.length} containers running | #{host.status[:free_mem]} MB RAM free".green
    end
  end

  ### LIST
  task :list do
    invoke "docker:check_running"
  end

  ### UPDATE_HOST_IMAGES
  desc "Update host images from registry"
  task :update_host_images do
    reg = fetch(:registry)
    app_key = fetch(:app_key)
    images = fetch(:images)
    on roles(:host) do
      filtered_image_types.each do |type|
        img_opts = images[type.to_sym]
        execute "sudo docker pull #{reg}/#{img_opts[:name]}:latest"
      end
    end
  end

  ### SSH
  task :ssh do
    name = ENV['name']
    ci = container_with_name(name)
    server = server_running_container(ci)

    on server do |host|
      upload!(File.join(context_path, 'keys', 'container'), "/tmp/container_key")
      #execute "ssh -i /tmp/container_key root@#{ci.ip_address}"
    end
    sh "ssh -t #{server.user}@#{server.hostname} ssh -t -i /tmp/container_key -o \\\"StrictHostKeyChecking no\\\" root@#{ci.ip_address}"
  end


end

before "docker:add", "docker:update_host_images"
before "docker:add", "docker:check_running"

before "docker:remove", "docker:check_running"

before "docker:update", "docker:check_running"
before "docker:update", "docker:update_host_images"

before "docker:ssh", "docker:check_running"
