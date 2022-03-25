#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob globstar

## chapter 3.
# K8s management:
# - Intro to high availability.
# - Intro to k8s management tools.
# - Safely drainig a k8s node.
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



















