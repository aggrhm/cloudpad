# Kubernetes Setup

## New Cluster/Node

Create new node with name scheme [ns]-kube-master or [ns]-kube-nodeX

Add the node's name and its openstack internal IP address to its /etc/hosts file
so it won't complain about not knowing its own name.


```bash
# switch to root
sudo su -

# install the kubernetes repo
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -

cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF

apt-get update && apt-get dist-upgrade -qy

# this is a good place to reboot to avoid complaining

apt-get install -y docker.io apt-transport-https kubelet kubeadm kubectl nfs-client

# make sure docker uses the right cgroup driver
cat << EOF > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=cgroupfs"]
}
EOF

# Drop in the cloud config

cat << EOF > /etc/kubernetes/cloud.conf
[Global] 
auth-url=https://osapi.cirrusseven.com:5000/v3
username=[username]
password=[password]
tenant-id=[tenant-id]
tenant-name=[tenant-name]
domain-name=Default
region=VA1

[BlockStorage]
bs-version=v3
EOF

# === FOR MASTER ===

# init cluster
kubeadm init

# choose weave networking

# update config for openstack (see https://stackoverflow.com/questions/46067591/how-to-use-openstack-cinder-to-create-storage-class-and-dynamically-provision-pe)

# === FOR NODE ===

# create a join token on master
kubeadm token create --print-join-command

# join this node to the cluster (output of join command modified to drop the ca-cert)
kubeadm join --token <token> 10.250.10.14:6443 --discovery-token-unsafe-skip-ca-verification

# =================

# add openstack support to kubelet

vim /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Add --cloud-provider=openstack --cloud-config=/etc/kubernetes/cloud.conf to the
# KUBELET_KUBECONFIG_ARGS environment variable

# then restart kubelet
systemctl daemon-reload
systemctl restart kubelet
```

## Additional Master Configuration

```bash
# install git
apt-get install git-core

# install ruby with rvm.io

# install cloudpad, following README
```
