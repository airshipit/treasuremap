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

# Kubernetes upgrade: deploy the kubeadm chart with a newer Kubernetes
# version and the anchor image with binaries of this version. The anchor
# syncs the binaries to the nodes, upgrades the control plane (kubeadm
# upgrade node) and restarts kubelets.

set -ex

: "${KUBERNETES_UPGRADE_VERSION:="v1.37.0"}"
# porthole kubeadm-utility image built with v1.37.0 binaries
: "${KUBERNETES_UPGRADE_ANCHOR_IMAGE:="quay.io/airshipit/porthole-kubeadm-utility:f059ba0f3e4cc9f33c0ce20c08f521519549e206-ubuntu_noble"}"

# shellcheck source=tools/deployment/airliner/common.sh
source ./tools/deployment/airliner/common.sh

kubectl version
kubectl get nodes -o wide

./tools/deployment/airliner/set-document-data.py "${RENDERED}" armada/Chart/v1 kubeadm \
  "values.cluster_config.kubernetesVersion=${KUBERNETES_UPGRADE_VERSION}" \
  "values.images.tags.anchor=${KUBERNETES_UPGRADE_ANCHOR_IMAGE}" \
  "values.kubelet.restart=true"
./tools/deployment/airliner/050-armada-apply.sh

kubectl version
kubectl get nodes -o wide
# Kubelets and the control plane run the new version
while read -r name _ role _; do
  test "$(kubectl get node "${name}" -o jsonpath='{.status.nodeInfo.kubeletVersion}')" == \
    "${KUBERNETES_UPGRADE_VERSION}"
  [[ "${role}" == "control-plane" ]] || continue
  for component in kube-apiserver kube-controller-manager kube-scheduler; do
    kubectl -n kube-system wait --for=condition=Ready pod "${component}-${name}" --timeout=300s
    image=$(kubectl -n kube-system get pod "${component}-${name}" -o jsonpath='{.spec.containers[0].image}')
    [[ "${image}" == *":${KUBERNETES_UPGRADE_VERSION}" ]]
  done
done <<< "${NODES}"
test "$(kubectl version -o json | python3 -c 'import json, sys; print(json.load(sys.stdin)["serverVersion"]["gitVersion"])')" == \
  "${KUBERNETES_UPGRADE_VERSION}"

# Addons are upgraded by the addon phase of kubeadm upgrade node on the last
# upgraded control plane node: kube-proxy of the new version, CoreDNS of the
# version kubeadm recommends for it
kubectl -n kube-system rollout status daemonset/kube-proxy --timeout=600s
image=$(kubectl -n kube-system get daemonset kube-proxy -o jsonpath='{.spec.template.spec.containers[0].image}')
[[ "${image}" == *":${KUBERNETES_UPGRADE_VERSION}" ]]
kubectl -n kube-system rollout status deployment/coredns --timeout=600s
kubectl -n kube-system get deployment coredns -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
