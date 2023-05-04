#!/usr/bin/env bash

set -euo pipefail

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

## chapter 11: Troubleshooting.

# Troubleshooting k8s cluster.
# (a) Kube API server: If it is down, you won't be able to interact with cluster via kubectl.
#                      Possible Fixes; make sure docker & kubelet are running in the CP nodes. 
# (b) Check node status: `kubectl get nodes`; `kubectl describe node <nodeName>`
#                         If node has issues;
#                         - It may be because a service(docker, kubelet, etc) is down in that node.
#                           `systemctl status kubelet; systemctl enable kubelet; systemctl start kubelet`
#                         - It may also be bcoz some k8s component's pods are unhealthy.
#                           `kubectl get pods -n kube-system`; `kubectl describe pod <podName> -n kube-system`
check_cluster(){
    kubectl get nodes
    kubectl describe node <nodeName> # check `Conditions` section
    systemctl status kubelet # Is it active and enabled.
    systemctl enable kubelet
    systemctl start kubelet

    kubectl get pods -n kube-system
}

# Checking Cluster and Node logs
# Use `journalctl`.
# The k8s cluster components have log output redirected to `/var/log` eg `/var/log/kube-scheduler.log`
# Not all clusters may have logs in that location, eg for `kubeadm` components run inside containers and their logs can be accessed using `kubectl logs`
check_node(){
    journalctl -u kubelet
    journalctl -u docker
    ls -lsha /var/log/
}

# Troubleshooting applications.
check_apps(){
    kubectl get pods
    kubectl describe pod <podName>
    kubectl logs -f --tail=1000 --namespace=hey-dev <podName> --all-containers=true --max-log-requests=21

    kubectl exec --namespace=namespace --stdin --tty podName -- /bin/sh                  # 1 container pod
    kubectl exec --namespace=namespace --stdin --tty podName -c my-container -- /bin/sh  # multi-container pod
}

# Troubleshooting networking.
# - check your k8s networking plugin, eg calico
# - check kube-proxy
# - check k8s DNS
# In `kubeadm` clusters, both k8s DNS and kube-proxy both run as pods in the kube-system namespace.
# You can run a container in the cluster that u can use to run commands to test and gather info about network functionality.
# See https://github.com/nicolaka/netshoot & https://github.com/komuw/docker-debug


