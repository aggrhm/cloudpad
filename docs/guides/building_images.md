# Building Images

Once your configuration has been defined, you are ready to begin building your images. First you will need to prepare the proper dependencies so that your images can be built.

## Preparation

The two thing that you need to build a Docker image are a Dockerfile and a context. Cloudpad assists in the preparation of both parts.

### Dockerfile Manifest

In the `manifests` folder are your Dockerfiles which can be referred to by images in your configuration. Each Dockerfile stipulates the process for building an image, using files in the `context` folder.

To make the Dockerfile more dynamic in nature, it is processed as an ERB template with the configuration scope accessible to it. This provides the way for `Dockerfile Instructions`, another feature of Cloudpad that allows you to define scripts that can be ran by multiple docker files.

Dockerfile Instructions are very helpful for building your images. To read more about them, see the [API][dfi].

Let's take a look at an example, considering again the TodoList application. Below we will look at the `rails-app.dockerfile`.

```ruby
FROM phusion/baseimage:0.9.12
MAINTAINER Alan G. Graham "alan@productlab.com"

### PRIMARY PACKAGES

RUN apt-get update -q

# let's run a dockerfile instruction to install haproxy
<%= dfi :install_haproxy_153 %>

### ADDITIONAL PACKAGES

RUN apt-get install -qy git-core

# ':run' here is a built in DFI that adds and runs a script in a single line
<%= dfi :run, 'bin/setup_box.py', '--core' %>

### APP STUFF

# note how we can fetch a param from the config using ERB
ENV RACK_ENV <%= fetch(:stage) %>

### SERVICES

ADD conf/haproxy.conf.tmpl /root/conf/haproxy.conf.tmpl

### CONTAINER STUFF

ADD bin /root/bin

# container_public_key is a utility to cat the key located at keys/container
RUN echo "<%= container_public_key %>" >> /root/.ssh/authorized_keys

EXPOSE 80

CMD ["/sbin/my_init"]

<%= dfi :install_image_services %>
```

Note the use of the DFIs to easily reuse certain commands when building an image. This allows your Dockerfile to become much more dynamic, allowing you to keep most of your configuration in `config/deploy.rb`.

### Image Context

Now that you have your Dockerfile defined, it needs a context to pull files from. This is the purpose of the `context` folder. Because Docker.io does not currently support symbolic linking, we must use a common folder for files that should be shared across multiple images.

This context is provided to the image every time it is built. The directory structure you choose to use is up to you. Some built-in utilities may automatically install to certain directories as follows:

* **Repositories** - Any repos you define are installed in `context/src/[repo_name]`
* **Services** - Any services you define are written to `context/services/[service_name].sh`

## Starting a Build

Once your dockerfile and context are defined, you are ready to begin a build. For more information on building images, see [Commands][commands].

### Implementation

To build your images, you will run the `docker:build` command. This command will perform the following:

1. Update any repositories referred to by the image
2. Build any necessary service files
2. Copy the relevant Dockerfile manifest into the context
3. Execute the docker build command
4. Push the images to the docker registry

To choose a subset of images to build, you can pass the `type=[type1],[type2]` or `group=[group]` argument. Note that the type refers to the container type, not the name of the image. The images that need to be rebuilt are discerned from the relevant container types passed in on the command line.

### Storage

Once the images are built, they are pushed to the defined registry and tagged with a unique name that is a combination of the `app_key` and the image name (e.g. `tlp-mongo`). This allows multiple applications to use the same registry.


[dfi]: ../api/dockerfile_instructions
[commands]: ../api/commands
