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

## chapter 6: Advanced pod Allocation.

# 1. Exploring k8s scheduling.
# 2. Using daemonsets.
# 3. Using static pods.


# 1. Exploring k8s scheduling.
# Scheduling is process of assigning pods to nodes so that kubelet can run them.
# Scheduler is the control-plane component that handles scheduling. The things that a Scheduler takes into account are;
#   - resource requests vs available node resources.
#   - various configurations that affect scheduling eg, using node labels.
#
# - nodeSelector: Pod onfiguration to limit which nodes the pod can be scheduled on.
#                 It uses node labels to filter suitable nodes.
# - nodeName:     Assign a pod to a specific node by name, thus bypassing scheduling.
nodeSelector_pod(){
    pod_contents="
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  nodeSelector: # another option `nodeName: myNode`
    nodeType: app # only schedule this pod on nodes that have label `nodeType == app`
  containers:
  - name: busybox
    image: busybox
"
}

# 2. Using daemonsets.
# DaemonSets automatically runs a copy of a pod on each node.
# They DO respect scheduling rules. If a pod would not normally be scheduled in a node, a daemonset will not run it in the node.
# Pods have to match a selector in order to be identified as pods been managed by the daemonSet.
# Example usecase: there's some trash files that need to be periodically removed from all nodes.
add_daemonset(){
    the_contents="
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: my-cleanup
spec:
  selector:
    matchLabels:
      app: workers # pods having this label will be managed by this daemonSet.
  template:
    metadata:
      labels:
        app: workers # should be same as what is in `matchLabels` above.
    spec:
      containers:
      - name: nginx
        image: nginx
"
}

# 3. Using static pods.
# Static pod: Is managed directly by the kubelet on a node, not by the k8s API server. They can run even if k8s API server is not present.
#             There's a manifest path on nodes. If you put yaml files in there, kubelet will automatically create static pods.
# Mirror pod: Pod that is auto created by kubelet for each static pod. It allows u to see status of the static pod via k8s API.
#             You cannot change/manage them via k8s API. It is a ghost rep of static pod.
#
# Example usecase: A pod that you want to run independent of the k8s API server. Maybe to collect metrics, etc.
add_static_pod(){
    pod_contents="
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  containers:
  - name: busybox
    image: busybox
"
    # The manifest path/dir where static pods can be put.
    # This is the one that is default for kubeadm, but a different one can be configured.
    STAT_POD_PATH = "/etc/kubernetes/manifests"

    podPath = "${STAT_POD_PATH}/my_pod.yml"
    insert_if_not_exists "my-pod" "${pod_contents}" podPath

    # You can wait a little while and kubelet will automatically start the pod.
    # Alternatively; restart kubelet: `sudo systemctl restart kubelet`
}


