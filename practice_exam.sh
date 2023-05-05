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

# 1. part 1.
# (a) Count the Number of Nodes That Are Ready to Run Normal Workloads
# (b) Retrieve Error Messages from a Container Log
#     In the backend namespace, check the log for the proc container in the data-handler Pod.
# (c) Find the Pod with a Label of app=auth in the Web Namespace That Is Utilizing the Most CPU
#     Determine which Pod in the web namespace with the label app=auth is using the most CPU. Save the name of this Pod to the file
#     Before doing this step, please wait a minute or two to give our backend script time to generate CPU load.
#
# Note: In the practice exam labs check on, for additional info at the right side-bar on the acloudguru.com/course/certified-kubernetes-administrator-cka website.
# - Additional Resources
# - Learning Objectives
part_one(){
    kubectl config use-context acgk8s # Switch to the `acgk8s` k8s cluster.

    # - control plane nodes cannot run normal workloads hence need to be excluded.
    # - nodes with some special tolerations/taints(eg `NoSchedule`) cannot run normal workloads.
    # - nodes not in the Ready state cannot run workloads
    kubectl get nodes | grep -i 'ready'
    kubectl logs data-handler -c proc -n backend | grep ERROR
    kubectl top pod -l app=auth --sort-by cpu -n web

    ./verify.sh # run script to verify that the 3 objectives have been achieved.
}

# 2. part 2.
# (a) In the web namespace, there is a deployment called web-frontend.
#     Edit this deployment so that the containers within its Pods expose port 80.
# (b) Create a service called web-frontend-svc in the web namespace. 
#     This service should make the Pods from the web-frontend deployment in the web namespace reachable from outside the cluster.
# (c) Scale the web-frontend deployment in the web namespace up to 5 replicas.
# (d) Create an Ingress called web-frontend-ingress in the web namespace that maps to the web-frontend-svc service in the web namespace. 
#     The Ingress should map all requests on the / path.
part_two(){
    kubectl config use-context acgk8s # Switch to the `acgk8s` k8s cluster.

    kubectl edit deployment web-frontend -n web # `spec.template.spec.containers.ports.containerPort: 80`
    nodeport_svc_contents="
apiVersion: v1
kind: Service
metadata:
  name: web-frontend-svc
  namespace: web
spec:
  type: NodePort
  selector:
    app: web-frontend
  ports:
    - protocol: TCP
      port: 80        # the service's port. It is usually set to same value as `targetPort`.
      targetPort: 80  # the port where the pods are listening at.
      nodePort: 30080 # the port on the server/nodes. You can access this port on ANY node(cp or workers) and it will just work.
"
    kubectl Scale deployment web-frontend -n web --replicas=5
    the_ingress_contents="
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-frontend-ingress
  namespace: web
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-frontend-svc
            port:
              number: 80 # If Service uses a named port, Ingress can also use the port's name.
"

    ./verify.sh
}

# 3. part 3.
# (a) Create a service account in the web namespace called webautomation.
# (b) Create a ClusterRole That Provides Read Access to Pods
#     It will be called pod-reader that has get, watch, and list access to all Pods.
# (c) Bind the ClusterRole to the Service Account to Only Read Pods in the web Namespace
part_three(){
    kubectl config use-context acgk8s # Switch to the `acgk8s` k8s cluster.

    service_account_contents='
apiVersion: v1
kind: ServiceAccount
metadata:
  name: webautomation
  namespace: web
'

    cluster_role_contents='
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
'
    rolebinding_contents='
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: sa-pod-reader
  namespace: web
subjects:
- kind: ServiceAccount
  name: webautomation
  namespace: web
# roleRef is what connects this binding. ie we are binding it to the Role called pod-reader
roleRef:
  kind: ClusterRole
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
'

    ./verify.sh
}

# 4. part 4.
# For this question, you will need to ssh into the ectd1.
# ie, from the root server run `ssh etcd1`
# Auth certificates are located in `/home/cloud_user/etcd-certs`
# (a) Back Up the etcd Data, to a file located at /home/cloud_user/etcd_backup.db
# (b) Restore the etcd Data from the Backup, from the backup file at /home/cloud_user/etcd_backup.db
part_four(){
    kubectl config use-context acgk8s # Switch to the `acgk8s` k8s cluster.

    ssh etcd1

    hostname --all-ip-addresses # to find private IP
    NODE_PRIVATE_IP="etcd1" # For some reason, using the private IP found by `hostname --all-ip-addresses` does not work.
    BACKUP_FILE="/home/cloud_user/etcd_backup.db"
    BACKUP_PORT="2379"
    RESTORE_PORT="2380"
    CA_CERT_LOCATION="/home/cloud_user/etcd-certs/etcd-ca.pem"
    CERT_LOCATION="/home/cloud_user/etcd-certs/etcd-server.crt"
    CERT_KEY_LOCATION="/home/cloud_user/etcd-certs/etcd-server.key"

    ETCDCTL_API=3 \
      etcdctl \
          snapshot \
          save \
          ${BACKUP_FILE} \
          --endpoints=https://${NODE_PRIVATE_IP}:${BACKUP_PORT} \
          --cacert=${CA_CERT_LOCATION} \
          --cert=${CERT_LOCATION} \
          --key=${CERT_KEY_LOCATION}

    sudo systemctl stop etcd
    sudo rm -rf /var/lib/etcd

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

    ./verify.sh
}
