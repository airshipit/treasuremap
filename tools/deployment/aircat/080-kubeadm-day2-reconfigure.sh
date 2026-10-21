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

# Day 2 reconfiguration: change the cluster configuration in the kubeadm
# chart values, deploy it with Armada and check that the anchor applies it.
#
# Usage: 080-kubeadm-day2-reconfigure.sh eviction|no-eviction
#   eviction    - the kubelet configuration is changed too: the anchor drains
#                 every node and restarts kubelet (kubelet.restart=true),
#                 workloads are evicted
#   no-eviction - kubelet.restart=false: the anchor applies the control plane
#                 configuration (kubeadm upgrade node) only, workloads keep
#                 running

set -ex

MODE="${1:?Usage: $0 eviction|no-eviction}"
: "${SMOKE_TEST_IMAGE:="quay.io/airshipit/network-multitool"}"

# shellcheck source=tools/deployment/aircat/common.sh
source ./tools/deployment/aircat/common.sh

case "${MODE}" in
  eviction)
    NODE_PORT_RANGE=30000-32700
    KUBELET_RESTART=true
    CONTAINER_LOG_MAX_FILES=$(($(kubeadm_data "${RENDERED}" values.kubelet.containerLogMaxFiles) + 1))
    ;;
  no-eviction)
    NODE_PORT_RANGE=30000-32600
    KUBELET_RESTART=false
    CONTAINER_LOG_MAX_FILES=$(kubeadm_data "${RENDERED}" values.kubelet.containerLogMaxFiles)
    ;;
  *)
    echo "Unknown mode ${MODE}" >&2
    exit 1
    ;;
esac

# Canary workload: a pod on every node
NODE_COUNT=$(wc -l <<< "${NODES}")
kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: day2-canary
  namespace: default
spec:
  replicas: ${NODE_COUNT}
  selector:
    matchLabels:
      app: day2-canary
  template:
    metadata:
      labels:
        app: day2-canary
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: day2-canary
      containers:
        - name: canary
          image: ${SMOKE_TEST_IMAGE}
EOF
kubectl rollout status deployment/day2-canary --timeout=300s
canary_pods() {
  kubectl get pods -l app=day2-canary -o jsonpath='{range .items[*]}{.metadata.uid}{"\n"}{end}' | sort
}
CANARY_PODS=$(canary_pods)

# The configuration is changed in the documents of the site (the network of
# the cluster is substituted from the common addresses), the site is rendered
# again: the next steps deploy it with their own changes.
./tools/deployment/aircat/set-document-data.py "${PL_SITE}" pegleg/CommonAddresses/v1 common-addresses \
  "kubernetes.service_node_port_range=${NODE_PORT_RANGE}"
./tools/deployment/aircat/set-document-data.py "${PL_SITE}" armada/Chart/v1 "${KUBEADM_DOCUMENT}" \
  "values.kubelet.restart=${KUBELET_RESTART}" \
  "values.kubelet.containerLogMaxFiles=${CONTAINER_LOG_MAX_FILES}"
./tools/deployment/aircat/020-render-site.sh
test "$(kubeadm_data "${RENDERED}" values.network.kubernetes.service_node_port_range)" == "${NODE_PORT_RANGE}"
./tools/deployment/aircat/050-armada-apply.sh

# The control plane runs with the new configuration
kubectl -n kube-system rollout status daemonset/kube-proxy --timeout=300s
while read -r name _ role _; do
  [[ "${role}" == "control-plane" ]] || continue
  kubectl -n kube-system wait --for=condition=Ready pod \
    -l component=kube-apiserver --field-selector "spec.nodeName=${name}" --timeout=300s
  # one argument per line: the flag can be the last one of the command
  kubectl -n kube-system get pod "kube-apiserver-${name}" \
    -o jsonpath='{range .spec.containers[0].command[*]}{@}{"\n"}{end}' | \
    grep -Fx -- "--service-node-port-range=${NODE_PORT_RANGE}"
done <<< "${NODES}"
kubectl get --raw /livez

# Kubelets run with the configuration of the chart
while read -r name _; do
  test "$(kubectl get --raw "/api/v1/nodes/${name}/proxy/configz" | \
    python3 -c 'import json, sys; print(json.load(sys.stdin)["kubeletconfig"]["containerLogMaxFiles"])')" \
    == "${CONTAINER_LOG_MAX_FILES}"
done <<< "${NODES}"

kubectl rollout status deployment/day2-canary --timeout=300s
kubectl get pods -l app=day2-canary -o wide
if [[ "${MODE}" == "eviction" ]]; then
  # every node was drained: none of the canary pods survived
  test -z "$(comm -12 <(echo "${CANARY_PODS}") <(canary_pods))"
else
  test "$(canary_pods)" == "${CANARY_PODS}"
fi
kubectl delete deployment day2-canary --wait
