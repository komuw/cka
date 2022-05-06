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

## chapter 5.
# pods and containers.
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
# 5. into to init containers.


todo(){
    set -ex

    configmap_contents='
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-confMap
data:
  key1: val1
  key2:
    subKey:
      more: data
      evenmore: some more data
  key3: |
    You can also do
    multi-line
'

    secret_contents='
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
type: Opaque
data:
  user: base64.encode(john)
  password: base64.encode(mypass)
'

    pod_snippet='
...
spec:
  containers:
  - ...
    env:
    - name: HEY
      valueFrom:
        configMapKeyRef:
          name: my-confMap
          key: key1
    ...
    volumes:
    - name: secret-vol
      secret:
        secretName: my-secret
'

}

