namespace :docker do

  task :load do
    app_key = fetch(:app_key) || set(:app_key, "app")
    set(:images, {}) if fetch(:images).nil?
    set(:container_types, {}) if fetch(:container_types).nil?
    set(:repos, {}) if fetch(:repos).nil?
    set(:services, {}) if fetch(:services).nil?
    set(:docker_version, "1.2.0") if fetch(:docker_version).nil?
    set(:insecure_registry, false) if fetch(:insecure_registry).nil?
    set(:nfs_shared_path, "/shared") if fetch(:nfs_shared_path).nil?
    set(:host_subnet, "0.0.0.0/0") if fetch(:host_subnet).nil?
    local_ip = local_ip_address
    set(:launcher_ip, local_ip) if fetch(:launcher_ip).nil?
    set(:registry, "#{local_ip}:5000") if fetch(:registry).nil?
    set(:etcd_client_url, "http://#{local_ip}:2379") if fetch(:etcd_client_url).nil?
    set(:context_extensions, {}) if fetch(:context_extensions).nil?

    fetch(:images).each do |type, opts|
      opts[:name] ||= "#{app_key}-#{type}"
    end
    fetch(:container_types).each do |type, opts|
      opts[:image] ||= type.to_sym
    end

    set :running_containers, []
    set :dockerfile_helpers, {
      install_gemfile: lambda {|gf|
        if !File.exists?( File.join(context_path, gf) )
          str = ""
        else
          has_lock = File.exists?( File.join(context_path, "#{gf}.lock") )
          str = "ADD #{gf} /tmp/Gemfile\n"
          str << "ADD #{gf}.lock /tmp/Gemfile.lock\n" if has_lock
          str << "RUN bundle install #{has_lock ? "--frozen" : ""} --system --gemfile /tmp/Gemfile\n"
        end
        str
      },
      install_repo: lambda {|repo, dest|
        repo = repo.to_s
        str = ""
        if File.exists?( gf = File.join(context_path, "src", repo, "Gemfile") )
          str << "#{dfi(:install_gemfile, "src/#{repo}/Gemfile")}\n"
        end
        str << "RUN mkdir -p #{dest} #{dest}/tmp/pids #{dest}/tmp/sockets #{dest}/log\n"
        str << "ADD src/#{repo} #{dest}\n"
      },
      install_image_gemfiles: lambda {
        str = ""
        image_opts[:repos].each do |repo, dest|
          str << dfi(:install_gemfile, "conf/#{repo}_gemfile") + "\n"
        end
        str
      },
      install_image_repos: lambda {
        str = ""
        image_opts[:repos].each do |repo, dest|
          str << dfi(:install_repo, repo, dest) + "\n"
        end
        str
      },
      install_image_services: lambda {
        str = ""
        image_opts[:available_services].each do |svc|
          str << "ADD services/#{svc}.sh /root/services/#{svc}.sh\n"
        end unless image_opts[:available_services].nil?
        image_opts[:services].each do |svc|
          str << "ADD services/#{svc}.sh /etc/service/#{svc}/run\n"
        end unless image_opts[:services].nil?
        str
      },
      run: lambda {|script, *args|
        base = File.basename(script)
        str = "ADD #{script} /tmp/#{base}\n"
        str << "RUN /tmp/#{base} #{args.join(" ")}\n"
      },
      install_container_key: lambda {
        str = "RUN echo #{container_public_key} >> /root/.ssh/authorized_keys\n"
      },
      set_timezone_etc: lambda {
        str = ""
        str << "RUN echo \"Etc/UTC\" > /etc/timezone\n"
        str << "RUN dpkg-reconfigure -f noninteractive tzdata\n"
      },
      disable_ssh_host_check: lambda {
        str = "RUN echo \"Host *\\n\\tStrictHostKeyChecking no\\n\" >> /root/.ssh/config\n"
      },
      configure_basic_container: lambda {
        str = dfi(:set_timezone_etc)
        str << dfi(:disable_ssh_host_check)
      }
    }.merge(fetch(:dockerfile_helpers) || {})

    fetch(:context_extensions)[:cloudpad] = {path: Cloudpad.gem_context_path}

    set :services, {
      heartbeat: "/root/bin/heartbeat -a $APP_KEY -e #{fetch(:etcd_client_url)}",
    }.merge(fetch(:services) || {})

    if ENV['group']
      grs = ENV['group'].split(',').collect(&:to_sym)
      types = fetch(:container_types).select{|type, opts|
        opts[:groups] && !(opts[:groups] & grs).empty?
      }.keys

      ENV['type'] = types.collect(&:to_s).join(",")
      puts "Processing types: #{ENV['type']}...".yellow
    end

  end

end

Capistrano::DSL.stages.each do |stage|
  after stage, 'docker:load'
end

