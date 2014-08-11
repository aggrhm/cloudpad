namespace :docker do

  task :load do
    app_key = fetch(:app_key) || "app"
    fetch(:images).each do |type, opts|
      opts[:name] ||= "#{app_key}-#{type}"
    end
    set :running_containers, []
  end

  ### BUILD
  desc "Rebuild docker images for all defined container types"
  task :build do
    tf = ENV['type'].split(',') if ENV['type']
    images = fetch(:images)
    images.each do |type, opts|
      next if tf && !tf.include?(type.to_s)
      puts "Building #{type} container...".yellow
      set :building_image, type

      # write dockerfile to context
      mt = opts[:manifest] || type
      df_path = File.join(manifests_path, "Dockerfile.#{mt.to_s}")
      df_str = build_template_file(df_path)
      cdf_path = File.join(context_path, "Dockerfile")
      File.open(cdf_path, "w") {|fp| fp.write(df_str)}

      sh "sudo docker build -t #{opts[:name]} #{context_path}"

    end
    set :building_image, nil
  end


  ### ADD
  desc "Add docker containers on most available host"
  task :add do
    type = ENV['type'].to_sym
    count = ENV['count'] ? ENV['count'].to_i : 1
    img_opts = fetch(:images)[type]
    app_key = fetch(:app_key)
    (1..count).each do
      on next_available_server do |server|
        host = server.properties.source
        inst = next_available_container_instance(type)
        ct = Cloudpad::Container.prepare({type: type, instance: inst, app_key: app_key}, img_opts, host)
        execute "sudo docker run -d --env APP_KEY=#{app_key} #{ct.run_args({registry: fetch(:registry)})}"
        fetch(:running_containers) << ct
      end
    end
  end


  ### REMOVE
  desc "Stop and remove all containers running on hosts for this application"
  task :remove do
    name = ENV['name']
    # find host running this container
    server = server_running_container(name)
    if server.nil?
      puts "Could not find a host running that instance.".red
      next
    end

    on server do
      execute "sudo docker stop #{name}"
      execute "sudo docker rm #{name}"
    end
  end


  desc "Check running containers"
  task :check_running do
    containers = []
    on roles(:host) do |server|
      host = server.properties.source
      hd = capture("sudo docker inspect $(sudo docker ps -q)")
      # parse container info
      JSON.parse(hd).each do |cs|
        cn = cs["Name"].gsub("/", "")
        ip = cs["NetworkSettings"]["IPAddress"]
        ak, type, inst = cn.split(".")
        if ak == fetch(:app_key)
          ci = Cloudpad::Container.new
          # this is a container we manage, add it to list
          ci.host = host
          ci.name = cn
          ci.type = type
          ci.instance = inst.to_i
          ci.ip_address = ip
          containers << ci
        end
      end
    end
    puts "#{containers.length} containers running in #{fetch(:stage)} for this application.".green
    puts containers.collect{|c| "- #{c.name} (on #{c.host.name} at #{c.ip_address}) : #{c.type}"}.join("\n").green
    set :running_containers, containers
  end


  ### ASSIGN CONTAINERS
  desc "Assign containers to hosts"
  task :assign_containers do
    images = fetch(:images)
    cloud = fetch(:cloud)
    img_types = images.keys

    # prepare host memo
    hca = {}
    cloud.hosts.each {|h| hca[h.name] = {host: h, containers: []}}
    next_available_host = lambda {|hosts|
      ret = nil
      cn = nil
      hosts.each do |host|
        if ret.nil? || hca[host.name][:containers].length < cn
          ret = host.name
          cn = hca[ret][:containers].length
        end
      end
      hca[ret][:host]
    }

    # sort images by strict assignments
    img_types.sort! { |t1, t2| b1 = images[t1].key?(:host) ? 1 : 0; b2 = images[t2].key?(:host) ? 1 : 0; b2 <=> b1 }

    # process images
    img_types.each do |type|
      puts "Assigning containers for #{type}...".yellow
      opts = images[type]
      count = opts[:count] || 1
      hf = opts[:hosts] || []
      eligible_hosts = !hf.empty? ? cloud.hosts.select{|h| h.has_id?(hf)} : cloud.hosts
      if count == :per_host
        # handle per host images
        eligible_hosts.each_with_index do |h, idx|
          cr = Cloudpad::Docker.container_record(env, type, opts, (idx+1), h)
          hca[h.name][:containers] << cr
        end

      else
        # normally assign to hosts
        (1..count).each do |idx|
          host = next_available_host.call(eligible_hosts)
          cr = Cloudpad::Docker.container_record(env, type, opts, idx, host)
          hca[host.name][:containers] << cr
        end
      end
    end

    crs = hca.values.collect{|ao| ao[:containers]}.flatten
    set :containers, crs
    puts "===== Containers ====="
    puts crs.join("\n")
    puts "======================"
  end


  ### PUSH_IMAGES
  desc "Push images to registry"
  task :push_images do
    reg = fetch(:registry)
    next if reg.nil?
    tf = ENV['type'].split(',') if ENV['type']

    images = fetch(:images)
    images.each do |type, opts|
      next if tf && !tf.include?(type.to_s)
      sh "sudo docker tag #{opts[:name]}:latest #{reg}/#{opts[:name]}:latest"
      sh "sudo docker push #{reg}/#{opts[:name]}:latest"
    end
  end


  ### UPDATE_REPOS
  desc "Update code for docker containers"
  task :update_repos do
    next if ENV['skip_update_repos'].to_i == 1
    FileUtils.mkdir_p(repos_path)
    repos = fetch(:repos)
    repos.each do |name, opts|
      ru = opts[:url]
      rb = opts[:branch] || "master"
      rp = File.join(repos_path, name.to_s)
      if !File.directory?(rp)
        # dir doesn't exist, clone it
        puts "Cloning #{name} repository...".yellow
        sh "git clone #{ru} #{rp}"
        sh "cd #{rp} && git checkout #{rb}"
      else
        puts "Updating #{name} repository...".yellow
        # dir already exists, do a checkout and pull
        sh "cd #{rp} && git checkout #{rb} && git pull"
      end
    end
  end


  ### UPDATE_HOST_IMAGES
  desc "Update host images from registry"
  task :update_host_images do
    reg = fetch(:registry)
    app_key = fetch(:app_key)
    tf = ENV['type'].split(',') if ENV['type']
    on roles(:host) do
      tf.each do |type|
        img_opts = fetch(:images)[type.to_sym]
        execute "sudo docker pull #{reg}/#{img_opts[:name]}:latest"
      end
    end
  end

  task :ssh do
    name = ENV['name']
    ci = container_with_name(name)
    server = server_running_container(ci)

    on server do |host|
      upload!(File.join(context_path, 'keys', 'container'), "/tmp/container_key")
      #execute "ssh -i /tmp/container_key root@#{ci.ip_address}"
    end
    sh "ssh -t #{server.user}@#{server.hostname} ssh -t -i /tmp/container_key root@#{ci.ip_address}"
  end


  ### CLEAN_LOCAL
  desc "Cleanup images and containers"
  task :clean_local do
    sh "sudo docker stop $(sudo docker ps -a -q)"
    sh "sudo docker rm $(sudo docker ps -a -q)"
    sh "sudo docker rmi $(sudo docker images -a -q)"
  end

end

Capistrano::DSL.stages.each do |stage|
  after stage, 'docker:load'
end

before "docker:build", "docker:update_repos"
before "docker:add", "docker:update_host_images"
before "docker:add", "docker:check_running"
before "docker:remove", "docker:check_running"
before "docker:ssh", "docker:check_running"
after "docker:build", "docker:push_images"
