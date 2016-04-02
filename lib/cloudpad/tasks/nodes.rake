namespace :nodes do

  task :load do
    set :cloud, Cloudpad::Cloud.new(env)
    cloud = fetch(:cloud)
    cloud.update
    nodes = cloud.nodes
    host_key = File.join(context_path, "keys", "node.key")
    has_host_key = File.exists?(host_key)
    puts "#{hosts.length} hosts found.".green
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

Capistrano::DSL.stages.each do |stage|
  after stage, 'nodes:load'
end
