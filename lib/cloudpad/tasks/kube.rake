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
    invoke "kube:build"
    invoke "kube:apply"
  end

  task :pods do
    sh "kubectl -n #{fetch(:app_key)} get pods"
  end

  task :shell do
    name = ENV['name']
    if name.blank?
      puts "Please give pod name.".red
      next
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
end

before "kube:apply", "kube:prepare_config"
