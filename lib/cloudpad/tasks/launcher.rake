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

end
