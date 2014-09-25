# Configuration

Your central place for all configuration is in `config/deploy.rb`. For stage specific configuration, you may override certain params in `config/[stage]/deploy.rb`.

The configuration file is where you define:

1. Images that should be built.
2. Containers that should be ran based on the defined images.
3. Repositories that should be installed on the images.
4. Service scripts that should be ran on the images (requires Phusion Base Image, see below).

Certain features (such as services and init scripts) rely on the [Phusion Base Image](http://phusion.github.io/baseimage-docker/). It is not an explicit requirement that you use this image as the base for your images, but certain features you will then need to support yourself.

This page serves as a guide to getting started with Cloudpad configuration. For more detail about all the params supported, checkout the [Configuration][configuration] page

## Format

Cloudpad is an extension of Capistrano, so the configuration files are simple ruby files with a DSL to provide for the setting of configuration `params`. Most entries will take the form of:

```ruby
set :param_name, 'value'
set :param_hash, {my_hash: 'value'}

# to fetch a previous value
val = fetch(:param_name)
```

Some params are required, but you can (and should) add many of your own params to be used elsewhere in the app, like your Dockerfile manifests which support ERB.

## Application Params

First you'll want to define some basic settings for your Application. See [Configuration][configuration] for all the options here. To get started, set some basics like:

```ruby
set :application, 'todo_list'
set :app_key, 'tlp'							# will be prefixed to image and container names
set :registry, '1.2.3.4:5000'		# the place you will store your docker images
```

## Images

### Design

The first thing you should think about when deploying with Cloudpad is: *What are my images?* Maybe you are running a Wordpress installation. Sounds like you might need a Wordpress app image and a MySQL image. Or perhaps maybe if you're running a Rails app; you might need your Rails app image, a MongoDB image, and a Redis image.

Take the Rails example for instance. Maybe you need to run Unicorn and also a few scripts, all based on the same code. Some might recommend building a separate image for each script that needs to run. However, with Cloudpad you can specify a single image, and define multiple container types based on that single image as we'll see later. Thus, separate containers can be defined against the same image, using initialization scripts to configure exactly what services start at runtime, what ports are exposed, etc. This makes images much easier to maintain and decreases deployment time.

### Example

The definition of an image occurs in the `images` param in the configuration file. The only required param for an `image` definition is the `manifest` param. This specifies which dockerfile to use as the base for building the image. All other params are used within the Dockerfile manifest to control how it's built. Some params are used by Dockerfile Instructions, as we'll see later.

Let's say for example we're deploying a Rails app that is a TodoList application, backed by MongoDB. Maybe the app needs to run unicorn, and a background script.

```ruby
set :images, {
	# our rails app, built into an image
	todo: {

		# We want to use the file manifests/rails-app.dockerfile
		manifest: 'rails-app'

		# We want the :todo_app repo to be installed at /app
		repos: {todo_app: "/app"}		

		# We want to install some service scripts, but not activate them, just make them available for the container. We will see where these are defined later.
		available_services: ['unicorn', 'nginx', 'job_processor']

	}
	mongo: {
		# We want to use the file manifests/mongo.dockerfile
		manifest: 'mongodb'

		# We want to install AND activate services
		services: ['mongodb']
	}
}
```

So you can see from our configuration, A `todo` and `mongo` image will be built. When stored to our registry, they will have the names `tlp-todo` and `tlp-mongo` respectively, prefixed with the `app_key` specified earlier. This allows multiple applications to use the same registry.

Also note the params `repos`, `available_services`, and `available_services`. These are commands used by the [Dockerfile Instructions][dfi].


## Containers

### Design

The container types specify the different types of containers that can be launched on your hosts. Specically, it controls what's passed to the docker command when a container is launched. Here is where you can specify the image, port mappings, volumes, and services appropriate for the container type.

As we mentioned earlier, it is possible for multiple container types to be based on the same image. You can use the `services` param to differentiate what services are ran for each type.

### Example

The definition of a container type occurs in the `container_types` param in the configuration file. The only required param for a `container_type` definition is the `image` param, which defaults to the name of the container type if not explicitly defined. The `image` param specifies what image the container is to be built on. The other params influence parameters sent to the docker command when the container type is to be launched.

Let's continue our TodoList example.

```ruby
set :container_types, {
	# a container for running the todo web front end
	todo_web: {

		# We want to build on the :todo image
		image: :todo,

		# We want to run unicorn and nginx
		services: ['unicorn', 'nginx']

		# We want to map port 3000 of the container to port 80 on the host,
		# and we don't want to incorporate the instance number of the container into
		# the port mapping. Let's call the port mapping :app.
		ports: {:app => {cport: 3000, hport: 80, no_range: true}}
	}
	todo_job: {
		image: :todo,
		services: ['job_processor']

		# make sure this container type is ran on this host only
		hosts: ["host1"]
	}
	mongo: {

		# automatically assumes image is :mongo, so this isn't needed
		image: :mongo,

		# map volume on host at /volumes/mongo_data.[inst_num] to /data/db in container
		volumes: {:mongo_data => {cpath: "/data/db"}}
	}
}
```

As you can see, both the `todo_web` and `todo_job` container types are based on the `todo` image. For more on container type configuration, see the [Configuration API][configuration]. For more on launching and managing containers, see the [Managing Containers Guide][managing_containers].


## Repositories

Cloudpad comes with support for installing version-controlled files to an image. Once added, any `repo` that is referred to by an image is automatically updated before the image is built. Presently, Cloudpad only supports repos that are git-accessible.

```ruby
set :repos, {
	todo_app: {
		url: "git@github.com:johnsmith/todo_app.git",
		branch: "master",
		scripts: [
			"bundle install --frozen --without development test",
			"bundle exec rake assets:precompile"
		]
	}
}
```

Note that the branch and scripts can be specified to further tailor the updating of remote code.


## Container Services

As noted earlier, this applies to images based on the Phusion Base Image. The `services` param defines bash scripts that should be installed to `/etc/service/[service_name]/run`. Defining them here allows you to not have to create your own files, instead they are created and added to your context automatically.

```ruby
set :services, {
	unicorn: "cd /app && bundle exec unicorn -c /root/conf/unicorn.rb",
	nginx: "nginx",
	mongodb: "/usr/bin/mongod --bind_ip 0.0.0.0 --logpath /var/log/mongodb.log"
	job_processor: "cd /app && bundle exec script/job_processor -D -e $RACK_ENV"
}
```

Note the ability to use environment variables, which will be parsed at runtime on the container.

[configuration]: ../api/configuration
[dfi]: ../api/dockerfile_instructions
[managing_containers]: managing_containers
