namespace :launcher do

  task :ensure_docker do
    run_locally do
      Cloudpad::Docker::Context.install_docker(self)
    end
  end

  task :remove_docker do
    run_locally do
      Cloudpad::Docker::Context.remove_docker(self)
    end
  end

  task :cache_repo_gemfiles do
    repo_name = ENV['repo']
    repos = fetch(:repos)
    if repo_name.nil? || (repo = repos[repo_name.to_sym]).nil?
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
