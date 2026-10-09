#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Day 0: build the Kubernetes cluster with the kubeadm chart.
#
# The values of the kubeadm chart document of the rendered site are used to
# render the chart with `helm template`, the bootstrap script is extracted
# from the kubeadm-service-bootstrap Secret and executed on the node.
#
# The node is the site node which IP is configured on this machine. Its
# bootstrap phase is defined by the site:
#   init          - the first control plane node: kubeadm init
#   control-plane - the rest of control plane nodes: kubeadm join
#   worker        - kubelet joins the cluster with the delivered credentials,
#                   kubeadm is not needed
# Usage: 040-kubeadm-bootstrap.sh [<phase>]
# If the phase is given, the script does nothing on nodes of other phases:
# this allows to run it on all nodes of a multinode site phase by phase.

set -ex

: "${INSTALL_PATH:="../"}"
: "${PL_SITE:="airliner"}"
: "${RENDERED:="${PL_SITE}.yaml"}"
: "${KUBEADM_CHART:="${INSTALL_PATH}/promenade/charts/kubeadm"}"
: "${HELM:="helm"}"
: "${NODE_IFACE:="kubeadm0"}"
PHASE="${1:-}"

if [[ ! -d "${KUBEADM_CHART}" ]]; then
  git clone https://opendev.org/airship/promenade.git "${INSTALL_PATH}/promenade"
fi

GET_DATA="./tools/deployment/airliner/get-document-data.py ${RENDERED} armada/Chart/v1 kubeadm"

# Node name and IP are defined by the site, certificates are issued for them
LOCAL_NODE=$(./tools/deployment/airliner/get-site-nodes.py "${RENDERED}" local)
read -r NODE_NAME NODE_IP _ NODE_PHASE <<< "${LOCAL_NODE}"
if [[ -n "${PHASE}" && "${PHASE}" != "${NODE_PHASE}" ]]; then
  echo "${NODE_NAME} is bootstrapped in the ${NODE_PHASE} phase, skipping"
  exit 0
fi

NODE_ROLE=master
case "${NODE_PHASE}" in
  init)
    : "${KUBEADM_ARGS:="init --config /etc/kubernetes/kubeadm/init_config.yaml"}"
    ;;
  control-plane)
    : "${KUBEADM_ARGS:="join --config /etc/kubernetes/kubeadm/join_config.yaml"}"
    ;;
  worker)
    NODE_ROLE=worker
    # kubelet registers the node itself using the delivered kubelet.conf
    : "${KUBEADM_ARGS:="version"}"
    ;;
esac

print_diagnostics() {
  set +e
  sudo systemctl status kubelet --no-pager
  sudo journalctl -u kubelet --no-pager | tail -n 100
  sudo crictl ps -a
  for component in etcd kube-apiserver kube-controller-manager kube-scheduler; do
    for id in $(sudo crictl ps -a -q --name "${component}"); do
      echo "=== ${component} ${id}"
      sudo crictl logs --tail 50 "${id}"
    done
  done
}

# Bring up the node IP defined by the site (single node site: on a dummy
# interface; on multinode sites it must be configured beforehand)
if ! ip -4 -o addr show | grep -q " inet ${NODE_IP}/"; then
  sudo ip link add "${NODE_IFACE}" type dummy
  sudo ip addr add "${NODE_IP}/32" dev "${NODE_IFACE}"
  sudo ip link set "${NODE_IFACE}" up
fi
while read -r name ip _; do
  if ! grep -qE "^${ip}[[:space:]]+${name}\b" /etc/hosts; then
    echo "${ip} ${name}" | sudo tee -a /etc/hosts
  fi
done < <(./tools/deployment/airliner/get-site-nodes.py "${RENDERED}" all)

# Values and the bootstrap script contain private keys: keep them private
# and never copy them to the job artifacts.
WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT
chmod 0700 "${WORK_DIR}"

${GET_DATA} values > "${WORK_DIR}/values.yaml"

HELM_EXTRA_ARGS=()
# The containerd config v3 (chart default) is supported by containerd 2.x only
CONTAINERD_MAJOR=$(containerd --version | grep -oE ' v?[0-9]+\.[0-9]+' | head -n1 | tr -d ' v' | cut -d. -f1)
if [[ "${CONTAINERD_MAJOR}" -lt 2 ]]; then
  HELM_EXTRA_ARGS+=(--set containerd.version=v2)
fi

${HELM} template kubeadm "${KUBEADM_CHART}" \
  -f "${WORK_DIR}/values.yaml" \
  --set manifests.secret_bootstrap=true \
  --set bootstrap.string_data=true \
  --set bootstrap.nodename="${NODE_NAME}" \
  "${HELM_EXTRA_ARGS[@]}" > "${WORK_DIR}/kubeadm.yaml"

python3 - "${WORK_DIR}/kubeadm.yaml" "${WORK_DIR}/bootstrap.sh" << 'EOF'
import sys

import yaml

with open(sys.argv[1]) as f:
    for doc in yaml.safe_load_all(f):
        if doc and doc.get('kind') == 'Secret' and \
                doc['metadata']['name'] == 'kubeadm-service-bootstrap':
            with open(sys.argv[2], 'w') as out:
                out.write(doc['stringData']['script'])
            break
    else:
        sys.exit('Secret kubeadm-service-bootstrap is not found')
EOF

# shellcheck disable=SC2086
if ! sudo env NODE_NAME="${NODE_NAME}" NODE_IP="${NODE_IP}" NODE_ROLE="${NODE_ROLE}" \
    bash "${WORK_DIR}/bootstrap.sh" -- ${KUBEADM_ARGS}; then
  print_diagnostics
  exit 1
fi
