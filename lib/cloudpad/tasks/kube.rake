namespace :kube do

  desc "Prepare config resources"
  task :prepare_config do
    FileUtils.mkdir_p(build_kube_path)
    Dir.glob(File.join(kube_path, "*.*")) do |file|
      out = build_template_file(File.join(kube_path, file))
      of = File.join(build_kube_path, file)
      File.write(of, out)
    end
  end

  desc "Apply configuration"
  task :apply do
    app_key = fetch(:app_key)
    comps = filtered_components
    comp_files = comps.collect{|opts| opts[:file] }
    args = comp_files.collect{|f| "-f #{f}"}.join(" ")
    sh "kubectl -n #{app_key} apply #{args}"
  end

  task :deploy do
    invoke "docker:build"
    invoke "kube:apply"
  end

end

before "kube:apply", "kube:prepare_config"
