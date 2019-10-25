namespace :kube do

  desc "Build with docker"
  task :build do
    invoke "docker:build"
  end

  task :push_images do
    invoke "docker:push_images"
  end

  task :deploy do
    if ENV['build'] != 'false'
      invoke "kube:build"
    end
    invoke "kube:apply"
  end

  task :pods do
    sh "#{kubecmd} get pods"
  end

  task :shell do
    name = ENV['name']
    comp = ENV['comp']
    if name.blank? && comp.blank?
      puts "Please give pod or component name.".red
      next
    elsif comp.present?
      json = JSON.parse(`#{kubecmd} get pods -o json`)
      ci = json['items'].select{|itm| itm['metadata']['labels']['component'] == comp}.first
      if ci.nil?
        puts "No pod running with that component name".red
        next
      end
      name = ci['metadata']['name']
    end
    sh "#{kubecmd} exec -i -t #{name} bash"
  end

  task :logs do
    name = ENV['name']
    if name.blank?
      puts "Please give pod name.".red
      next
    end
    sh "#{kubecmd} logs #{name}"
  end

  desc "Apply configuration"
  task :apply do
    invoke "kube:apply:init_jobs"
    invoke "kube:apply:components"
  end

  namespace :apply do

    task :init_jobs do
      # run jobs for relevant components
      cmps = filtered_components
      jids = cmps.collect{|cmp| cmp[:init_jobs] || []}.flatten.uniq
      jcmps = Cloudpad::Job.with_ids(jids)
      next if jcmps.length == 0

      # write each job
      puts "Building Kubernetes init job configuration files..."
      jcmps.each do |jcmp|
        jcmp.build_spec!
      end

      # run each job
      jcmp.each do |jcmp|
        jcmp.run!
      end
    end
    
    task :components do
      app_key = fetch(:app_key)
      comps = filtered_components

      # build comp files
      puts "Building Kubernetes component configuration files..."
      comps.each do |comp|
        comp.build_spec!
      end

      # apply files
      Cloudpad::KubeSpec.apply_specs!(comps)
    end

  end

end

#before "kube:apply", "kube:prepare_config"
