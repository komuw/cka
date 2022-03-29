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

## chapter 4.
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

    # get pods/services
    kubectl get services --all-namespaces
    kubectl get pods --all-namespaces

    # describe a pod
    kubectl describe pod --namespace=ara-dev controller-ara-69d7876896-pml5q

    # fetch logs(selecting by labels)
    kubectl logs -f --namespace=ara-dev -l app.kubernetes.io/instance=ara --all-containers=true --max-log-requests=21
    kubectl logs -f --namespace=ara-dev -l app.kubernetes.io/component=billing --all-containers=true
    kubectl logs -f --namespace=ara-dev -l app.kubernetes.io/component=controller --all-containers=true
    kubectl logs -f --namespace=ara-dev -l app.kubernetes.io/component=dashboard --all-containers=true

    # exec into a pod
    kubectl exec --stdin --tty my-pod -- /bin/sh                  # 1 container case
    kubectl exec --stdin --tty my-pod -c my-container -- /bin/sh  # multi-container case
    kubectl exec --namespace=namespace --stdin --tty podName -- /bin/sh

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
    kubectl get secret --namespace=foobarbaz-bingbong ara-home -o yaml
    kubectl get secret --namespace=foobarbaz-bingbong ara-home --template={{.data.mongoCS}} | base64 -d

    # networkPolicy
    kubectl get networkpolicy --all-namespaces
    kubectl get networkpolicy --namespace=foobarbaz-bingbong <name>
    kubectl describe networkpolicy --namespace=foobarbaz-bingbong <name>

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
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
'
    insert_if_not_exists "pod-reader" "${role_binding_contents}" /tmp/role-binding.yml
    kubectl apply -f /tmp/role-binding.yml

    # dev user should now be able to list pods.
    kubectl get pods -n beebox-mobile --kubeconfig dev-k8s-config
}

