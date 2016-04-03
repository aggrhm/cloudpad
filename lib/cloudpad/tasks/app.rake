namespace :app do

  task :provision do
    invoke "launcher:provision"
    invoke "nodes:provision"
    invoke "hosts:provision"
  end

  task :maintain do
    invoke "docker:maintain"
  end

end

before "app:maintain", "app:provision"
