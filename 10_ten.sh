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

## chapter 10: Storage.

# - Container File systems: It is ephemeral. Files on th CFS exist only as long as the container exists.
# - Volumes:                They allow us to store data outside the CFS while allowing container access the data at runtime.
# - Persistent volumes:     They allow you to treat storage as an abstract resource & consume it using your pods.
# - Volume types:           Both volumes and persistent volumes have a type. The type determines how storage is actually handled. The common(there are more) types are;
#                           (a) hostPath. Stores data in a specific directory in the k8s node.
#                           (b) emptyDir. Stores data in a dynamically created directory in the k8s node. The dir & data is deleted when the pod ceases to exist.
#                                         It is useful when sharing data between containers. See `multi_container_pod` in `five.sh`
#                           Volume types support different storage methods, eg;
#                           (a) NFS
#                           (b) Cloud storage(AWS, Azure, etc)
#                           (c) ConfigMaps
#                           (d) Secrets
#                           (e) Simple directory on the k8s node.
# Container -> PersistentVolumeClaim -> PersistentVolume -> StorageClass -> External-storage

volumes_and_mounts(){
    contents="
apiVersion: v1
kind: Pod
metadata:
  name: my-vol-pod
spec:
  containers:
  - name: busybox
    image: busybox
    volumeMounts:
    - name: my-volume
      mountPath: /output # directory inside the container where volume is at.
  volumes:
  - name: my-volume
    hostPath:
      path: /data        # directory in the k8s Node where volume is at.
"
}

# Persistent volumes:    They allow you to treat storage as an abstract resource & consume it using your pods.
#                        It uses a set of attributes to describe the underlying storage resources which will be used to store data.
# PersistentVolumeClaim: It represents a user's request for storage resources.
#                        When created, it will look for a PV that is able to meet the request criteria. If found, it will be `bound` to that PV.
# StorageClass:          They allow k8s administrators to specify the types of storage services that they offer on their platform.
#                        For example, admins could create an SC called `slow` to describe low perfomance storage, & `fast` describing a high perf storage.
#                        Users could then choose between them based on their app needs.
# The `allowVolumeExpansion` property of an SC determines whether or not the SC supports resizing of volumes after they have been created.
# The `persistentVolumeReclaimPolicy` property of a PV determines how the storage resources can be resused when the PV's associated PVC are deleted.
#   - Retain: keeps all data. An admin would have to manually clean-up the data in preparation for reuse.
#   - Delete: deletes underlying strage resource automatically. This ONLY works for cloud storage resources.
#   - Recycle: deletes data automatically, allowing PV to be reused.
#

my_pv(){
    contents="
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: localdisk
provisioner: kubernetes.io/no-provisioner # This stores data directly on the host disk.
allowVolumeExpansion: false

# This PVC will look for a PV that meets criteria; has same storageClassName, supports same accessModes, has >= requested storage amt.
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  storageClassName: localdisk
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi  # If you want to resize a PVC, just change this. Note that the underlying StorageClass should `allowVolumeExpansion` for this to happen.

apiVersion: v1
kind: PersistentVolume
metadata:
  name: my-pv
spec:
  storageClassName: localdisk
  persistentVolumeReclaimPolicy: Recycle
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /var/output

apiVersion: v1
kind: Pod
metadata:
  name: my-pv-pod
spec:
  containers:
  - name: busybox
    image: busybox
    volumeMounts:
    - name: pv-storage
      mountPath: /output # directory inside the container where volume is at.
  volumes:
  - name: pv-storage
    persistentVolumeClaim:
      claimName: my-pvc # Should match the PVC metadata.name
"
}
