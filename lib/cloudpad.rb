require 'colored'
require "cloudpad/version"
require "cloudpad/task_utils"
require "cloudpad/cloud"
require "cloudpad/docker"
require "active_support/core_ext"

module Cloudpad

  module Context

    # install puppet
    def self.ensure_puppet_installed(c)
      # create config directory
      if !File.directory?(puppet_path)
        c.execute "mkdir -p #{puppet_path}"
      end
      # check if puppet already installed
      if !c.is_package_installed?("puppet")
        c.info "Puppet not installed, installing..."
        c.execute "wget -O /tmp/puppetlabs.deb http://apt.puppetlabs.com/puppetlabs-release-`lsb_release -cs`.deb"
        c.execute "sudo dpkg -i /tmp/puppetlabs.deb"
        c.execute "sudo apt-get update"
        c.execute "sudo apt-get -y install puppet"
        c.info "Puppet installation complete."
      else
        c.info "Puppet installed."
      end
    end

    def self.prompt_add_node(c, opts={})
      cloud = c.fetch(:cloud)
      node = Cloudpad::Node.new
      node.name = c.prompt("Enter node name")
      node.external_ip = c.prompt("Enter external ip")
      node.internal_ip = c.prompt("Enter internal ip")
      node.roles = opts[:roles] || c.prompt("Enter roles (comma-separated)", "host").split(",").collect{|r| r.downcase.to_sym}
      node.user = c.prompt("Enter login user", "ubuntu")
      node.os = c.prompt("Enter node OS", "ubuntu")
      cloud.nodes << node
      cloud.update_cache
      puts "Node #{node.name} added."
    end

    def self.gem_context_path
      File.expand_path("../../context", __FILE__)
    end

  end

end

include Cloudpad::TaskUtils

load File.expand_path("../cloudpad/tasks/app.rake", __FILE__)
load File.expand_path("../cloudpad/tasks/launcher.rake", __FILE__)
load File.expand_path("../cloudpad/tasks/nodes.rake", __FILE__)
load File.expand_path("../cloudpad/tasks/hosts.rake", __FILE__)
load File.expand_path("../cloudpad/tasks/docker.rake", __FILE__)
