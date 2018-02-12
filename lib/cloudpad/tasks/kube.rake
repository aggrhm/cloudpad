namespace :kube do

  desc "Build with docker"
  task :build do
    invoke "docker:build"
  end

  desc "Prepare config resources"
  task :prepare_config do
    puts "Building kubernetes configuration files..."
    imgs = fetch(:images)
    basedir = Pathname.new(kube_path)
    FileUtils.mkdir_p(build_kube_path)
    filtered_components.each do |cmp|
      # check if tag is known for images
      cmp[:images].collect{|id| imgs[id]}.each do |img|
        if img[:tag].blank?
          raise "Image #{img[:id]} does not have a known tag set."
        end
      end
      out = build_template_file(cmp[:file])
      puts "Building file #{cmp[:build_file]}"
      File.write(cmp[:build_file], out)
    end
  end

  desc "Apply configuration"
  task :apply do
    app_key = fetch(:app_key)
    comps = filtered_components
    comp_files = comps.collect{|opts| opts[:build_file] }
    args = comp_files.collect{|f| "-f #{f}"}.join(" ")
    sh "kubectl -n #{app_key} apply #{args}"
  end

  task :deploy do
    if ENV['build'] != 'false'
      invoke "kube:build"
    end
    invoke "kube:deploy:init"
    invoke "kube:apply"
  end

  task :pods do
    sh "kubectl -n #{fetch(:app_key)} get pods"
  end

  task :shell do
    name = ENV['name']
    comp = ENV['comp']
    if name.blank? && comp.blank?
      puts "Please give pod or component name.".red
      next
    elsif comp.present?
      json = JSON.parse(`kubectl -n #{app_key} get pods -o json`)
      ci = json['items'].select{|itm| itm['metadata']['labels']['component'] == comp}.first
      if ci.nil?
        puts "No pod running with that component name".red
        next
      end
      name = ci['metadata']['name']
    end
    sh "kubectl -n #{fetch(:app_key)} exec -i -t #{name} bash"
  end

  task :logs do
    name = ENV['name']
    if name.blank?
      puts "Please give pod name.".red
      next
    end
    sh "kubectl -n #{fetch(:app_key)} logs #{name}"
  end

  namespace :deploy do

    task :init do
      # run jobs for relevant components
      cmps = filtered_components
      jfs = cmps.collect{|cmp| cmp[:init_jobs] || []}.flatten.uniq
      # run each job
      jfs.each do |jf|
        jfn = "#{jf}.yml"
        cf = File.join(kube_path, jfn)
        of = File.join(build_kube_path, jfn)
        write_template_file(cf, of)
        jd = YAML.load_file(of).with_indifferent_access
        jname = jd[:metadata][:name]

        puts "Running job #{jname}..."
        # delete job first
        sh "kubectl -n #{app_key} delete job #{jname} --ignore-not-found=true"
        sh "kubectl -n #{app_key} apply -f #{of}"
        puts "Waiting for job".yellow
        loop do
          js = JSON.parse(`kubectl -n #{app_key} get job/#{jname} -o json`)
          if js['status']['failed'].to_i > 0
            raise "Job did not successfully finish.".red
          end
          if js['status']['succeeded'].to_i >= js['spec']['completions'].to_i
            puts "Job completed successfully.".green
            break
          end
          sleep 1
        end
      end
    end

  end

end

before "kube:apply", "kube:prepare_config"
