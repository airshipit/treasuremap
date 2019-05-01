#!/bin/bash
set -ex

CLUSTER_DNS=${CLUSTER_DNS:-10.96.0.10}

KUBECTL_IMAGE=${KUBECTL_IMAGE:-gcr.io/google-containers/hyperkube-amd64:v1.11.6}
UBUNTU_IMAGE=${UBUNTU_IMAGE:-docker.io/ubuntu:16.04}

cat > /tmp/rbd-roomba-scanner.yaml << 'EOF'
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: rbd-roomba-scanner
  namespace: ceph
  labels:
    hotfix: 'true'
data:
  singleshot.sh: |+
    #!/bin/bash
    set -ex

    while [ 1 ];

      do

        # don't put it in /tmp where it can be p0wned (???)
        lsblk | awk '/^rbd/ {if($7==""){print $0}}' | awk '{ printf "/dev/%s\n",$1 }' > /var/run/rbd_list

        # wait a while, so we don't catch rbd devices the kubelet is working on mounting
        sleep 60

        # finally, examine rbd devices again and if any were seen previously (60s ago) we will
        # forcefully unmount them if they have no fs mounts
        DATE=$(date)
        for rbd in `lsblk | awk '/^rbd/ {if($7==""){print $0}}' | awk '{ printf "/dev/%s\n",$1 }'`; do
          if grep -q $rbd /var/run/rbd_list; then
            echo "[${DATE}] Unmapping stale RBD $rbd"
            /usr/bin/rbd unmap -o force $rbd
            # NOTE(supamatt): rbd unmap -o force will only succeed if there are NO pending I/O
          else
            echo "[${DATE}] Skipping RBD $rbd as it hasn't been stale for at least 60 seconds"
          fi
        done
        rm -rf /var/run/rbd_list

      done;
EOF
cat >> /tmp/rbd-roomba-scanner.yaml << EOF
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: rbd-roomba-scanner
  namespace: ceph
spec:
  template:
    metadata:
      labels:
        name: rbd-roomba-scanner
    spec:
      hostNetwork: true
      hostPID: true
      nodeSelector:
        openstack-control-plane: enabled
      containers:
        - resources:
            requests:
              cpu: 0.1
          securityContext:
            privileged: true
          image: ${UBUNTU_IMAGE}
          name: rbd-roomba-scanner
          command: ["/bin/bash", "-cx"]
          args:
            - >
              cp -p /tmp/singleshot.sh /host/tmp;
              nsenter -t 1 -m -u -n -i /tmp/singleshot.sh;
          volumeMounts:
            - name: host
              mountPath: /host
            - name: rbd-roomba-scanner
              subPath: singleshot.sh
              mountPath: /tmp/singleshot.sh
      volumes:
        - name: host
          hostPath:
            path: /
        - name: rbd-roomba-scanner
          configMap:
            name: rbd-roomba-scanner
            defaultMode: 0555
EOF

docker run --rm -i \
        --net host \
        -v /tmp:/work \
        -v /etc/kubernetes/admin:/etc/kubernetes/admin \
        -e KUBECONFIG=/etc/kubernetes/admin/kubeconfig.yaml \
        ${KUBECTL_IMAGE} \
            /kubectl apply -f /work/rbd-roomba-scanner.yaml
