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

  task :provision do
    invoke "launcher:ensure_ntp"
    invoke "launcher:ensure_nfs"
    invoke "launcher:ensure_docker"
    invoke "launcher:ensure_registry"
    invoke "launcher:ensure_etcd"
    invoke "launcher:ensure_puppet"
  end

  task :ensure_ntp do
    on roles(:host) do
      if !is_package_installed?("ntp")
        execute "sudo apt-get install -qy ntp"
      end
    end
  end

  task :ensure_nfs do
    shared_path = fetch(:nfs_shared_path)
    host_subnet = fetch(:host_subnet)
    # install server locally
    run_locally do
      # install package if needed
      if !is_package_installed?("nfs-kernel-server")
        execute "sudo apt-get install -qy nfs-kernel-server"
      end
      # create share path if needed
      if !test("[ -d #{shared_path} ]")
        execute "sudo mkdir #{shared_path}" 
        execute "sudo chmod a+w #{shared_path}"
      end
      # update exports file and restart if needed
      export_str = "#{shared_path} #{host_subnet}(rw,all_squash)"
      act_export_str = local_file_content("/etc/exports")
      if act_export_str.nil? || act_export_str.strip != export_str
        execute "echo \"#{export_str}\" | sudo tee /etc/exports > /dev/null"
        execute "sudo service nfs-kernel-server restart"
      end
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
      if container_running?("etcd")
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

  task :ensure_puppet do
    run_locally do
      Cloudpad::Context.ensure_puppet_installed(self)
    end
  end

  task :install_puppet_module do
    mod_name = ENV['module'] || ENV['name']
    ver = ENV['version']
    mod_dir = File.join puppet_path, "modules"
    run_locally do
      Cloudpad::Context.ensure_puppet_installed(self)
      cmd = "sudo puppet module install #{mod_name} --modulepath #{mod_dir}"
      cmd << " --version #{ver}" if ver
      execute cmd
    end
  end

  task :uninstall_puppet_module do
    mod_name = ENV['module'] || ENV['name']
    ver = ENV['version']
    mod_dir = File.join puppet_path, "modules"
    run_locally do
      Cloudpad::Context.ensure_puppet_installed(self)
      cmd = "sudo puppet module uninstall #{mod_name} --modulepath #{mod_dir}"
      cmd << " --version #{ver}" if ver
      execute cmd
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

  task :clean do
    run_locally do
      execute "sudo docker rmi $(sudo docker images -q --filter \"dangling=true\")"
    end
  end

  task :list_commands do

    commands = [
      # launcher
      {
        name: "launcher:ensure_docker",
        desc: "Ensure docker running on launching host",
        group: "Launcher"
      },
      {
        name: "launcher:ensure_etcd",
        desc: "Ensure etcd running on launching host",
        group: "Launcher"
      },
      {
        name: "launcher:ensure_registry",
        desc: "Ensure registry running on launching host",
        group: "Launcher"
      },
      {
        name: "launcher:cache_repo_gemfiles",
        desc: "Cache gemfiles in context directory for repository",
        group: "Launcher",
        options: [
          {flag: "repo", desc: "The repository to cache"}
        ]
      },
      {
        name: "launcher:clean",
        desc: "Clean up any untagged images",
        group: "Launcher",
        options: []
      },
      # docker
      {
        name: "docker:update_repos",
        desc: "Update code repositories",
        group: "Docker",
        options: [
          {flag: "run_repo_scripts", desc: "Run repository post-update scripts"}
        ]
      },
      {
        name: "docker:build",
        desc: "Build container images",
        group: "Docker",
        options: [
          {flag: "no_cache", desc: "Build image without using cache"},
          {flag: "skip_update_repos", desc: "Skip updating the repositories before building"}
        ]
      },
      {
        name: "docker:add",
        desc: "Start new container from image",
        group: "Docker",
        options: []
      },
      {
        name: "docker:remove",
        desc: "Stop running container",
        group: "Docker",
        options: []
      },
      {
        name: "docker:deploy",
        desc: "Build images, stop containers, and restart with new images",
        group: "Docker",
        options: []
      },
      # hosts
      {
        name: "hosts:add",
        desc: "Build images, stop containers, and restart with new images",
        group: "Hosts",
        options: []
      },
      {
        name: "hosts:provision",
        desc: "Ensure necessary processes running on hosts",
        group: "Hosts",
        options: []
      },
      {
        name: "hosts:clean",
        desc: "Remove untagged images from hosts",
        group: "Hosts",
        options: []
      },
    ]

    groups = ["Launcher", "Docker", "Hosts"]

    groups.each do |group|
      puts "\n#{group.upcase}"
      puts "====================="
      commands.select{|c| c[:group] == group}.each do |cmd|
        puts "\n#{cmd[:name]}"
        puts "\t#{cmd[:desc]}"
        (cmd[:options] || []).each do |opt|
          puts "\t\t- <#{opt[:flag]}> #{opt[:desc]}"
        end
      end
    end

  end

end
