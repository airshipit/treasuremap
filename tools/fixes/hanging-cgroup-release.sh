#!/bin/bash
set -ex

CLUSTER_DNS=${CLUSTER_DNS:-10.96.0.10}

KUBECTL_IMAGE=${KUBECTL_IMAGE:-gcr.io/google-containers/hyperkube-amd64:v1.11.6}
UBUNTU_IMAGE=${UBUNTU_IMAGE:-docker.io/ubuntu:16.04}

cat > /tmp/hanging-cgroup-release.yaml << 'EOF'
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: hanging-cgroup-release
  namespace: kube-system
  labels:
    hotfix: 'true'
data:
  singleshot.sh: |+
    #!/bin/bash
    set -ex

    while [ 1 ];
      do
        cgroup_count() {
          echo "Current cgroup count: $(find /sys/fs/cgroup/*/system.slice -name tasks | wc -l)"
        }

        DATE=$(date)
        echo "$(cgroup_count)"
        echo   # Stop systemd mount unit that isn't actually mounted
        echo "Stopping Kubernetes systemd mount units that are not mounted to the system."
        systemctl list-units --state=running| \
          sed -rn '/Kubernetes.transient.mount/s,(run-\S+).+(/var/lib/kubelet/pods/.+),\1 \2,p' | \
          xargs -r -l1 sh -c 'test -d $2 || echo $1' -- | \
          xargs -r -tl1 systemctl stop |& wc -l
        echo "$(cgroup_count)"

        sleep 3600

      done;
EOF
cat >> /tmp/hanging-cgroup-release.yaml << EOF
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: hanging-cgroup-release
  namespace: kube-system
spec:
  template:
    metadata:
      labels:
        name: hanging-cgroup-release
    spec:
      hostNetwork: true
      hostPID: true
      nodeSelector:
        ucp-control-plane: enabled
      containers:
        - resources:
            requests:
              cpu: 0.1
          securityContext:
            privileged: true
          image: ${UBUNTU_IMAGE}
          name: hanging-cgroup-release
          command: ["/bin/bash", "-cx"]
          args:
            - >
              cp -p /tmp/singleshot.sh /host/tmp;
              nsenter -t 1 -m -u -n -i /tmp/singleshot.sh;
          volumeMounts:
            - name: host
              mountPath: /host
            - name: hanging-cgroup-release
              subPath: singleshot.sh
              mountPath: /tmp/singleshot.sh
      volumes:
        - name: host
          hostPath:
            path: /
        - name: hanging-cgroup-release
          configMap:
            name: hanging-cgroup-release
            defaultMode: 0555
EOF

docker run --rm -i \
        --net host \
        -v /tmp:/work \
        -v /etc/kubernetes/admin:/etc/kubernetes/admin \
        -e KUBECONFIG=/etc/kubernetes/admin/kubeconfig.yaml \
        ${KUBECTL_IMAGE} \
            /kubectl apply -f /work/hanging-cgroup-release.yaml

