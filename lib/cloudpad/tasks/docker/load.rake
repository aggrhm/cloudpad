namespace :docker do

  task :load do
    app_key = fetch(:app_key) || set(:app_key, "app")
    set(:images, {}) if fetch(:images).nil?
    set(:repos, {}) if fetch(:repos).nil?

    fetch(:images).each do |type, opts|
      opts[:name] ||= "#{app_key}-#{type}"
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
        image_opts[:services].each do |svc|
          str << "ADD services/#{svc}.sh /etc/service/#{svc}/run\n"
        end
        str
      },
      run: lambda {|script, *args|
        base = File.basename(script)
        str = "ADD #{script} /tmp/#{base}\n"
        str << "RUN /tmp/#{base} #{args.join(" ")}\n"
      }
    }.merge(fetch(:dockerfile_helpers) || {})
  end

end

Capistrano::DSL.stages.each do |stage|
  after stage, 'docker:load'
end

