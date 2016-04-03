namespace :nodes do

  task :load do
    set :cloud, Cloudpad::Cloud.new(env)
    cloud = fetch(:cloud)
    cloud.update
    nodes = cloud.nodes
    host_key = File.join(context_path, "keys", "node.key")
    has_host_key = File.exists?(host_key)
    puts "#{nodes.length} nodes found.".green
    role_filter = ENV['ROLES'] || ENV['NODE_ROLES']
    if role_filter
      role_filter = role_filter.split(",").collect{|r| r.downcase.to_sym}
    end

    nodes.each do |s|
      next if role_filter && (s.roles & role_filter).length == 0
      puts "- Registering #{s.internal_ip}(#{s.name}) as #{s.roles.join(",")}".green
      sopts = {}
      sopts[:roles] = s.roles
      sopts[:user] = s.user
      sopts[:source] = s
      sopts[:ssh_options] = {keys: [host_key]} if has_host_key
      server s.internal_ip, sopts
    end
  end


  task :provision do

    # update checksum for puppet dir
    update_directory_checksum(puppet_path)
    on roles(:all) do |host|
      Cloudpad::Context.ensure_puppet_installed(self)
      # check if puppet config out of date
      if !directory_checksums_match?(puppet_path, "/etc/puppet")
        # backup current puppet
        if test("[ -d /tmp/puppet-bkp ]")
          execute "sudo rm -rf /tmp/puppet-bkp"
        end
        if test("[ -d /etc/puppet ]")
          execute "sudo mv /etc/puppet /tmp/puppet-bkp"
        end
        # upload puppet files
        if test("[ -d /tmp/puppet_config ]")
          execute "rm -rf /tmp/puppet_config"
        end
        copy_directory puppet_path, "/tmp/puppet_config"
        execute "sudo mv /tmp/puppet_config /etc/puppet"
        execute "sudo puppet apply --logdest syslog --verbose /etc/puppet/manifests/site.pp"
      else
        info "Puppet configuration up-to-date."
      end
    end

  end

  task :add do
    Cloudpad::Context.prompt_add_node(self)
  end

end

Capistrano::DSL.stages.each do |stage|
  after stage, 'nodes:load'
end
