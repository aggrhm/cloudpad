# Hosts

In Cloudpad, the `Host` is the VM or bare-metal machine that will be running your containers. The host must run either CoreOS or Ubuntu (at least 14.04 LTS).

**NOTE:** Presently, only Ubuntu is supported for container deployment. Deployment commands that work with Fleet on CoreOS are in the development pipeline.

Cloudpad stores a local registry of the hosts that support your application. Once a `Host` is registered with Cloudpad, it can be automatically provisioned from a bare-bones Ubuntu install using the `host:provision` command.

## Adding a new host

After you've setup your deployment directory, you'll want to register all your hosts that support your application's containers. To add a new host, run the following command:

```sh
$ bundle exec cap production hosts:add
# follow the prompts to enter the information for your host.
```

## Provisioning a new host (Ubuntu)

For Ubuntu, Docker and some of it's necessary auxillary services are not automatically installed. Cloudpad will take care of this for you. After registering your hosts, run the following command to provision them:

```sh
$ bundle exec cap production hosts:provision
```

This will perform the following actions:

1. Install docker.io if not installed.
2. Install and run etcd if not installed.

**NOTE:** If a host is ever restarted, you need to ensure that etcd is restarted. Running `hosts:provision` again will resolve this. Automatic restarting of etcd will be added in the future.
