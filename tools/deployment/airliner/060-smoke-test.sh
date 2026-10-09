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

# Check that the cluster built by the kubeadm chart is functional and uses
# the PKI generated for the site.

set -ex

: "${PL_SITE:="airliner"}"
: "${RENDERED:="${PL_SITE}.yaml"}"
: "${SMOKE_TEST_IMAGE:="quay.io/airshipit/network-multitool"}"
# ICMP payload of the pod to pod check, sent with fragmentation prohibited:
# 1372 + 28 bytes of headers fits the smallest pod MTU used by the gates
: "${SMOKE_TEST_PING_SIZE:="1372"}"

GET_DATA="./tools/deployment/airliner/get-document-data.py ${RENDERED} armada/Chart/v1 kubeadm"
NODES=$(./tools/deployment/airliner/get-site-nodes.py "${RENDERED}" all)

kubectl get nodes -o wide
# All nodes of the site are registered with the site IPs and ready
while read -r name ip _; do
  # one address per line: a node can have several internal IPs
  kubectl get node "${name}" \
    -o jsonpath='{range .status.addresses[?(@.type=="InternalIP")]}{.address}{"\n"}{end}' | \
    grep -qFx -- "${ip}"
  kubectl wait --for=condition=Ready node "${name}" --timeout=300s
done <<< "${NODES}"

kubectl -n kube-system rollout status daemonset/kube-proxy --timeout=300s
kubectl -n calico-system rollout status daemonset/calico-node --timeout=300s
kubectl -n kube-system rollout status deployment/coredns --timeout=300s
kubectl -n kube-system wait --for=condition=Ready pods --all --timeout=300s \
  --field-selector=status.phase!=Succeeded
kubectl get pods -A -o wide

# Components must serve certificates delivered by the chart
check_cert() {
  local endpoint="$1" cert_path="$2"
  local expected actual
  expected=$(${GET_DATA} "${cert_path}" | openssl x509 -noout -fingerprint -sha256)
  actual=$(openssl s_client -connect "${endpoint}" < /dev/null 2> /dev/null | \
    openssl x509 -noout -fingerprint -sha256)
  if [[ "${expected}" != "${actual}" ]]; then
    echo "Certificate served by ${endpoint} doesn't match ${cert_path}" >&2
    return 1
  fi
}
CONTROL_PLANE_ENDPOINT=$(${GET_DATA} values.kubeconfig.controlPlaneEndpoint)
# through the VIP (haproxy) if the site has one
check_cert "${CONTROL_PLANE_ENDPOINT}" values.certs.apiserver.crt
while read -r name ip role _; do
  if [[ "${role}" == "control-plane" ]]; then
    check_cert "${ip}:6443" values.certs.apiserver.crt
    check_cert "${ip}:2379" "values.certs.nodes.${name}.etcd_server.crt"
  fi
  check_cert "${ip}:10250" "values.certs.nodes.${name}.kubelet.crt"
done <<< "${NODES}"

# Workloads: scheduling, pod network, cluster DNS, apiserver -> kubelet.
# The test pod runs on the last node of the site (a worker on multinode
# sites), its peer on the first one: pod to pod traffic crosses the nodes.
run_pod() {
  local pod="$1" node="$2"
  kubectl delete pod "${pod}" --ignore-not-found --wait
  kubectl run "${pod}" --image="${SMOKE_TEST_IMAGE}" --restart=Never \
    --overrides="{\"apiVersion\": \"v1\", \"spec\": {\"nodeSelector\": {\"kubernetes.io/hostname\": \"${node}\"}}}"
}
TEST_NODE=$(tail -n 1 <<< "${NODES}" | cut -d ' ' -f 1)
PEER_NODE=$(head -n 1 <<< "${NODES}" | cut -d ' ' -f 1)
run_pod smoke-test "${TEST_NODE}"
run_pod smoke-test-peer "${PEER_NODE}"
kubectl wait --for=condition=Ready pod smoke-test smoke-test-peer --timeout=300s
kubectl get pod smoke-test smoke-test-peer -o wide
PEER_IP=$(kubectl get pod smoke-test-peer -o jsonpath='{.status.podIP}')
kubectl exec smoke-test -- ping -c 3 -W 5 -M "do" -s "${SMOKE_TEST_PING_SIZE}" "${PEER_IP}"
kubectl exec smoke-test -- nslookup kubernetes.default.svc.cluster.local
kubectl exec smoke-test -- curl -skf https://kubernetes.default.svc.cluster.local/livez
kubectl logs smoke-test | tail -n 5
kubectl delete pod smoke-test smoke-test-peer --wait
