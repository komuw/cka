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

## chapter 7: Deployments

# A deployment is a k8s object that defines a desired state for a ReplicaSet.
# A ReplicaSet is a group of replica pods(ie, multiple copies of same pod).
# Deployment controller maintains the desired state.
# Example usecase:
#  - Easily scale an app by changing number of replicas.
#  - Perform rolling updates(by changing the image version.)
my_deployment(){
    contents="
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-dep
spec:
  replicas: 3
  selector:
    # All pods that match this selector will be managed by this Deployment.
    # Irrespective of how the pods were created. ie, even if the pods were created in another yaml file etc.
    matchLabels:
      app: workers
  template: # allow us to create pods 'inline' to Deployment
    metadata:
      labels:
        app: workers 
    spec:
      containers:
      - name: busybox
        image: busybox
        imagePullPolicy: IfNotPresent
"
}

# Scaling apps with Deployments.
# Scale is dedicating more/fewer resources to an app in order to meet changing needs.
# Deployments help in horizontal scaling.
# We can scale up/down by changing the `spec.replicas` number.
scaling(){
    kubectl scale <deploymentName> --replicas=4
}

# Managing rolling updates with Deployments.
# Rolling update allows you to make changes to a Deployment's pods at a controlled rate; gradually replacing old pods with new ones.
# This eliminates downtime.
deployment_rolling_update(){
    contents="
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-dep
spec:
  replicas: 3
  selector:
    matchLabels:
      app: workers
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
  ...
  ...
"
}
