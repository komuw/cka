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

## chapter 8: Networking

# k8s network model:
# This is a set of standards that define how networking between pods behaves.
# There are a variety of different implementations of this model, eg calico network plugin.
# - Each pod has its own unique IP address.
# - Any pod can reach any other using that pod's IP address.

# CNI plugins:
# They provide network connectivity between pods according to the k8s network model.
# k8s nodes will remain in the `NotReady` status until a network plugin is installed.

# DNS in k8s:
# The k8s virtual network uses DNS to allow pods to locate other pods & services, instead of using IP addresses.
# It runs as a service in the cluster; its components can be found in the `kube-system` namespace.
# kubeadm uses `CoreDNS`.
# All pods are automatically given a dns domain like;
#   `pod-ip-address.namespace.pod.cluster.local` eg `192-168-100.default.pod.cluster.local` note that IP has hyphens.

# Network Policies:
# k8s object that lets u control the flow of network comms to & from pods.
# This enhances security by keeping pods isolated from traffic that they do not need.
# By default, pods are considered open to all communication.
#   - spec.podSelector: determines which pods in the namespace, the NetworkPolicy applies to.
#
# Once a NetworkPolicy selects a pod, it will be isolated and only open to traffic allowed by that NetworkPolicy
# NetworkPolicy can apply to Ingress(incoming traffic to the pod), Egress(outgoing traffic from pod) or both.
#   - from selector: selects Ingress traffic that will be allowed.
#   - to selector:   selects Egress traffic that will be allowed.
#   - podSelector:   selects pods to allow traffic from/to
#   - namespaceSelector: select namespace to allow traffic from/to
#   - ipBlock: select an IP range to allow traffic from/to
#   - port: specifies one or more ports that will allow traffic.
my_network_policy(){
    pod_one_contents="
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: some-namespace
  labels:
    app: api
spec:
  containers:
  - name: nginx
    image: nginx
"

    pod_two_contents="
apiVersion: v1
kind: Pod
metadata:
  name: busybox
  namespace: some-namespace
  labels:
    app: client
spec:
  containers:
  - name: busybox
    image: busybox
"

    # This NetworkPolicy will block all comms to the pods with the given label/s.
    # This is because the NP does not have an `ingress.from` or `egress.to` section.
    lockdown_np_contents="
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: my-networkpolicy
  namespace: some-namespace
spec:
  podSelector:
    matchLabels:
      app: api # This NP applices to the pods with this label.
  policyTypes:
  - Ingress
  - Egress
"

    allow_np_contents="
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: my-networkpolicy
  namespace: some-namespace
spec:
  podSelector:
    matchLabels:
      app: api # This NP applices to the pods with this label.
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: some-namespace # Allow traffic from any pods in the `some-namespace` NS to the pods with label(`app: api`) at port 80.
    ports:
    - protocol: TCP
      port: 80
"
}
