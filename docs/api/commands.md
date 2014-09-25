# Usage

Running a command in Cloudpad will generally take the following form:

    $ bundle exec cap <stage> <command> <option flags>
    $ bundle exec cap production docker:add type=job

## Building Images

### docker:build

Builds the docker images specified by your configuration, tags them as `latest`, and pushes them to the private registry. If a type or group is specified, only images belonging to that type/group will be built and pushed. If no type or group is specified, all images are built and pushed.

    $ bundle exec cap production docker:build [type=<type>] [group=<group>]


## Deploying Images

### docker:add

Adds a new running container with the container type specified to an eligible host.

    $ bundle exec cap production docker:add type=<type> [count=<count>]

### docker:remove

Removes a running container with the specified name or type.

    $ bundle exec cap production docker:remove type=<type>
    $ bundle exec cap production docker:remove name=<name>

### docker:update

Stop all running containers and start again with latest image (on same hosts). Useful for code updates after a build.

    $ bundle exec cap production docker:update [type=<type>] [group=<group>]

### docker:deploy

Build and update, in a single command.

    $ bundle exec cap production docker:update [type=<type>] [group=<group>]


## Accessing Images

### docker:list

List all the running containers on all hosts.

    $ bundle exec cap production docker:list

### docker:ssh

SSH into a container with the specified name.

    $ bundle exec cap production docker:ssh name=<name>


## Provisioning Hosts

### hosts:provision

Provisions all Ubuntu hosts to ensure docker and etcd are both installed and properly configured and running.

    $ bundle exec cap production hosts:provision

