# Managing Containers

Once your images are built, you are ready to start containers on your hosts. This guide will take you through a few common operations; for more details check out [Commands][commands].

## Listing running containers

To know what containers are presently running, run `docker:list`.

```sh
$ bundle exec cap production docker:list

1 hosts found.
- Registering 104.131.116.45(db-host1) as host
3 containers running in production for this application.
- dbp.site.1 (on db-host1 at 172.17.0.8) : site
- dbp.mongo.1 (on db-host1 at 172.17.0.6) : mongo
- dbp.proxy.1 (on db-host1 at 172.17.0.5) : proxy
Host Summary:
- db-host1: 3 containers running | 44 MB RAM free
```

This listing reports the information for the containers and hosts of your application.

## Starting a new container

To start a new container run `docker:add type=[type] count=[num] chost=[host]`. This will first check the containers that are running across all hosts, and subsequently run the container on the host with the most memory (Ubuntu only). For CoreOS, the selection of the host will be delegated to Fleet.

```sh
$ bundle exec cap production docker:add type=mongo

# Reports back that tlp.mongo.1 started on host1

```

Note you **must** pass the type of the container. Other arguments are optional (count defaults to 1). Also note that each container is appended with its numeric instance. Thus `tlp.mongo.1` is how you refer to this container for any further commands.

## Removing a container

To stop a container run `docker:remove name=[container_name]`.

```sh
$ bundle exec cap production docker:remove name=tlp.mongo.1
```

## Accessing a container

Cloudpad provides an easy ability to SSH into a container from the deployment machine. It will automatically determine which host is running a container. To access a container run `docker:ssh name=[container_name]`.

```sh
$ bundle exec cap production docker:ssh name=tlp.mongo.1
```

**NOTE:** The image must be built with the container key found at `context/keys/container` added to its authorized keys.


[commands]: ../api/commands
