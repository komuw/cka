#!/usr/bin/env bash

set -euo pipefail


## chapter 3. Cluster management.

# K8s management:
# - Intro to high availability.
# - Intro to k8s management tools.
# - Safely draining a k8s node.
# - Upgrading k8s with kubeadm.
# - Backing up & restoring etcd cluster data.


# High availability(see: imgs/HA-control-plane.png):
# - High availability control plane.
# - Stacked etcd.
# - External etcd.
#
# We need multiple control plane Nodes to get HA.
#  [cp-1]  [cp-2]  # multiple control-plane nodes.
#       [lb]  ie load balancer
#        ^
#      /   \ 
#  kubectl  kubelet(running in worker nodes.)
#
# In the context of HA control-plane, there are multiple ways in which we can manage etcd.
#  (a) Stacked; etcd runs in each of those control-plane nodes. kubeadm uses this.
#  (b) External; etcd running in external server/s.

# K8s management tools.
#  (a) kubectl; official cli for k8s.
#  (b) kubeadm; easily create clusters.
#  (c) minikube; setup k8s cluster using one server/machine.
#  (d) helm; templating & package management for k8s objects.
#  (e) kompose; transtion from docker/docker-compose to k8s.
#  (f) kustomize; cfg management tool for managing k8s object configs. Kind a bit like helm.

# Safely draining a node.
# Drain: Remove a k8s node from service. eg during maintenance.
#        containers are terminated and/or rescheduled in other nodes.
#        You may need to ignore Daemonsets(pods that are tied to each node.)
#        You may also need to ignore any stand-alone pods(that aren't part of a deployment/replicaset etc) using `--force` flag
# Uncordon: Allow pods to run on the node after maintenance is complete.
#           ie, Mark node as schedulable.
#           uncordon does not cause already running pods to be rescheduled, but newly created pods can be scheduled in the node.
kubectl get nodes
kubectl drain <node-name> --ignore-daemonsets --force
kubectl uncordon <node-name>

# Upgrading k8s.
# - control plane steps.
# - worker node steps.
# 
# (a) control-plane upgrade.
#     - drain node
#     - upgrade kubeadm
#     - plan upgrade
#     - apply upgrade
#     - upgrade kubelet & kubectl
#     - uncordon node.
#
# (b) worker upgrade.
#     - drain node
#     - upgrade kubeadm
#     - upgrade kubelet configuration
#     - upgrade kubelet & kubectl
#     - uncordon node.

upgrade_control_plane(){
    set -ex
    control_plane_name=$1

    kubectl get nodes
    kubectl drain "${control_plane_name}" --ignore-daemonsets
    sudo apt -y update
    kubeadm version
    sudo apt -y install --allow-change-held-packages kubeadm=1.22.2-00
    kubeadm version
    sudo kubeadm upgrade plan v1.22.2
    sudo kubeadm upgrade apply v1.22.2
    kubelet --version
    kubectl version
    sudo apt -y install --allow-change-held-packages kubelet=1.22.2-00 kubectl=1.22.2-00
    kubelet --version
    kubectl version
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet
    kubectl uncordon "${control_plane_name}"
    sleep 3
    kubectl get nodes
}
upgrade_control_plane k8s-control

upgrade_worker(){
    set -ex
    worker_name=$1

    { # try
      kubectl drain "${worker_name}" --ignore-daemonsets --force # this specific command should be ran in control-plane.
    } || { # catch
      echo -n ""
    }
    sudo apt -y update
    kubeadm version
    sudo apt -y install --allow-change-held-packages kubeadm=1.22.2-00
    kubeadm version
    sudo kubeadm upgrade node
    kubelet --version # you cant run `kubectl version` in workers, fails with error about port.
    sudo apt -y install --allow-change-held-packages kubelet=1.22.2-00 kubectl=1.22.2-00
    kubelet --version
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet
    { # try
      kubectl uncordon "${worker_name}" # this specific command should be ran in control-plane.
    } || { # catch
      echo -n ""
    }
}
upgrade_worker k8s-worker1
upgrade_worker k8s-worker2


# Backing up & restoring etcd cluster data.
# - Why backup : All k8s objects, apps and configs are stored in etcd.
# - Backing up etcd
# - Restoring etcd

backup_etcd(){
    # usage:
    #    backup_etcd "10.0.1.101" "2379" "2380" "/tmp/ca.pem" "/tmp/cert.crt" "/tmp/key.key" "/tmp/etcd_backup.db"
    set -ex

    NODE_PRIVATE_IP=$1
    BACKUP_PORT=$2
    RESTORE_PORT=$3
    CA_CERT_LOCATION=$4
    CERT_LOCATION=$5
    CERT_KEY_LOCATION=$6
    BACKUP_FILE=$7

    CLUSTER_NAME=$(ETCDCTL_API=3 etcdctl get cluster.name \
                --endpoints=https://${NODE_PRIVATE_IP}:${BACKUP_PORT} \
                --cacert=${CA_CERT_LOCATION} \
                --cert=${CERT_LOCATION} \
                --key=${CERT_KEY_LOCATION})
    printf "\n\t CLUSTER_NAME is: ${CLUSTER_NAME} \n"

    ETCDCTL_API=3 \
      etcdctl \
          snapshot \
          save \
          ${BACKUP_FILE} \
          --endpoints=https://${NODE_PRIVATE_IP}:${BACKUP_PORT} \
          --cacert=${CA_CERT_LOCATION} \
          --cert=${CERT_LOCATION} \
          --key=${CERT_KEY_LOCATION}
}

restore_etcd(){
    # usage:
    #    restore_etcd "10.0.1.101" "2379" "2380" "/tmp/ca.pem" "/tmp/cert.crt" "/tmp/key.key" "/tmp/etcd_backup.db"
    set -ex

    NODE_PRIVATE_IP=$1
    BACKUP_PORT=$2
    RESTORE_PORT=$3
    CA_CERT_LOCATION=$4
    CERT_LOCATION=$5
    CERT_KEY_LOCATION=$6
    BACKUP_FILE=$7

    ETCDCTL_API=3 \
    sudo etcdctl \
      snapshot \
      restore \
      ${BACKUP_FILE} \
      --initial-cluster etcd-restore=https://${NODE_PRIVATE_IP}:${RESTORE_PORT} \
      --initial-advertise-peer-urls https://${NODE_PRIVATE_IP}:${RESTORE_PORT} \
      --name etcd-restore \
      --data-dir /var/lib/etcd
    # The name `etcd-restore` in `--initial-cluster` needs to match the one in `----name`

    sudo chown -R etcd:etcd /var/lib/etcd

    { # try
      sudo systemctl restart etcd
    } || { # catch
      sudo systemctl start etcd
    }

    CLUSTER_NAME=$(ETCDCTL_API=3 etcdctl get cluster.name \
                --endpoints=https://${NODE_PRIVATE_IP}:${BACKUP_PORT} \
                --cacert=${CA_CERT_LOCATION} \
                --cert=${CERT_LOCATION} \
                --key=${CERT_KEY_LOCATION})
    # The $CLUSTER_NAME here should match the one in `backup_etcd` assuming the restore happened succesfully.
    printf "\n\t CLUSTER_NAME is: ${CLUSTER_NAME} \n"
}
