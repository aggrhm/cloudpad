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

See the [Configuration wiki page](https://github.com/agquick/cloudpad/wiki/Configuration)

## Usage

See the [Usage wiki page](https://github.com/agquick/cloudpad/wiki/Usage)

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
