namespace :docker do

  task :load do
    app_key = fetch(:app_key) || "new"
    fetch(:images).each do |type, opts|
      opts[:name] ||= "#{app_key}-#{type}"
    end
  end

  ### BUILD
  desc "Rebuild docker images for all defined container types"
  task :build do
    tf = ENV['images'].split(',') if ENV['images']
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


  ### RUN
  desc "Run docker containers on assigned hosts"
  task :run do
    cs = fetch(:containers)
    on roles(:host) do |server|
      host = server.properties.source
      # get containers for host
      cs.select{|c| host.has_id?(c['host']) }
    end
  end


  ### STOP
  desc "Stop and remove all containers running on hosts for this application"
  task :remove do
    # TODO: find all containers with the app key using -q and inspect them to check the image name
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

    images = fetch(:images)
    images.each do |type, opts|
      sh "sudo docker tag #{opts[:name]} #{reg}/#{opts[:name]}"
      sh "sudo docker push #{reg}/#{opts[:name]}"
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
