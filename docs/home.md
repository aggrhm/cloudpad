# Cloudpad

> Cloudpad is a tool to consolidate commands for the building and deployment of Docker containers.

## Concept

Cloudpad is designed to be used in a repository strictly responsible for the deployment of code to a cluster of CoreOS or docker-capable machines. It will take you from source-controlled code to running containers across multiple hosts, while abstracting and reducing reduntant tasks.

## Deployment Strategy

When deploying containers with Cloudpad, you must complete the following steps:

1. Identify the container types that are going to be deployed
2. Define the configuration for each container type (including it's Dockerfile and context)
3. Locally update source code to the context to be deployed prior to build
4. Build container images in a fashion that best utilizes the cache
5. Push the image to a private docker registry after a successful build
6. Deploy containers to the host using Fleet, SSH, etc.
7. Seamlessly manage and update running containers (i.e. code updates)

## Conventions

Cloudpad provides conventions for building containers with defined roles, and allows for remote execution of certain tasks. This library is also capable of deriving the cluster hosts using a cached manifest or connecting to an API.

The principle purpose of using Capistrano is to provide for the remote execution of commands in an easy manner. Many of the guides for CoreOS assume commands are ran from one of the CoreOS hosts, which may not be optimal in all cases. Also, by using Capistrano, we can execute Docker deployment commands on non-CoreOS hosts.

## Dependencies

As of writing this the hosts that are part of Cloudpad must run the following. Everything other than the OS is taken care of by the provisioning process.

* Ubuntu 14.04 LTS
* Docker.io 
* Etcd

It is recommended that the images that you build be built on top of Phusion Base Image for full functionality, although this is not required.

## Upcoming Features

1. CoreOS and Fleet integration
2. Better tagging of built and stored images for rollbacks
3. Public registry support
