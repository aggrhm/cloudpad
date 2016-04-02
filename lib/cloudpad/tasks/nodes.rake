namespace :nodes do

  task :provision do

    on roles(:all) do |host|
      Cloudpad::Context.ensure_puppet_installed(self)
      # backup current puppet
      if test("-d /tmp/puppet-bkp")
        execute "sudo rm /tmp/puppet-bkp"
      end
      execute "sudo mv /etc/puppet /tmp/puppet-bkp"
      # upload puppet files
      upload! puppet_path, "/etc/puppet", recursive: true
      execute "sudo puppet apply /etc/puppet/manifests/site.pp"
    end

  end

  task :add do
    Cloudpad::Context.prompt_add_node(self)
  end

end
