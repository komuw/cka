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

# 5. part 5.
# (a) Upgrade all components on the control plane node to Kubernetes version 1.22.2.
# (b) Upgrade all components on the two worker nodes to Kubernetes version 1.22.2.
part_five(){
    kubectl config use-context acgk8s # Switch to the `acgk8s` k8s cluster.

    # (a)
    sudo apt -y update
    kubectl get nodes
    kubectl drain <control_plane_name> --ignore-daemonsets
    sudo apt -y install --allow-change-held-packages kubeadm=1.22.2-00
    sudo kubeadm upgrade plan v1.22.2
    sudo kubeadm upgrade apply v1.22.2
    sudo apt -y install --allow-change-held-packages kubelet=1.22.2-00 kubectl=1.22.2-00
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet
    kubectl uncordon <control_plane_name>

    # (b)
    kubectl drain acgk8s-worker1 --ignore-daemonsets --force # Should be ran in control-plane.
    ssh acgk8s-worker1
    sudo apt -y update
    sudo apt -y install --allow-change-held-packages kubeadm=1.22.2-00
    sudo kubeadm upgrade node
    sudo apt -y install --allow-change-held-packages kubelet=1.22.2-00 kubectl=1.22.2-00
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet
    exit # to get out of ssh and go back to cp node.
    kubectl uncordon acgk8s-worker1 # Should be ran in control-plane.

    kubectl drain acgk8s-worker2 --ignore-daemonsets --force # Should be ran in control-plane.
    ssh acgk8s-worker2
    sudo apt -y update
    sudo apt -y install --allow-change-held-packages kubeadm=1.22.2-00
    sudo kubeadm upgrade node
    sudo apt -y install --allow-change-held-packages kubelet=1.22.2-00 kubectl=1.22.2-00
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet
    exit # to get out of ssh and go back to cp node.
    kubectl uncordon acgk8s-worker2 # Should be ran in control-plane.

    ./verify.sh
}

# 6. part 6.
# (a) Drain Worker Node 1(acgk8s-worker1)
# (b) Create a Pod That Will Only Be Scheduled on Nodes with a Specific Label
#     Add the disk=fast label to the acgk8s-worker2 Node.
#     Create a pod called fast-nginx(nginx image) in the dev namespace that will only run on nodes with this label.
part_six(){
    kubectl config use-context acgk8s # Switch to the `acgk8s` k8s cluster.

    kubectl drain acgk8s-worker1 # This will give error, and also tell you which flags u need to add.
    kubectl drain acgk8s-worker1 --ignore-daemonsets --force --delete-local-data

    kubectl label nodes acgk8s-worker2 disk=fast
    pod_contents="
apiVersion: v1
kind: Pod
metadata:
  name: fast-nginx
  namespace: dev
spec:
  nodeSelector:
    disk: fast
  containers:
  - name: nginx
    image: nginx
"

    ./verify.sh
}

# 7. part 7.
# (a) Create a PersistentVolume
#     It will be called `host-storage-pv` with storage capacity 1Gi in the acgk8s context.
#     Configure it so that volumes that use it can be expanded in the future.
#     Note: This may require you to create additional objects.
# (b) Create a Pod That Uses the PersistentVolume for Storage
#     Pod called `pv-pod` in the `auth`` Namespace. It should use the `host-storage-pv` PersistentVolume for storage.
#     This will require a PVC `host-storage-pvc` with size 100Mi in same namespace.
#     Mount the volume that uses the PV for storage, so that `/output` directory ultimately writes to the PV.
# (c) Expand the PersistentVolumeClaim so that it requests 200Mi.
part_seven(){
    kubectl config use-context acgk8s # Switch to the `acgk8s` k8s cluster.

    sc="
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: localdisk
provisioner: kubernetes.io/no-provisioner # store on host disk.
allowVolumeExpansion: true # VERY important.
"
    pv="apiVersion: v1
kind: PersistentVolume
metadata:
  name: host-storage-pv
spec:
  storageClassName: localdisk
  persistentVolumeReclaimPolicy: Recycle
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /etc/data
"
    pvc="apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: host-storage-pvc
  namespace: auth
spec:
  storageClassName: localdisk
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi # For part (c) of the question, edit this and use 200Mi 
"
    pod="apiVersion: v1
kind: Pod
metadata:
  name: pv-pod
  namespace: auth
spec:
  containers:
  - name: busybox
    image: busybox
    command: ['sh', '-c' 'while true; do echo success > /output/output.log; sleep 5; done']
    volumeMounts:
    - name: pv-storage
      mountPath: /output # directory inside the container where volume is at.
  volumes:
  - name: pv-storage
    persistentVolumeClaim:
      claimName: host-storage-pvc # Should match the pvc.metadata.name
"

    ./verify.sh
}

# 8. part 8.
# (a) Create a networkPolicy that denies all access to the `maintenance` pod in the `foo` namespace.
# (b) Create a networkPolicy that allows ALL pods in the `users-backend` namespace to communicate with each other only on port 80.
part_eight(){
    kubectl config use-context acgk8s # Switch to the `acgk8s` k8s cluster.

    kubectl describe pod maintenance -n foo # Look at the labels it has.
    lockdown_np_contents="
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: my-networkpolicy
  namespace: foo
spec:
  podSelector:
    matchLabels:
      app: maintenance # This is one of the labels we got from running `kubectl describe pod maintenance -n foo`.
  policyTypes:
  - Ingress
  - Egress
"

    kubectl label namespace users-backend app=users-backend # Label the NS to make it easier to do things with it.
    allow_np_contents="
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: my-networkpolicy
  namespace: users-backend
spec:
  podSelector: {} # Leaving it empty will match all pods in the `users-backend` NS.
  policyTypes:
  - Ingress # This NP does not apply to `Egress`
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: users-backend # Allow traffic from any pods in the `users-backend` NS to the pods in same NS at port 80.
    ports:
    - protocol: TCP
      port: 80
"

    ./verify.sh
}
