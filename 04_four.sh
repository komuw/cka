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

## chapter 4. Kubernetes Object Management.

# Working with kubectl: https://kubernetes.io/docs/reference/kubectl/cheatsheet/
#  - kubectl get           : list objects in cluster.
#  - kubectl describe      : detailed info about objects.
#  - kubectl create        : create objects. -f <file-name>. if object exists it errors.
#  - kubectl apply         : similar to create, if object exists it updates.
#  - kubectl delete
#  - kubectl exec          : run command inside container.
#  - kubectl api-resources :lists all the resources/objects in a cluster. This resources can then be used in `kubectl get <resource>`

kubectl_cheatsheet(){
    set -ex
    # https://kubernetes.io/docs/reference/kubectl/cheatsheet/
    # lists all the resources/objects in a cluster. This resources can then be used in `kubectl get <resource>`
    kubectl api-resources
    
    # use a different kubeconfig
    kubectl --kubeconfig=/path/to/kubeconfig.yaml get pods
    export KUBECONFIG=/path/to/kubeconfig.yaml kubectl get pods
    kubectl config view # show the kubeconfig in use
    kubectl config view --raw # show whole config. You can send this to another computer and use kubectl in that computer to access the cluster.
    kubectl get all --all-namespaces # show all objects in all namespaces.
    kubectl get all -n foo # show all objects in namespace foo.

    # get pods/services
    kubectl get services --all-namespaces
    kubectl get pods --all-namespaces
    kubectl get deployment myDeploy --namespace=hey-dev --output=yaml # get yaml output of a resource, you can then pass it to kubectl apply -f

    # describe a pod
    kubectl describe pod --namespace=hey-dev nginx-hey-69d7876896-pml5q

    # fetch logs(selecting by labels)
    kubectl logs -f --namespace=hey-dev -l app.kubernetes.io/instance=hey --all-containers=true --max-log-requests=21
    kubectl logs -f --namespace=hey-dev -l app.kubernetes.io/component=billing --all-containers=true
    kubectl logs -f --namespace=hey-dev -l app.kubernetes.io/component=controller --all-containers=true
    kubectl logs -f --namespace=hey-dev -l app.kubernetes.io/component=dashboard --all-containers=true

    # exec into a pod
    kubectl exec --stdin --tty my-pod -- /bin/sh                  # 1 container case
    kubectl exec --stdin --tty my-pod -c my-container -- /bin/sh  # multi-container case
    kubectl exec --namespace=namespace --stdin --tty podName -- /bin/sh
    
    # run a debugging pod in the context of another pod. it is like a better `kubectl run` or `kubectl exec`
    kubectl debug --namespace=someNamespace some-pod-26phw --container='my-debugger-pod' -it --image=komuw/debug:latest

    # show resource usages
    kubectl top pod --all-namespaces
    kubectl top node

    kubectl delete pod --namespace=hey my_pod

    # persistent volumes & persistent-volume-claims: https://kubernetes.io/docs/concepts/storage/persistent-volumes/
    kubectl get pv                                                                                 
    kubectl get pvc --all-namespaces
    kubectl describe pv <name>
    kubectl describe pvc --namespace=namespace <name>

    # secrets
    kubectl get secrets --all-namespaces
    kubectl describe secret --namespace=namespace <secret_name>
    kubectl get secret --namespace=foobarbaz-bingbong hey-home -o yaml # You can also add `--export` to remove unneccesary data.
    kubectl get secret --namespace=foobarbaz-bingbong hey-home --template={{.data.mongoCS}} | base64 -d

    # networkPolicy
    kubectl get networkpolicy --all-namespaces
    kubectl get networkpolicy --namespace=foobarbaz-bingbong <name>
    kubectl describe networkpolicy --namespace=foobarbaz-bingbong <name>

    # endpoints
    kubectl get endpoint --all-namespaces # really good to see which services map to which pods and their IPs
    
    # get events
    kubectl get events --all-namespaces
    kubectl get events --all-namespaces --field-selector type!=Normal # get the ones that are troublesome

    # create a pod for testing. This one has ping,telnet,wget etc already installed.
    # Note; you can specify labels, namespace etc.
    # eg for this case, we run it in kube-system namespace bcoz we want to test wether we can ping a pod from the kube-system NS
    kubectl run \
    --namespace=kube-system \
    --labels="app=tester-pod,env=dev,country=kenya" \
    tester-pod \
    --rm -ti \
    --image busybox \
    /bin/sh


    # get a sample yaml file quickly. This yaml file can then be used in later commands.
    kubectl create deployment my-deployment --image=nginx --dry-run -o yaml
    kubectl create deployment my-deployment --image=nginx --dry-run --export -o yaml > /tmp/mytmpl.yaml # export removes unneccesary data.

    # record the command that was used to make a change.
    kubectl scale deployment my-deployment replicas=5 --record 
    kubectl describe deployment my-deployment # The annotations will have the command that was recorded.
}


# Managing kubernetes role-based access control(RBAC)
# Control what users are allowed to do and access within the cluster.
# RBAC objects:
#  (a) Roles & ClusterRoles: k8s objects that define set of permissions.
#                            Role define perms in a namespace, ClusterRole define perms cluster-wide.
#  (b) RoleBinding & ClusterRoleBinding: objects that connect roles and clusterRoles to users.
#  
create_rbac(){
    set -ex

    { # try
      kubectl get pods -n beebox-mobile --kubeconfig dev-k8s-config
    } || { # catch
      printf "\n\t dev user does not have permission to list pods. \n"
    }

    rm -rf /tmp/role.yml /tmp/role_binding.yml
    kubectl get role --all-namespaces
    kubectl get rolebinding --all-namespaces
    

    role_contents='
# ClusterRoles dont have a namespace, and kind is ClusterRole.
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: beebox-mobile
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "watch", "list"]
'

    insert_if_not_exists "pod-reader" "${role_contents}" /tmp/role.yml
    kubectl apply -f /tmp/role.yml


    role_binding_contents='
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader
  namespace: beebox-mobile
subjects:
- kind: User
  name: dev
  apiGroup: rbac.authorization.k8s.io
# roleRef is what connects this binding. ie we are binding it to the Role called pod-reader created in /tmp/role.yml
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
'
    insert_if_not_exists "pod-reader" "${role_binding_contents}" /tmp/role_binding.yml
    kubectl apply -f /tmp/role_binding.yml

    # dev user should now be able to list pods.
    sleep 3
    kubectl get pods -n beebox-mobile --kubeconfig dev-k8s-config
}


# Service Accounts:
#  - what are they? : Account used by container process within pods to authenticate with k8s API.
#                     If your pod needs comms with k8s API, u can use service account to control their access.
#  - creating them.
#  - Binding roles to service accounts.
#
# You can manage their access by binding serviceAccounts with ClusterRole or ClusterRoleBinding

create_service_accounts(){
    set -ex

    rm -rf /tmp/service_account.yml /tmp/service_account_role.yml /tmp/service_account_role_binding.yml

    service_account_contents='
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-service-account
  namespace: beebox-mobile
'
    insert_if_not_exists "my-service-account" "${service_account_contents}" /tmp/service_account.yml
    kubectl apply -f /tmp/service_account.yml

    role_contents='
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: beebox-mobile
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "watch", "list"]
'
    insert_if_not_exists "pod-reader" "${role_contents}" /tmp/service_account_role.yml
    kubectl apply -f /tmp/service_account_role.yml

    role_binding_contents='
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: sa-pod-reader
  namespace: beebox-mobile
subjects:
- kind: ServiceAccount
  name: my-service-account
  namespace: beebox-mobile
# roleRef is what connects this binding. ie we are binding it to the Role called pod-reader created in /tmp/service_account_role.yml
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
'
    insert_if_not_exists "sa-pod-reader" "${role_binding_contents}" /tmp/service_account_role_binding.yml
    kubectl apply -f /tmp/service_account_role_binding.yml

    # check the service_account we created.
    kubectl describe serviceaccount my-service-account --namespace=beebox-mobile
}



# Pod resource usage:
#  - k8s metrics server: An addon that collects and provides metric data. This is one of many other such addons.
#  - kubectl top
install_k8s_metrics_server(){
    set -ex

    rm -rf /tmp/pod.yml

    # The one from this URL is a custom one that works with clusters created using kubeadm.
    # The default one does not work with kubeadm clusters.
    kubectl apply -f https://raw.githubusercontent.com/ACloudGuru-Resources/content-cka-resources/master/metrics-server-components.yaml

    # query to make sure install worked.
    sleep 2
    kubectl get --raw /apis/metrics.k8s.io/

    pod_contents="
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  namespace: beebox-mobile
  labels:
    app: metrics-test
spec:
  containers:
  - name: busybox
    image: radial/busyboxplus:curl
    command: ['sh', '-c', 'while true; do sleep 3600; done']
"
    insert_if_not_exists "my-pod" "${pod_contents}" /tmp/pod.yml
    kubectl apply -f /tmp/pod.yml

    kubectl get pods --all-namespaces

    # It can take a few mins for metric-server to collect data.
    # You might get an error if server has not collected data.
    sleep 3
    kubectl top pod --sort-by cpu --all-namespaces
    kubectl top node
}
