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
# version. The anchor installs the binaries of this version on the nodes,
# upgrades the control plane (kubeadm upgrade node) and restarts kubelets.

set -ex

: "${KUBERNETES_UPGRADE_VERSION:="v1.37.0"}"

# shellcheck source=tools/deployment/aircat/common.sh
source ./tools/deployment/aircat/common.sh

kubectl version
kubectl get nodes -o wide

# The versions of the site are substituted to the kubeadm chart
./tools/deployment/aircat/set-document-data.py "${PL_SITE}" pegleg/SoftwareVersions/v1 software-versions \
  "kubernetes.version=${KUBERNETES_UPGRADE_VERSION}"
./tools/deployment/aircat/set-document-data.py "${PL_SITE}" armada/Chart/v1 "${KUBEADM_DOCUMENT}" \
  "values.kubelet.restart=true"
./tools/deployment/aircat/020-render-site.sh
test "$(kubeadm_data "${RENDERED}" values.cluster_config.kubernetesVersion)" == "${KUBERNETES_UPGRADE_VERSION}"
./tools/deployment/aircat/050-armada-apply.sh

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
