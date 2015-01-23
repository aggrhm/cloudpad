namespace :docker do

  ### UPDATE_REPOS
  desc "Update code for docker containers"
  task :update_repos do
    next if ENV['skip_update_repos'].to_i == 1
    run_scripts = ENV['run_repo_scripts'].to_i == 1
    FileUtils.mkdir_p(repos_path)
    repos = fetch(:repos)
    filtered_repo_names.each do |name|
      opts = repos[name]
      next if opts.nil? # this is not a managed repository
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
        # if commits differ, need to merge and run update commands
        local_rev = `cd #{rp} && git ls-remote --heads . #{rb}`
        remote_rev = `cd #{rp} && git ls-remote --heads origin #{rb}`
        if local_rev != remote_rev
          puts "Code updating...".yellow
          sh "cd #{rp} && git checkout #{rb} && git fetch origin #{rb}:refs/remotes/origin/#{rb}"
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

  ### BUILD
  desc "Rebuild docker images for all defined container types"
  task :build do
    images = fetch(:images)
    services = fetch(:services)
    puts "No images to build".red if images.nil? || images.empty?

    filtered_image_types.each do |type|
      opts = images[type]
      puts "Building #{type} image...".yellow
      set :building_image, type

      # write service files
      FileUtils.mkdir_p( File.join(context_path, 'services') )
      svs = (opts[:services] || []) | (opts[:available_services] || [])
      svs.each do |svc|
        cmd = services[svc.to_sym]
        raise "Service not found!" if cmd.nil?
        ofp = File.join(context_path, 'services', "#{svc}.sh")
        ostr = "#!/bin/bash\n#{cmd}"
        if !File.exists?(ofp) || ostr != File.read(ofp)
          File.write(ofp, ostr)
          File.chmod(0755, ofp)
        end
      end

      # write dockerfile to context
      mt = opts[:manifest] || type
      df_path = File.join(manifests_path, "#{mt.to_s}.dockerfile")
      df_str = build_template_file(df_path)
      cdf_path = File.join(context_path, "Dockerfile")
      File.open(cdf_path, "w") {|fp| fp.write(df_str)}

      sh "sudo docker build -t #{opts[:name]} #{context_path}"

    end
    set :building_image, nil
  end

  ### PUSH_IMAGES
  desc "Push images to registry"
  task :push_images do
    reg = fetch(:registry)
    next if reg.nil?

    images = fetch(:images)
    insecure = fetch(:insecure_registry)
    filtered_image_types.each do |type|
      opts = images[type]
      sh "sudo docker tag -f #{opts[:name]}:latest #{reg}/#{opts[:name]}:latest"
      sh "sudo docker push #{reg}/#{opts[:name]}:latest"
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

before "docker:build", "docker:update_repos"
after "docker:build", "docker:push_images"

