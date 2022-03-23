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
#     (b) container-runtime: It is not built into k8s, instead it is a separate piece of software for actually running containers.
#                            examples are; docker, containerd etc
#     (c) kube-procy: It's a network proxy. Handles tasks related to providing networking btwn containers & services running in the cluster.
#     (c) containers: The containers themselves.








