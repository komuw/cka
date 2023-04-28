#!/usr/bin/env bash

set -euo pipefail


## chapter 1. Intro & Getting Started.

# In this course we will cover:
# 1. Cluster architecture, installation & configuration.
# 2. Workloads and scheduling.
# 3. Services & networking.
# 4. Storage.
# 5. Troubleshooting.

# For the CKA exam, the ubuntu version and k8s version in use is changed periodically.
# At time of writing(23/march/2022), they use: ubuntu20.04 & k8s v1.23


## chapter 2.
# k8s features:
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



# Building a cluster.
# You need 3 servers(1 control-plane, 2-worker nodes.)

insert_if_not_exists() {
  # This will write something to a text file if it doesnt already exist.
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

1_install_pre_requistes(){
  set -ex
  # install some pre-requiste software
  sudo apt -y update
  sudo apt -y install \
                    apt-transport-https \
                    curl

  # curl & apt-transport-https are required, the others are just here for debugging purposes.
  sudo apt -y install \
                    procps \
                    psmisc \
                    telnet \
                    iputils-ping \
                    nano \
                    wget \
                    grep
}

2_etc_hosts_networking(){
  set -ex
  # setup some network stufff in all the nodes.
  CONTROL_PLANE_PRIVATE_IP="10.0.1.101" # TODO: replace this IPs with your actual ones.
  WORKER_ONE_PRIVATE_IP="10.0.1.102"
  WORKER_TWO_PRIVATE_IP="10.0.1.103"
  etc_host_contents="
${CONTROL_PLANE_PRIVATE_IP} k8s-control-plane
${WORKER_ONE_PRIVATE_IP} k8s-worker-1
${WORKER_TWO_PRIVATE_IP} k8s-worker-2
"
  insert_if_not_exists "${CONTROL_PLANE_PRIVATE_IP}" "${etc_host_contents}" /etc/hosts
}


3_kernel_modules(){
  set -ex
  # enable some kernel modules.
  kernel_module_contents="
overlay
br_netfilter
"
  insert_if_not_exists "br_netfilter" "${kernel_module_contents}" /etc/modules-load.d/containerd.conf
  sudo modprobe overlay
  sudo modprobe br_netfilter
  }

4_kubernetes_networking_settings(){
  set -ex
  # enable some k8s networking settings modules.
  kubernetes_cri_contents="
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
"
  insert_if_not_exists "bridge-nf-call-ip6tables" "${kubernetes_cri_contents}" /etc/sysctl.d/99-kubernetes-cri.conf
  sudo sysctl --system
}

5_install_containerd(){
  set -ex
  # install containerd
  sudo apt -y update && \
  sudo apt -y install containerd
}

6_setup_containerd_config(){
  set -ex
  #  containerd config file.
  mkdir -p /etc/containerd
  sudo containerd config default | sudo tee /etc/containerd/config.toml
  sudo systemctl restart containerd
}

7_disable_swap(){
  set -ex
  # disable swap(needed so that k8s can work)
  sudo swapoff -a 
  cat /etc/fstab # need to check there's nothing in there that can enale swap.
}


8_install_k8s_packages(){
  set -ex
  # install k8s packages.
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
  kubernetes_sources_contents="
deb https://apt.kubernetes.io/ kubernetes-xenial main
"
  insert_if_not_exists "kubernetes-xenial" "${kubernetes_sources_contents}" /etc/apt/sources.list.d/kubernetes.list
  sudo apt -y update && \
  sudo apt -y install kubeadm=1.23.0-00 \
                      kubelet=1.23.0-00 \
                      kubectl=1.23.0-00
  sudo apt-mark hold kubelet kubeadm kubectl # prevent automatic upgrades.
}

9_intialize_cluster(){
  set -ex
  # intialize cluster(This only needs to be done in the control-plane node/s)
  # pod-network-cidr is the IP prefix for all pods in the Kubernetes cluster.
  # The newtork range chosen must not clash with other networks in your VPC
  # `192.168.0.0/16` was taken from the calico docs:
  # https://projectcalico.docs.tigera.io/getting-started/kubernetes/hardway/standing-up-kubernetes
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
}

10_setup_calico(){
  set -ex
  # setup k8s networking(on control-plane nodes). We will use calico, but there are a bunch of other that you can use.
  kubectl apply -f https://docs.projectcalico.org/v3.24.5manifests/calico.yaml

  # Seems like the calico link does not work. This is coz they appear to have move to using operator as shown below:
  # kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/tigera-operator.yaml
}

11_fetch_join_token(){
  set -ex
  # fetch token to use to join workers to the cluster.
  kubeadm token create --print-join-command # it will emit to stdout, a command that you need to run in worker nodes.
  comd=$(kubeadm token create --print-join-command)
  printf "\n run the following command in the worker nodes:\n\t sudo ${comd}\n\n"
}

12_join_workers_to_cluster(){
  set -ex
  # join workers to cluster(should be done in worker nodes.)
  sudo kubeadm join <ip>:<port> --token <some-token> --discovery-token-ca-cer-hash <some-hash> # command emitted by `kubeadm token create`
}

13_verify(){
  set -ex
  # verify(on the control-plane node/s)
  kubectl get nodes
  kubectl get pods --all-namespaces
}

14_one_node_cluster(){
  set -ex
  # allow all nodes(including control-plane) to be used as a worker node.
  kubectl taint nodes --all node-role.kubernetes.io/master-

  # allow node named `node-one` to be used as a worker node.
  # kubectl taint nodes node-one node-role.kubernetes.io/master-
}


control_plane_nodes(){
  1_install_pre_requistes
  2_etc_hosts_networking
  3_kernel_modules
  4_kubernetes_networking_settings
  5_install_containerd
  6_setup_containerd_config
  7_disable_swap
  8_install_k8s_packages
  9_intialize_cluster
  10_setup_calico
  11_fetch_join_token
  13_verify
}

worker_nodes(){
  1_install_pre_requistes
  2_etc_hosts_networking
  3_kernel_modules
  4_kubernetes_networking_settings
  5_install_containerd
  6_setup_containerd_config
  7_disable_swap
  8_install_k8s_packages
  12_join_workers_to_cluster
}

# Namespaces:
# They are virtual clusters backed by the same physical cluster. k8s objects(pods/containers etc) live in namespaces.
kubectl get namespaces; # to list namespaces
kubectl create namespace my-namespace; # to create namespace.
kubectl get pods --namespace=kube-system; # specify a namespace
kubectl get pods --all-namespaces; # from all namespaces.
