# Configuration

Before you can execute any commands, you need to specify your configuration options. Most of your configuration can be specified in `config/deploy.rb`. Any stage-specific configuration should be specified in `config/deploy/[stage].rb`


## Global Options

```ruby
set :application, "CoolTodoList"
set :app_key, 'ctl'
```

| Param		| Expected Value| Notes	|
| ---		| ---			| ---		|
| application	| String		|	
| app_key	| String		| Short string prepended to docker container names|
| registry	| String		| IP of docker registry|
| log_level	| :debug, :info		| :info recommended					
| images	| Hash			| Image configuration (see section)
| container_types | Hash		| Container type configuration (see section)
| repos		| Hash			| Repository configuration (see section)
| services	| Hash			| Services configuration (see section)


## Repository Options

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

| Param		| Expected Value	| Notes			|
| ---		| ---			| ---					|
| url		| String		| Path to clone git repository
| branch	| String		| Branch to deploy to image
| scripts	| Array			| Array of commands to execute on repository after an update is performed


## Services Options

The `services` option defines services that can be added to docker images. It should be written as a bash command that does not daemonize.

```ruby
set :services, {
	nginx: "nginx",
	app_cron: "cd /app && bundle exec script/cron -D -e $RACK_ENV start",
	job_reporter: "cd /app && bundle exec script/job_processor -D -e $RACK_ENV start"
}
```


## Images Options

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

| Param		| Expected Value	| Notes			|
| ---		| ---			| ---			|
| manifest	| String		| Name of Dockerfile manifest to use (found in manifests directory). See **Manifests** documentation.
| repos		| Hash			| Name of repository to use (specified by symbol) with the value pointing to the path the repository should be stored to within the container
| available_services | Array		| Array of services that should be installed to the docker container, but not enabled (will be enabled selectively using the init script and environment variables)
| services	| Array			| Array of services to be installed in the container and enabled


## Container Type Options

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

| Param		| Expected Value	| Notes				|
| ---		| ---			| ---				|
| group		| Array			| Array of symbols (useful for deployment)
| image		| Symbol		| Name of image to build container on top of
| services	| Array			| Array of service names to enable during container init
| ports		| Hash			| cport: container port (symbol)<br>hport: host port<br>no_range: if true, don't increment host port number by container instance number
| volumes	| Hash			| cpath: container path to mount port

