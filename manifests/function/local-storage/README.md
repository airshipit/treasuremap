# Local-Storage function

This function implements the local-volume-static-provisioner which
manages the lifecycle of the persistent volumes for pre-allocated
disks by detecting and creating PVs for each local disk on the host,
and cleaning up the disks when released. It does not support dynamic
provisioning.

Manual creation of PV on a particular host:

```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: example-local-pv
spec:
  capacity:
    storage: 5Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: local-storage
  local:
    path: /mnt/disks/ssd1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - my-node # node on which the local disk exists
```

Creating a simple PVC and attaching it to the pod in the Deployment:

```
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: example-local-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-storage
```

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: local-test-reader
spec:
  replicas: 1
  selector:
    matchLabels:
      app: local-test-reader
  template:
    metadata:
      labels:
        app: local-test-reader
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - name: reader
        image: k8s.gcr.io/busybox
        command:
        - "/bin/sh"
        args:
        - "-c"
        - "tail -f /usr/test-pod/test_file"
        volumeMounts:
        - name: local-vol
          mountPath: /usr/test-pod
      volumes:
      - name: local-vol
        persistentVolumeClaim:
          claimName: "example-local-claim"
```
