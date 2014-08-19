namespace :docker do

  task :load do
    app_key = fetch(:app_key) || "app"
    fetch(:images).each do |type, opts|
      opts[:name] ||= "#{app_key}-#{type}"
    end
    set :running_containers, []
    set :dockerfile_helpers, {
      install_gemfile: lambda {|gf|
        has_lock = File.exists?( File.join(context_path, "#{gf}.lock") )
        str = "ADD #{gf} /tmp/Gemfile\n"
        str << "ADD #{gf}.lock /tmp/Gemfile.lock\n" if has_lock
        str << "RUN bundle install #{has_lock ? "--frozen" : ""} --system --gemfile /tmp/Gemfile\n"
        str
      },
      install_repo: lambda {|repo, dest|
        repo = repo.to_s
        str = ""
        if File.exists?( gf = File.join(context_path, "src", repo, "Gemfile") )
          str << "#{dfi(:install_gemfile, "src/#{repo}/Gemfile")}\n"
        end
        str << "RUN mkdir #{dest} #{dest}/pids #{dest}/sockets #{dest}/log\n"
        str << "ADD src/#{repo} #{dest}\n"
      },
      run: lambda {|script, *args|
        base = File.basename(script)
        str = "ADD #{script} /tmp/#{base}\n"
        str << "RUN /tmp/#{base} #{args.join(" ")}\n"
      }
    }.merge(fetch(:dockerfile_helpers) || {})
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
      server = next_available_server(type)
      if server.nil?
        puts "No server available (check image host parameters)".red
        break
      end
      on server do |server|
        host = server.properties.source
        inst = next_available_container_instance(type)
        ct = Cloudpad::Container.prepare({type: type, instance: inst, app_key: app_key}, img_opts, host)
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
          ci.image_options = fetch(:images)[type.to_sym]
          ci.name = cn
          ci.type = type.to_sym
          ci.instance = inst.to_i
          ci.ip_address = ip
          ci.image = "#{ci.image_options[:name]}:latest"
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
    run_scripts = ENV['run_repo_scripts'].to_i == 1
    FileUtils.mkdir_p(repos_path)
    repos = fetch(:repos)
    repos.each do |name, opts|
      ru = opts[:url]
      rb = opts[:branch] || "master"
      au = opts[:scripts] || []
      rp = File.join(repos_path, name.to_s)
      if !File.directory?(rp)
        # dir doesn't exist, clone it
        puts "Cloning #{name} repository...".yellow
        sh "git clone #{ru} #{rp}"
        sh "cd #{rp} && git checkout #{rb}"
        is_new = true
      else
        puts "Updating #{name} repository...".yellow
        # dir already exists, do a checkout and pull
        sh "cd #{rp} && git checkout #{rb} && git fetch origin #{rb}:refs/remotes/origin/#{rb}"
        # if commits differ, need to merge and run update commands
        local_rev = `cd #{rp} && git rev-parse --verify HEAD`
        remote_rev = `cd #{rp} && git rev-parse --verify origin/#{rb}`
        if local_rev != remote_rev
          puts "Code updating...".yellow
          sh "cd #{rp} && git merge origin/#{rb}"
          is_new = true
        else
          puts "Code is up to date.".green
          is_new = false
        end
      end

      if is_new || run_scripts
        au.each do |cmd|
          clean_shell "cd #{rp} && #{cmd}"
        end
      end


    end
  end


  ### UPDATE_HOST_IMAGES
  desc "Update host images from registry"
  task :update_host_images do
    reg = fetch(:registry)
    app_key = fetch(:app_key)
    images = fetch(:images)
    tf = ENV['type'].split(',') if ENV['type']
    img_types = tf ? tf : images.keys
    on roles(:host) do
      img_types.each do |type|
        img_opts = images[type.to_sym]
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
    sh "ssh -t #{server.user}@#{server.hostname} ssh -t -i /tmp/container_key -o \\\"StrictHostKeyChecking no\\\" root@#{ci.ip_address}"
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
after "docker:build", "docker:push_images"

before "docker:add", "docker:update_host_images"
before "docker:add", "docker:check_running"

before "docker:remove", "docker:check_running"

before "docker:update", "docker:check_running"
before "docker:update", "docker:update_host_images"

before "docker:ssh", "docker:check_running"
