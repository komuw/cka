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

## chapter 5. Pods and Containers.

# 1. managing app config: dynamic vars that are passed to apps at runtime.
#      - configMaps.
#      - secrets.
#      - env vars.              You can pass configMap & Secrets to containers as env vars.
#      - configuration volumes. You can pass configMap & Secrets to containers as config volumes.
#                               They'll appear in containers as files mounted in them.
#                               Each toplevel key in config data will appear as a file containing all keys below that key.
# 2. managing container resources(cpu, mem, etc)
# 3. monitoring container health with probes.
# 4. building self-healing pods with restart policies.
# 5. intro to init containers.


app_config(){
    set -ex

    configmap_contents='
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-confmap
data:
  key1: val1
  key2: |
    subKey:
      more: data
      evenmore: some more data
  key3: |
    You can also do
    multi-line
'
    insert_if_not_exists "my-confmap" "${configmap_contents}" /tmp/my_configmap.yml
    kubectl apply -f /tmp/my_configmap.yml
    kubectl get configmap

    secret_contents='
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
type: Opaque
data:
  username: username-placeholder
  password: password-placeholder
'
    insert_if_not_exists "my-secret" "${secret_contents}" /tmp/my_secret.yml
    username=$(echo "John" | base64)
    password=$(echo "heyPasswd" | base64)
    sed -i.bak "s/username-placeholder/$username/" /tmp/my_secret.yml
    sed -i.bak "s/password-placeholder/$password/" /tmp/my_secret.yml
    kubectl apply -f /tmp/my_secret.yml
    kubectl get secret

    my_pod_env_vars_contents="
apiVersion: v1
kind: Pod
metadata:
  name: my-pod-env-vars
spec:
  containers:
  - name: busybox
    image: busybox
    command: [
        'sh',
        '-c', 
        '
        set -x;
        echo;
        echo configmap: \$CONFIMAP_ENV_VAR secret: \$SECRET_ENV_VAR;
        echo;
        sleep 2;
        '
        ]
    env:
    - name: CONFIMAP_ENV_VAR
      valueFrom:
        configMapKeyRef:
          name: my-confmap # should match the metadata.name of the /tmp/my_configmap.yml
          key: key1
    - name: SECRET_ENV_VAR
      valueFrom:
        secretKeyRef:
          name: my-secret # should match the metadata.name of the /tmp/my_secret.yml
          key: password
"
    insert_if_not_exists "my-pod-env-vars" "${my_pod_env_vars_contents}" /tmp/my_pod_env_vars.yml
    kubectl apply -f /tmp/my_pod_env_vars.yml
    kubectl describe pod my-pod-env-vars | tail
    kubectl logs my-pod-env-vars
    LOGS_RESP=$(kubectl logs --tail=100 my-pod-env-vars)
    if grep -q "val1" <<< $LOGS_RESP; then
        # exists
        echo -n ""
    else
        printf "\n\t required string not found in log output \n"
        exit 77;
    fi

    if grep -q "heyPasswd" <<< $LOGS_RESP; then
        # exists
        echo -n ""
    else
        printf "\n\t required string not found in log output \n"
        exit 77;
    fi


    my_pod_volume_contents="
apiVersion: v1
kind: Pod
metadata:
  name: my-pod-volume
spec:
  containers:
  - name: busybox
    image: busybox
    # there should be a file in /tmp/alas/hey-conf for each key inside the configMap.
    # there should be a file in /tmp/alas/hey-secret for each key inside the Secret.
    command: [
        'sh',
        '-c', 
        '
        set -x;
        ls -lsha /tmp/alas/hey-conf;
        ls -lsha /tmp/alas/hey-secret;
        sleep 2;
        cat /tmp/alas/hey-conf/key1;
        cat /tmp/alas/hey-conf/key3;
        sleep 2;
        cat /tmp/alas/hey-secret/username;
        cat /tmp/alas/hey-secret/password;
        '
        ]
    volumeMounts:
    - name: configmap-volume
      mountPath: /tmp/alas/hey-conf
    - name: secret-volume
      mountPath: /tmp/alas/hey-secret
  volumes:
  - name: configmap-volume
    configMap:
      name: my-confmap  # should match the metadata.name of the /tmp/my_configmap.yml
  - name: secret-volume
    secret:
      secretName: my-secret  # should match the metadata.name of the /tmp/my_secret.yml
"
    insert_if_not_exists "my-pod-volume" "${my_pod_volume_contents}" /tmp/my_pod_volume.yml
    kubectl apply -f /tmp/my_pod_volume.yml
    kubectl describe pod my-pod-volume | tail
    kubectl logs --tail=100 my-pod-volume

    LOGS_RESP=$(kubectl logs --tail=100 my-pod-volume)
    if grep -q "val1" <<< $LOGS_RESP; then
        # exists
        echo -n ""
    else
        printf "\n\t required string not found in log output \n"
        exit 77;
    fi

    if grep -q "heyPasswd" <<< $LOGS_RESP; then
        # exists
        echo -n ""
    else
        printf "\n\t required string not found in log output \n"
        exit 77;
    fi
}

# Managing container resources.
# - resource requests: Allow u to define amt of resources(cpu/mem/etc) that container will use.
#                      Scheduler will use those to avoid scheduling pods on nodes that don't have available resources.
#                      Containers are allowed to use more resources than requested. Resource request only affects scheduling.
# - resource limits: Limit amt of resources a container can use. Container runtime enforces this limits(eg by terminating container.)
#
# (a) Use CPU requests.
# (b) Do NOT use cpu limits.
# (c) Use memory requests.
# (d) Use memory limits. Set, memory_request == memory_limit.
# https://home.robusta.dev/blog/stop-using-cpu-limits
manage_container_resources(){
    pod_contents="
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  containers:
  - name: busybox
    image: radial/busyboxplus:curl
    resources:
      requests:
        memory: 120M
        cpu: 80m
      limits:
        memory: 250M
        cpu: 150m
"
}

# Monitoring Container health with probes.
# k8s needs to be able to determine the status of your app. This means actively monitoring container health.
# - startup probes:   Determine whether container is in healthy state at startup.
# - readiness probes: Determine when container is ready to start accepting requests.
# - liveness probes:  Determine whether container is in healthy state. We can customize this to suit our app.
health_probing(){
    pod_contents="
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  containers:
  - name: busybox
    image: radial/busyboxplus:curl
    livenessProbe:
      exec: # others are; `httpGet`, `tcpSocket`, `grpc`, etc.
        command: ["echo", "hello"]
      initialDelaySeconds: 5
      periodSeconds: 5
    startupProbe:
      httpGet:
        path: /
        port: 80
      failureThreshold: 30
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /
        port: 80
      failureThreshold: 5
      periodSeconds: 5
"
}

# Building self-healing pods with restart policies.
# They control what happens when pods fail. 
# - Always:     The default. Containers are restarted, after they stop, even if they stopped with a success exit code.
# - OnFailure:  Restarts only if process exits with error code or if determined to be unhealthy via liveness probe.
# - Never:      Self explanatory.
restart_policies(){
    pod_contents="
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  restartPolicy: OnFailure
  containers:
  - name: busybox
    image: radial/busyboxplus:curl
"
}

# Creating multi-container pods.
# This is a pod with more than one container.
# The containers share resources such as network & storage.
# It is a good idea to keep containers in separate pods UNLESS they need to share resources.
# Example usecase: You have a container that logs to a file on disk.
#                  So you add another container(sidecar) that reads that logfile(since they share resources) & prints it to console(so that the logs appear in container logs.)
multi_container_pod(){
    pod_contents="
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  containers:
  - name: logToDisk
    image: busybox
    command: ['sh', '-c', 'while true; do echo logs-data > /output/out.log; sleep 5; done']
    volumeMounts:
    - name: sharedVol
      mountPath: /output
  - name: logCollector
    image: busybox
    command: ['sh', '-c', 'tail -f /input/out.log']
    volumeMounts:
    - name: sharedVol
      mountPath: /input
  volumes:
  - name: sharedVol
    emptyDir: {}
"
}

# Intro to init containers.
# Containers that run ONCE during the startup process of a pod. They can be multiple of them.
# Example usecase:
#   - perform sensiive startup steps securely outside of app containers.
#   - cause pod to wait for another k8s resource to be created.
#   - populate data into a shared volume.
add_init_container(){
    pod_contents="
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  containers:
  - name: busybox
    image: busybox
  initContainers:
  - name: delay
    image: busybox
    command: ['sleep', '25']
"
}
