require 'colored'
require "cloudpad/version"
require "cloudpad/task_utils"
require "cloudpad/cloud"
require "cloudpad/docker"
require "active_support/core_ext"

module Cloudpad

  def self.gem_context_path
    File.expand_path("../../context", __FILE__)
  end

  module Context

    # install puppet
    def self.ensure_puppet_installed(c)
      # check if puppet already installed
      if !c.is_package_installed?("puppet") && !c.is_package_installed?("puppet-agent")
        c.info "Puppet not installed, installing..."
        c.execute "wget -O /tmp/puppetlabs.deb http://apt.puppetlabs.com/puppetlabs-release-pc1-`lsb_release -cs`.deb"
        c.execute "sudo dpkg -i /tmp/puppetlabs.deb"
        c.execute "sudo apt-get update"
        c.execute "sudo apt-get -y install puppet-agent"
        c.info "Puppet installation complete."
      else
        c.info "Puppet installed."
      end
    end

    def self.ensure_puppet_modules_installed(c)
      module_config = c.fetch(:puppet_modules)
      # get currently installed modules
      installed_modules = {}
      Dir.glob(File.join(c.puppet_path, "modules", "*", "metadata.json")).each {|fp|
        data = JSON.parse(File.read(fp))
        installed_modules[data["name"]] = data
      }
      mod_dir = File.join c.puppet_path, "modules"
      module_config.each do |mod_name, ver|
        next if !installed_modules[mod_name].nil?
        cmd = "sudo puppet module install #{mod_name} --modulepath #{mod_dir} --version #{ver}"
        c.execute cmd
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


  end

end

include Cloudpad::TaskUtils

load File.expand_path("../cloudpad/tasks/cloudpad.rake", __FILE__)
load File.expand_path("../cloudpad/tasks/app.rake", __FILE__)
load File.expand_path("../cloudpad/tasks/launcher.rake", __FILE__)
load File.expand_path("../cloudpad/tasks/nodes.rake", __FILE__)
load File.expand_path("../cloudpad/tasks/hosts.rake", __FILE__)
load File.expand_path("../cloudpad/tasks/docker.rake", __FILE__)
