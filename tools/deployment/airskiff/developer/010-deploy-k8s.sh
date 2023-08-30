#!/bin/bash

# Copyright 2019, AT&T Intellectual Property
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

set -xe

CURRENT_DIR="$(pwd)"
: "${OSH_INFRA_PATH:="../openstack-helm-infra"}"

# Configure proxy settings if $PROXY is set
if [ -n "${PROXY}" ]; then
  . tools/deployment/airskiff/common/setup-proxy.sh
fi

# Deploy K8s with Minikube
: "${HELM_VERSION:="v3.11.1"}"
: "${KUBE_VERSION:="v1.27.3"}"
: "${MINIKUBE_VERSION:="v1.30.1"}"
: "${CRICTL_VERSION:="v1.27.0"}"
: "${CALICO_VERSION:="v3.26.1"}"
: "${CORE_DNS_VERSION:="v1.10.1"}"
: "${YQ_VERSION:="v4.6.0"}"
: "${KUBE_DNS_IP="10.96.0.10"}"

export DEBCONF_NONINTERACTIVE_SEEN=true
export DEBIAN_FRONTEND=noninteractive

sudo swapoff -a

sudo mkdir -p /opt/ext_vol
sudo mkdir -p /opt/ext_vol/docker
sudo mkdir -p /opt/ext_vol/containerd

sudo mkdir -p /opt/ext_vol/run_containerd
sudo rsync -a /run/containerd/ /opt/ext_vol/run_containerd/
sudo mount --bind /run/containerd /opt/ext_vol/run_containerd
sudo systemctl restart containerd
mount
sudo fdisk --list
df -h

echo "DefaultLimitMEMLOCK=16384" | sudo tee -a /etc/systemd/system.conf
sudo systemctl daemon-reexec

function configure_resolvconf {
  # here with systemd-resolved disabled, we'll have 2 separate resolv.conf
  # 1 - /run/systemd/resolve/resolv.conf automatically passed by minikube
  # to coredns via kubelet.resolv-conf extra param
  # 2 - /etc/resolv.conf - to be used for resolution on host

  kube_dns_ip="${KUBE_DNS_IP}"
  # keep all nameservers from both resolv.conf excluding local addresses
  old_ns=$(cat /run/systemd/resolve/resolv.conf /etc/resolv.conf /run/systemd/resolve/resolv.conf | sort | uniq)

  if [[ -f "/run/systemd/resolve/resolv.conf" ]]; then
    sudo cp --remove-destination /run/systemd/resolve/resolv.conf /etc/resolv.conf
  fi

  sudo systemctl disable systemd-resolved
  sudo systemctl stop systemd-resolved

  # Remove localhost as a nameserver, since we stopped systemd-resolved
  sudo sed -i  "/^nameserver\s\+127.*/d" /etc/resolv.conf

  # Insert kube DNS as first nameserver instead of entirely overwriting /etc/resolv.conf
  grep -q "nameserver ${kube_dns_ip}" /etc/resolv.conf || sudo sed -i -e "1inameserver ${kube_dns_ip}" /etc/resolv.conf

  local dns_servers
  if [ -z "${HTTP_PROXY}" ]; then
    dns_servers="nameserver 8.8.8.8\nnameserver 8.8.4.4\n"
  else
    dns_servers="${old_ns}"
  fi

  grep -q "${dns_servers}" /etc/resolv.conf || echo -e ${dns_servers} | sudo tee -a /etc/resolv.conf

  grep -q "${dns_servers}" /run/systemd/resolve/resolv.conf || echo -e ${dns_servers} | sudo tee /run/systemd/resolve/resolv.conf

  local search_options='search svc.cluster.local cluster.local'
  grep -q "${search_options}" /etc/resolv.conf ||  echo "${search_options}" | sudo tee -a /etc/resolv.conf

  grep -q "${search_options}" /run/systemd/resolve/resolv.conf ||  echo "${search_options}" | sudo tee -a /run/systemd/resolve/resolv.conf

  local dns_options='options ndots:5 timeout:1 attempts:1'
  grep -q "${dns_options}" /etc/resolv.conf ||  echo ${dns_options} | sudo tee -a /etc/resolv.conf

  grep -q "${dns_options}" /run/systemd/resolve/resolv.conf || echo ${dns_options} | sudo tee -a /run/systemd/resolve/resolv.conf
}

# NOTE: Clean Up hosts file
sudo sed -i '/^127.0.0.1/c\127.0.0.1 localhost localhost.localdomain localhost4localhost4.localdomain4' /etc/hosts
sudo sed -i '/^::1/c\::1 localhost6 localhost6.localdomain6' /etc/hosts
if ! grep -qF "127.0.1.1" /etc/hosts; then
  echo "127.0.1.1 $(hostname)" | sudo tee -a /etc/hosts
fi
configure_resolvconf

# shellcheck disable=SC1091
. /etc/os-release

# uninstalling conflicting packages
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt remove $pkg || true; done

# NOTE: Add docker repo
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88
sudo add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) \
  stable"



if [ -n "${HTTP_PROXY}" ]; then
  sudo mkdir -p /etc/systemd/system/docker.service.d
  cat <<EOF | sudo -E tee /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=${HTTP_PROXY}"
Environment="HTTPS_PROXY=${HTTPS_PROXY}"
Environment="NO_PROXY=${NO_PROXY}"
EOF
fi

# Install required packages for K8s on host
wget -q -O- 'https://download.ceph.com/keys/release.asc' | sudo apt-key add -
RELEASE_NAME=$(grep 'CODENAME' /etc/lsb-release | awk -F= '{print $2}')
sudo add-apt-repository "deb https://download.ceph.com/debian-octopus/
${RELEASE_NAME} main"

sudo -E apt-get update
sudo -E apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin \
  socat \
  jq \
  util-linux \
  bridge-utils \
  iptables \
  conntrack \
  libffi-dev \
  ipvsadm \
  make \
  bc \
  git-review \
  notary \
  ceph-common \
  rbd-nbd \
  nfs-common \
  ethtool

sudo -E tee /etc/modprobe.d/rbd.conf << EOF
install rbd /bin/true
EOF



cat << EOF | sudo tee /etc/containerd/config.toml
version = 2

# persistent data location
root = "/opt/ext_vol/containerd"

[debug]
  level = "warn"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"

  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
EOF
sudo systemctl restart containerd

# NOTE: Configure docker
docker_resolv="/etc/resolv.conf"
docker_dns_list="$(awk '/^nameserver/ { printf "%s%s",sep,"\"" $NF "\""; sep=", "} END{print ""}' "${docker_resolv}")"

sudo -E mkdir -p /etc/docker
sudo -E tee /etc/docker/daemon.json <<EOF
{
  "data-root": "/opt/ext_vol/docker",
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "dns": [${docker_dns_list}]
}
EOF

sudo systemctl restart docker


# Prepare tmpfs for etcd when running on CI
# CI VMs can have slow I/O causing issues for etcd
# Only do this on CI (when user is zuul), so that local development can have a kubernetes
# environment that will persist on reboot since etcd data will stay intact
if [ "$USER" = "zuul" ]; then
  sudo mkdir -p /var/lib/minikube/etcd
  sudo mount -t tmpfs -o size=512m tmpfs /var/lib/minikube/etcd
fi

# Install YQ
wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64.tar.gz -O - | tar xz && sudo mv yq_linux_amd64 /usr/local/bin/yq

# Install minikube and kubectl
URL="https://storage.googleapis.com"
sudo -E curl -sSLo /usr/local/bin/minikube "${URL}"/minikube/releases/"${MINIKUBE_VERSION}"/minikube-linux-amd64
sudo -E curl -sSLo /usr/local/bin/kubectl "${URL}"/kubernetes-release/release/"${KUBE_VERSION}"/bin/linux/amd64/kubectl
sudo -E chmod +x /usr/local/bin/minikube
sudo -E chmod +x /usr/local/bin/kubectl

# Install cri-tools
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz
sudo tar zxvf "crictl-${CRICTL_VERSION}-linux-amd64.tar.g"z -C /usr/local/bin
rm -f "crictl-${CRICTL_VERSION}-linux-amd64.tar.gz"


#Forwarding IPv4 and letting iptables see bridged traffic
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system
sudo sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

lsmod | grep br_netfilter
lsmod | grep overlay




# Install CNI Plugins
# from https://github.com/containernetworking/plugins.git
CNI_TEMP_DIR=$(mktemp -d)
pushd "${CNI_TEMP_DIR}"
git clone https://github.com/containernetworking/plugins.git
pushd plugins
git checkout v0.8.5
popd
docker run --rm  -v ./plugins:/usr/local/src -w /usr/local/src golang:1.13.8  bash -c './build_linux.sh'
sudo mkdir -p /opt/cni
sudo cp -a plugins/bin /opt/cni/
popd
if [ -d "${CNI_TEMP_DIR}" ]; then
  sudo rm -rf mkdir "${CNI_TEMP_DIR}"
fi
sudo systemctl restart containerd
sudo systemctl restart docker

# Install Helm
TMP_DIR=$(mktemp -d)
sudo -E bash -c \
  "curl -sSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz | tar -zxv --strip-components=1 -C ${TMP_DIR}"
sudo -E mv "${TMP_DIR}"/helm /usr/local/bin/helm
rm -rf "${TMP_DIR}"

# NOTE: Deploy kubernetes using minikube. A CNI that supports network policy is
# required for validation; use calico for simplicity.
sudo -E minikube config set kubernetes-version "${KUBE_VERSION}"
sudo -E minikube config set vm-driver none

export CHANGE_MINIKUBE_NONE_USER=true
export MINIKUBE_IN_STYLE=false

set +e
api_server_status="$(set +e; sudo -E minikube status --format='{{.APIServer}}')"
set -e
echo "Minikube api server status is \"${api_server_status}\""
if [[ "${api_server_status}" != "Running" ]]; then
  sudo -E minikube start \
    --docker-env HTTP_PROXY="${HTTP_PROXY}" \
    --docker-env HTTPS_PROXY="${HTTPS_PROXY}" \
    --docker-env NO_PROXY="${NO_PROXY},10.96.0.0/12" \
    --network-plugin=cni \
    --cni=calico \
    --wait=apiserver,system_pods \
    --apiserver-names="$(hostname -f)" \
    --extra-config=controller-manager.allocate-node-cidrs=true \
    --extra-config=controller-manager.cluster-cidr=192.168.0.0/16 \
    --extra-config=kube-proxy.mode=ipvs \
    --extra-config=apiserver.service-node-port-range=1-65535 \
    --extra-config=kubelet.cgroup-driver=systemd \
    --extra-config=kubelet.resolv-conf=/run/systemd/resolve/resolv.conf \
    --embed-certs \
    --container-runtime=containerd
fi

sudo -E systemctl enable --now kubelet

sudo -E minikube addons list

curl -LSs https://raw.githubusercontent.com/projectcalico/calico/"${CALICO_VERSION}"/manifests/calico.yaml -o /tmp/calico.yaml

sed -i -e 's#docker.io/calico/#quay.io/calico/#g' /tmp/calico.yaml

# Download images needed for calico before applying manifests, so that `kubectl wait` timeout
# for `k8s-app=kube-dns` isn't reached by slow download speeds
awk '/image:/ { print $2 }' /tmp/calico.yaml | xargs -I{} sudo docker pull {}

kubectl apply -f /tmp/calico.yaml

# Note: Patch calico daemonset to enable Prometheus metrics and annotations
tee /tmp/calico-node.yaml << EOF
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9091"
    spec:
      containers:
        - name: calico-node
          env:
            - name: FELIX_PROMETHEUSMETRICSENABLED
              value: "true"
            - name: FELIX_PROMETHEUSMETRICSPORT
              value: "9091"
            - name: FELIX_IGNORELOOSERPF
              value: "true"
EOF
kubectl -n kube-system patch daemonset calico-node --patch "$(cat /tmp/calico-node.yaml)"

kubectl get pod -A
kubectl -n kube-system get pod -l k8s-app=kube-dns

# NOTE: Wait for dns to be running.
END=$(($(date +%s) + 240))
until kubectl --namespace=kube-system \
        get pods -l k8s-app=kube-dns --no-headers -o name | grep -q "^pod/coredns"; do
  NOW=$(date +%s)
  [ "${NOW}" -gt "${END}" ] && exit 1
  echo "still waiting for dns"
  sleep 10
done
kubectl -n kube-system wait --timeout=240s --for=condition=Ready pods -l k8s-app=kube-dns

# Validate DNS now to save a lot of headaches later
sleep 5
if ! dig svc.cluster.local ${KUBE_DNS_IP} | grep ^cluster.local. >& /dev/null; then
  echo k8s DNS Failure. Are you sure you disabled systemd-resolved before running this script?
  exit 1
fi

# Remove stable repo, if present, to improve build time
helm repo remove stable || true

# Add labels to the core namespaces & nodes
kubectl label --overwrite namespace default name=default
kubectl label --overwrite namespace kube-system name=kube-system
kubectl label --overwrite namespace kube-public name=kube-public
kubectl label --overwrite nodes --all openstack-control-plane=enabled
kubectl label --overwrite nodes --all openstack-compute-node=enabled
kubectl label --overwrite nodes --all openvswitch=enabled
kubectl label --overwrite nodes --all linuxbridge=enabled
kubectl label --overwrite nodes --all ceph-mon=enabled
kubectl label --overwrite nodes --all ceph-osd=enabled
kubectl label --overwrite nodes --all ceph-mds=enabled
kubectl label --overwrite nodes --all ceph-rgw=enabled
kubectl label --overwrite nodes --all ceph-mgr=enabled

for NAMESPACE in ceph openstack osh-infra; do
tee /tmp/${NAMESPACE}-ns.yaml << EOF
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: ${NAMESPACE}
    name: ${NAMESPACE}
  name: ${NAMESPACE}
EOF

kubectl apply -f /tmp/${NAMESPACE}-ns.yaml
done

# Update CoreDNS and enable recursive queries
PATCH=$(mktemp)
HOSTIP=$(hostname -I| awk '{print $1}')
kubectl get configmap coredns -n kube-system -o json | jq -r "{data: .data}"  | sed 's/ready\\n/header \{\\n        response set ra\\n    \}\\n    ready\\n/g' > "${PATCH}"
sed -i "s/127.0.0.1 host.minikube.internal/127.0.0.1 host.minikube.internal\\\n       $HOSTIP control-plane.minikube.internal/" "${PATCH}"
kubectl patch configmap coredns -n kube-system --patch-file "${PATCH}"
kubectl set image deployment coredns -n kube-system "coredns=registry.k8s.io/coredns/coredns:${CORE_DNS_VERSION}"
rm -f "${PATCH}"
kubectl rollout restart -n kube-system deployment/coredns
kubectl rollout status --watch --timeout=300s -n kube-system deployment/coredns
sleep 10
host -v control-plane.minikube.internal

kubectl label nodes --all --overwrite ucp-control-plane=enabled


kubectl run multitool --image=praqma/network-multitool
kubectl wait --for=condition=ready pod multitool --timeout=300s
kubectl exec -it multitool -- nslookup control-plane.minikube.internal
kubectl exec -it multitool -- ping -c 4 8.8.8.8
kubectl exec -it multitool -- nslookup google.com


# # Add user to Docker group
# # NOTE: This requires re-authentication. Restart your shell.
# sudo adduser "$(whoami)" docker
# sudo su - "$USER" -c bash <<'END_SCRIPT'
# if echo $(groups) | grep -qv 'docker'; then
#     echo "You need to logout to apply group permissions"
#     echo "Please logout and login"
# fi
# END_SCRIPT

# # clean up /etc/resolv.conf, if it includes a localhost dns address
# sudo sed -i.bkp '/^nameserver.*127.0.0.1/d
#                  w /dev/stdout' /etc/resolv.conf

cd "${CURRENT_DIR}"
df -h