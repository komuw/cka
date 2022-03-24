#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob globstar


## chapter 1.

# In this course we will cover:
# 1. Cluster architecture, installation & configuration.
# 2. Workloads and scheduling.
# 3. Services & networking.
# 4. Storage.
# 5. Troubleshooting.

# For the CKA exam, the ubuntu version and k8 version in use is changed periodically.
# At time of writing(23/march/2022), they use: ubuntu20.04 & k8s v1.23


## chapter 2.
# k8 features:
# (a) container orchestration: dynamically manage containers across multiple hosts.
# (b) app reliability: make it easier to build self-healing & scalable apps.
# (c) automation: offer utilities to automate mgnt of container apps.

# K8s architecture(see: imgs/k8s-architecture.png):
# 1. Control plane: It is a collection of components responsible for managing the cluster. It controls the cluster.
#                   The components can run on any machine in the cluster, but usually run on dedicated controller machines.
#     (a) kube-api-server: serves the k8s API. It is the primary interface to the control plane & to the cluster itself.
#     (b) etcd:            backend store for data relating to state of the cluster.
#     (c) kube-scheduler:  does scheduling; process of selecting an available node on which to run containers.
#     (d) kube-controller-manager: runs a collection of multiple controller utilities that do various things.
#     (e) cloud-controller-manager: provides and interface btwn k8s and different cloud platforms. Comes inplay when using their(eg AWS) services with k8s.
#
# 2. Nodes(worker nodes): The machines where the containers run.
#                         Various node components manage containers on the machine and communicate with the the control plane.
#     (a) Kubelet: k8s agent on each node. Comms with control-plane & ensures that containers are run as instructed by control-plane.
#                                          It also reports container status and other data.
#     (b) kube-proxy: It's a network proxy. Handles tasks related to providing networking btwn containers & services running in the cluster.
#     (c) container-runtime: It is not built into k8s, instead it is a separate piece of software for actually running containers.
#                            examples are; docker, containerd etc
#     (d) containers: The containers themselves.

# This will write something to a text file if it doesnt already exist.
insert_if_not_exists() {
    # usage:
    #   insert_if_not_exists "k8s-control-plane" "78.3.21 k8s-control-plane" /etc/hosts

    to_check=$1
    to_add=$2
    file=$3

    if grep -q "${to_check}" "${file}"; then
        # already exists
        echo -n ""
    else
        # append
        { # try
          printf "${to_add}" >> "${file}"
        } || { # catch
          printf "${to_add}" | sudo tee -a "${file}"
        }
    fi
}


# Building a cluster.
# You need 3 servers(1 control-plane, 2-worker nodes.)

# 0. install some pre-requiste software
sudo apt -y update && \
sudo apt -y install grep curl wget

# 1. setup some network stufff in all the nodes.
CONTROL_PLANE_PRIVATE_IP="10.0.1.101" # TODO: replace this IPs with your actual ones.
WORKER_ONE_PRIVATE_IP="10.0.1.102"
WORKER_TWO_PRIVATE_IP="10.0.1.103"
etc_host_contents="
${CONTROL_PLANE_PRIVATE_IP} k8s-control-plane
${WORKER_ONE_PRIVATE_IP} k8s-worker-1
${WORKER_TWO_PRIVATE_IP} k8s-worker-2
"
insert_if_not_exists "${CONTROL_PLANE_PRIVATE_IP}" "${etc_host_contents}" /etc/hosts

# 2. enable some kernel modules.
kernel_module_contents="
overlay
br_netfilter
"
insert_if_not_exists "br_netfilter" "${kernel_module_contents}" /etc/modules-load.d/containerd.conf
sudo modprobe overlay
sudo modprobe br_netfilter

# 2. enable some k8s networking settings modules.
kubernetes_cri_contents="
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
"
insert_if_not_exists "bridge-nf-call-ip6tables" "${kubernetes_cri_contents}" /etc/sysctl.d/99-kubernetes-cri.conf
sudo sysctl --system


# 3. install containerd
sudo apt -y update && \
sudo apt -y install containerd


# 4. containerd config file.
mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd

# 5. disable swap(needed so that k8s can work)
sudo swapoff -a 
cat /etc/fstab # need to check there's nothing in there that can enale swap.

# 6. install pre-required packages.
sudo apt -y update && \
sudo apt -y install \
                  apt-transport-https \
                  curl # curl & apt-transport-https are required, the others are just here for debugging purposes.
sudo apt -y install \
                  procps \
                  psmisc \
                  telnet \
                  iputils-ping \
                  nano \
                  wget


# 7. install k8s packages.
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
kubernetes_sources_contents="
deb https://apt.kubernetes.io/ kubernetes-xenial main
"
insert_if_not_exists "kubernetes-xenial" "${kubernetes_sources_contents}" /etc/apt/sources.list.d/kubernetes.list
sudo apt -y update && \
sudo apt -y install kubelet=1.23.0-00 \
                    kubeadm=1.23.0-00 \
                    kubectl=1.23.0-00
sudo apt-mark hold kubelet kubeadm kubectl # prevent automatic upgrades.

# 8. intialize cluster(This only needs to be done in the control-plane node/s)
sudo kubeadm init --pod-network-cidr 192.168.0.0/16 --kubernetes-version 1.23.0 # this command will output some further directions on what to do next.
setup_kube_config(){
    # This is an example of the instructions emitted by the `kubeadm init` command
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
}
setup_kube_config
kubectl get nodes # this should now work.
kubectl get pods --all-namespaces

# 9. setup k8s networking. We will use calico, but there are a bunch of other that you can use.
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# 10. fetch token to use to join workers to the cluster.
kubeadm token create --print-join-command # it will emit to stdout, a command that you need to run in worker nodes.


# 11. join workers to cluster(should be done in worker nodes.)
sudo kubeadm join <ip>:<port> --token <some-token> --discovery-token-ca-cer-hash <some-hash> # command emitted by `kubeadm token create`

# 12. verify(on the control-plane node/s)
kubectl get nodes
kubectl get pods --all-namespaces
