namespace :docker do

  ### UPDATE_REPOS
  desc "Update code for docker containers"
  task :update_repos do
    next if parse_env('skip_update_repos')
    run_scripts = parse_env('run_repo_scripts')
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
        # dir already exists, do a checkout and pull
        puts "Updating #{name} repository...".yellow
        # if commits differ, need to merge and run update commands
        local_rev = `cd #{rp} && git ls-remote --heads . #{rb}`
        remote_rev = `cd #{rp} && git ls-remote --heads origin #{rb}`
        if local_rev != remote_rev
          puts "Code updating...".yellow
          sh "cd #{rp} && git fetch origin #{rb}:refs/remotes/origin/#{rb}"
          sh "cd #{rp} && git checkout #{rb} && git merge origin/#{rb}"
          is_new = true
        else
          sh "cd #{rp} && git checkout #{rb}"
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

  ### UPDATE_CONTEXT_EXTENSIONS
  desc "Updates context extensions for docker context"
  task :update_context_extensions do
    # make extensions dir
    sh "\\mkdir -p #{context_extensions_path}" if !File.directory?(context_extensions_path)
    ctx_exts = fetch(:context_extensions)
    ctx_exts.each do |name_sym, eopts|
      name = name_sym.to_s
      # create path if doesn't exist
      ep = File.join(context_extensions_path, name)
      gep = eopts[:path]
      sh "\\mkdir -p #{ep}" if !File.directory?(ep)
      # check if paths are the same
      if !system("\\diff -r -q #{gep} #{ep}")
        sh "\\rm -rf #{ep}"
        sh "\\cp -a #{gep} #{ep}"
        puts "Updated context extension '#{name}'.".green
      end
    end
  end

  ### BUILD
  desc "Rebuild docker images for all defined container types"
  task :build do
    no_cache = parse_env('no_cache') || false
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
      cache_opts = no_cache ? "--no-cache " : ""

      sh "sudo docker build -t #{opts[:name]} #{cache_opts}#{context_path}"

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

  ### CACHE_REPO_GEMFILES
  task :cache_repo_gemfiles do
    repos = fetch(:repos)
    filtered_repo_names.each do |rn_sym|
      repo_name = rn_sym.to_s
      if repo_name.nil? || (repo = repos[rn_sym]).nil?
        puts "Repo '#{repo_name}' not found.".red
        next
      end
      # check for Gemfile
      gfp = File.join(context_path, "src", repo_name, "Gemfile")
      glp = File.join(context_path, "src", repo_name, "Gemfile.lock")

      if File.exists?(gfp) && File.exists?(glp)
        ngfp = File.join(context_path, "conf", "#{repo_name}_gemfile")
        nglp = File.join(context_path, "conf", "#{repo_name}_gemfile.lock")
        sh "\\cp #{gfp} #{ngfp}"
        sh "\\cp #{glp} #{nglp}"
        puts "Gemfiles cached in conf directory.".green
      else
        puts "Gemfile for repo not found.".red
      end
    end
  end


end

before "docker:build", "docker:update_context_extensions"
before "docker:build", "docker:update_repos"
before "docker:cache_repo_gemfiles", "docker:update_repos"
after "docker:build", "docker:push_images"

