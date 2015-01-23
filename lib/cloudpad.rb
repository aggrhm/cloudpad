require "cloudpad/version"
require "cloudpad/task_utils"
require "cloudpad/cloud"
require "cloudpad/docker"
require "active_support/core_ext"

module Cloudpad
  # Your code goes here...
end

include Cloudpad::TaskUtils

load File.expand_path("../cloudpad/tasks/launcher.rake", __FILE__)
load File.expand_path("../cloudpad/tasks/hosts.rake", __FILE__)
load File.expand_path("../cloudpad/tasks/docker.rake", __FILE__)
