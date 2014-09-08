# Cloudpad

> Cloudpad is a tool to consolidate commands for the building and deployment of Docker containers.

Cloudpad is designed to be used in a repository strictly responsible for the deployment of code to a cluster of CoreOS or docker-capable machines. It will take you from source-controlled code to running containers across multiple hosts, while abstracting and reducing reduntant tasks.

When deploying containers with Cloudpad, you must complete the following steps:

1. Identify the container types that are going to be deployed
2. Define the configuration for each container type (including it's Dockerfile and context)
3. Locally update source code to the context to be deployed prior to build
4. Build container images in a fashion that best utilizes the cache
5. Push the image to a private docker registry after a successful build
6. Deploy containers to the host using Fleet, SSH, etc.
7. Seamlessly manage and update running containers (i.e. code updates)

Cloudpad provides conventions for building containers with defined roles, and allows for remote execution of certain tasks. This library is also capable of deriving the cluster hosts using a cached manifest or connecting to an API. The principle purpose of using Capistrano is to provide for the remote execution of commands in an easy manner. Many of the guides for CoreOS assume commands are ran from one of the CoreOS hosts, which may not be optimal in all cases. Also, by using Capistrano, we can execute Docker deployment commands on non-CoreOS hosts.

## Installation

Create a directory and add a Gemfile:

    $ mkdir app-deploy
    $ cd app-deploy
    $ touch Gemfile

Add this line to your application's Gemfile:

    gem 'cloudpad', :github => 'agquick/cloudpad'
    gem 'cloudpad-starter', :github => 'agquick/cloudpad-starter' # if you want cloudpad base dockerfiles, etc. This is optional.

And then execute:

    $ bundle install
    $ bundle exec cap install

Update your Capfile:

    # Capfile

    require 'capistrano/setup'
    # require 'capistrano/deploy' # comment this line out

    require 'cloudpad'
    require 'cloudpad/starter'

Now install the starter files:

    $ bundle exec cap starter:install:all

Create your configuration file for deployment:

    $ mkdir config
    $ touch config/deploy.rb

Define your hosts for your cloud:

    # config/cloud/production.yml

    ---
    hosts:
    - internal_ip: 10.6.3.20
    	name: sfa-host1
    	roles:
    	- host
    	provider: manual
    	user: ubuntu
    	os: ubuntu
    containers: []

Now you're ready to build your configuration file.

## Configuration

Before you can execute any commands, you need to specify your configuration options. Most of your configuration can be specified in *config/deploy.rb*. Any stage-specific configuration should be specified in *config/deploy/[stage].rb*

### Global Options

```ruby
set :application, "CoolTodoList"
set :app_key, 'ctl'
```

| Param				| Expected Value	| Notes					|
| ---					| ---							| ---						|
| application	|	String					|	
| app_key			|	String					|	Short string prepended to docker container names|
| registry		|	String					|	IP of docker registry|
| log_level		| :debug, :info		| :info recommended					
|	images			| Hash						| Image configuration (see section)
| container_types | Hash				| Container type configuration (see section)
| repos				| Hash						| Repository configuration (see section)
| services		|	Hash						| Services configuration (see section)

### Images Options

The `images` hash defines the configuration for all the docker images defined for this application.

```ruby
set :images, {
	api: {
		manifest: 'base-app',
		repos: {api: '/app'},
		available_services: ['unicorn', 'nginx'],
	},
	proxy: {
		manifest: 'base-proxy',
		services: ['haproxy']
	}
}
```

| Param				| Expected Value	| Notes					|
| ---					| ---							| ---						|
| manifest		|	String					|	Name of manifest to use (found in manifests directory)
| repos				| Hash						| Name of repository to use (specified by symbol) with the value pointing to the path the repository should be stored to within the container
| available_services | Array		| Array of services that should be installed to the docker container, but not enabled (will be enabled selectively using the init script and environment variables)
| services		| Array						| Array of services to be installed in the container and enabled

### Container Type Options

The `container_types` option defines the configuration for all the docker container types for this application.

```ruby
set :container_types, {
  api: {
    groups: [:api],
    image: :api,
    services: ['unicorn', 'nginx', 'heartbeat', 'app_reporter'],
    ports: { :app => {cport: 8080, hport: 8080} } # range implied
  },
  job: {
    groups: [:api],
    image: :api,
    services: ['job_processor', 'heartbeat', 'app_reporter']
  },
	proxy: {
		groups: [:proxy],
		ports: {proxy: {cport: 80, no_range: true} },
		hosts: ["sfa-host1"]
	}
}
```

| Param				| Expected Value	| Notes					|
| ---					| ---							| ---						|
| group				|	Array						|	Array of symbols (useful for deployment)
| image				|	Symbol					|	Name of image to build container on top of
| services		|	Array						|	Array of service names to enable during container init
| ports				|	Hash						|	cport: container port (symbol)<br>hport: host port<br>no_range: if true, don't increment host port number by container instance number
| volumes			|	Hash						| cpath: container path to mount port

### Repository Options

The `repos` option defines the configuration for all app repositories included in the docker images.

```ruby
set :repos, {
	api: {
		url: 'git@github.com:jsmith/todolist_api.git',
		branch: 'master',
		scripts: [
			"bundle install --frozen --without development test",
			"bundle exec rake assets:precompile"
		]
	}
}
```

| Param				| Expected Value	| Notes					|
| ---					| ---							| ---						|
| url					|	String					|	Path to clone git repository
| branch			|	String					|	Branch to deploy to image
| scripts			|	Array						|	Array of commands to execute on repository after an update is performed

### Services

The `services` option defines services that can be added to docker images.

```ruby
set :services, {
	app_cron: "cd /app && bundle exec script/cron -D -e $RACK_ENV start",
	job_reporter: "cd /app && bundle exec script/job_processor -D -e $RACK_ENV start"
}
```

## Usage

Running a command in cloudpad will generally take the following form:

    $ bundle exec cap <stage> <command> <option flags>
    $ bundle exec cap production docker:add type=job

### Building Images

#### docker:build

Builds the docker images specified by your configuration, tags them as `latest`, and pushes them to the private registry. If a type or group is specified, only images belonging to that type/group will be built and pushed. If no type or group is specified, all images are built and pushed.

    $ bundle exec cap production docker:build [type=<type>] [group=<group>]


### Deploying Images

#### docker:add

Adds a new running container with the container type specified to an eligible host.

    $ bundle exec cap production docker:add type=<type> [count=<count>]

#### docker:remove

Removes a running container with the specified name or type.

    $ bundle exec cap production docker:remove type=<type>
    $ bundle exec cap production docker:remove name=<name>

#### docker:update

Stop all running containers and start again with latest image (on same hosts). Useful for code updates after a build.

    $ bundle exec cap production docker:update [type=<type>] [group=<group>]

#### docker:deploy

Build and update, in a single command.

    $ bundle exec cap production docker:update [type=<type>] [group=<group>]


### Accessing Images

#### docker:list

List all the running containers on all hosts.

    $ bundle exec cap production docker:list

#### docker:ssh

SSH into a container with the specified name.

    $ bundle exec cap production docker:ssh name=<name>

## Tips

* It might be helpful to ignore .git subdirectories in your context. To do so, add a .dockerignore file:

		# context/.dockerignore

		src/api/.git

## Contributing

1. Fork it ( http://github.com/<my-github-username>/cloudpad/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
