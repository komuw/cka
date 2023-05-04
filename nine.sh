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

## chapter 9: Services

# - service.
# - service routing.
# - endpoints.

# Service: Provides a way to expose an app running as a set of pods.
#          They provide an abstrac way for clients to access apps without needing to be aware of the app's pods.
#          Clients make requests to a Service, which routes that traffic to its pods in a load-balanced manner.
# Endpoints: They are the backend entities to which Services route traffic.
#            If a service routes traffic to multiple pods, each pod will have an endpoint associated with the service.
#            One way to determine which pods a Servie is routing to, is to look at that Service's endpoints.

# ServiceTypes: The type determines how & where the Service will expose your app. There are four types:
# (a) ClusterIP: They expose apps inside the cluster network. Use them if clients are other pods in the cluster.
# (b) NodePort: They expose apps outside the cluster network. Use them if clients are from outside the cluster.
# (c) LoadBalancer: They expose apps outside the cluster network, but they use external cloud load balancers to do so.
# (d) ExternalName. This out of scope in CKA.
my_services(){
    dep_contents="
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-dep
spec:
  replicas: 3
  selector:
    matchLabels:
      app: app-workers 
  template:
    metadata:
      labels:
        app: app-workers 
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
"

    cluster_svc_contents="
apiVersion: v1
kind: Service
metadata:
  name: svc-cluster-ip
spec:
  type: ClusterIP # Used by clients that in the same cluster. ClusterIP is the default and thus can be left out from the yaml
  selector:
    app: app-workers
  ports:
    - protocol: TCP
      port: 8080     # the service's port.
      targetPort: 80 # the port where the pods are listening at.
"

    nodeport_svc_contents="
apiVersion: v1
kind: Service
metadata:
  name: svc-node-port
spec:
  type: NodePort
  selector:
    app: app-workers
  ports:
    - protocol: TCP
      port: 80        # the service's port.
      targetPort: 80  # the port where the pods are listening at.
      nodePort: 30080 # the port on the server/nodes. You can access this port on ANY node(cp or workers) and it will just work.
"

    client_pod_contents="
apiVersion: v1
kind: Pod
metadata:
  name: client-pod
spec:
  containers:
  - name: busybox
    image: busybox
    command: ['sh', 'sleep 4500']
"

  kubectl exec client-pod -- curl svc-cluster-ip:8080  # clusterIP
  kubectl exec client-pod -- curl svc-cluster-ip.default.svc.cluster.local:8080  # clusterIP, access using fqdn.
  curl localhost:30080                                 # NodePort
}

# - Service DNS Names: Services are assigned DNS names allowing apps within cluster to easily locate them. It has format;
#                      `service-name.namespace.svc.cluster-domain`. Default `cluster-domain` is `cluster.local`
#                      `service-name.namespace.svc.cluster.local`
#                      A service can be reached using its fqdn from ANY namespace.
#                      However, pods within same namespace can use a short name; `service-name`

# Ingress:            Is k8s object that manages external access to services in a cluster.
#                     It provides more functionality than a NodePort service, eg;
#                     SSL termination, advanced load-balancing, name-based virtual hosting, etc.
# Ingress Controller: These are the things that make Ingress objects work.
#                     There are a variety of these and you can install whichever has the features that you want.
#                     eg; nginx-ingress-controller, haproxy-ingress-controller etc.
# Ingresses define a set of routing rules. A routing rules properties determine to which requests it applies to.
my_ingress(){
    contents="
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
spec:
  rules:
  - http:
      paths:
      - path: /somePath
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80 # If Service uses a named port, Ingress can also use the port's name.
"
  # A request to http://<some-endpoint>/somePath will be routed to port 80 on the my-service Service.
}

# Client -> Ingress-Controller -> Ingress -> Service -> NetworkPolicy -> | Pod1 |
#                                                                        | Pod2 |
#                                                                      | Deployment |
