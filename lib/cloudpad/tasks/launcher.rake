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

  task :ensure_registry do
    run_locally do
      if !container_running?("registry")
        execute "sudo docker run -d -p 5000:5000 --restart=always --name=registry registry:2"
      else
        execute "sudo docker start registry"
      end
    end
  end

  task :ensure_etcd do
    run_locally do
      if !container_running?("etcd")
        execute "sudo docker start etcd"
      else
        host_ip = fetch(:launcher_ip)
        app_key = fetch(:app_key)
        cmd = "sudo docker run -d -p 2379:2379 -p 2380:2380 --restart=always --name=etcd quay.io/coreos/etcd:v2.2.2"
        cmd << " -name etcd0"
        cmd << " -advertise-client-urls http://#{host_ip}:2379"
        cmd << " -listen-client-urls http://0.0.0.0:2379"
        cmd << " -initial-advertise-peer-urls http://#{host_ip}:2380"
        cmd << " -listen-peer-urls http://0.0.0.0:2380"
        cmd << " -initial-cluster-token #{app_key}"
        cmd << " -initial-cluster etcd0=http://#{host_ip}:2380"
        cmd << " -initial-cluster-state new"
        execute cmd
      end
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
