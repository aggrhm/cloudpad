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
      rb = opts[:branch] || opts[:tag] || "master"
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
        `cd #{rp} && git fetch origin`
        local_rev = `cd #{rp} && git rev-parse HEAD`
        remote_rev = rb

        remote_rev_cmd = "cd #{rp} && git rev-parse origin/#{remote_rev}"
        direct_rev_cmd = "cd #{rp} && git rev-parse #{remote_rev}"

        if system(remote_rev_cmd)
          # if the rev is remotely interpretable, use it that way (origin/master)
          remote_rev = `#{remote_rev_cmd}`
        elsif system(direct_rev_cmd)
          # try directly interpreting the rev
          remote_rev = `#{direct_rev_cmd}`
        else
          raise StandardError, "can't resolve #{remote_rev} into a SHA1"
        end

        if local_rev != remote_rev
          puts "Code updating...".yellow
          sh "cd #{rp} && git checkout #{remote_rev}"
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
    # determine image tag
    tag_time = Time.now.strftime("%Y%m%d-%H%M%S")
    tag = "#{app_key}-#{tag_time}"
    no_cache = parse_env('no_cache') || false
    puts "No images to build".red if images.empty?

    if File.directory?(context_path) && !File.exist?(File.join(context_path, ".build-info"))
      raise "Context has been modified manually. Cannot clear.".red
    end

    filtered_images.each do |image|
      image.build!(tag: tag, no_cache: no_cache)
    end
  end

  ### PUSH_IMAGES
  desc "Push images to registry"
  task :push_images do
    reg = fetch(:registry_url)
    next if reg.nil?

    filtered_images.each do |image|
      image.push_to_registry!
    end
  end

  ### REGISTRY LOGIN
  desc "Login to registry"
  task :login_registry do
    scn = fetch(:registry_login_script)
    next if scn.nil?
    sp = File.join(root_path, scn)
    sh "REGISTRY_URL=#{fetch(:registry_url)} #{sp}"
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

#before "docker:build", "docker:update_context_extensions"
#before "docker:build", "docker:update_repos"
before "docker:cache_repo_gemfiles", "docker:update_repos"
before "docker:push_images", "docker:login_registry"
after "docker:build", "docker:push_images"
after "docker:push_images", "launcher:clean_images"
