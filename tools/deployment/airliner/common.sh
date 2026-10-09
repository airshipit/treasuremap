# shellcheck shell=bash
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

# Helpers of the day 2 scripts, sourced from the repository root.

: "${PL_SITE:="airliner"}"
: "${RENDERED:="${PL_SITE}.yaml"}"
: "${NAMESPACE:="kube-system"}"
# Armada release of the kubeadm chart: <release_prefix>-<release>
: "${RELEASE:="airship-kubeadm"}"

NODES=$(./tools/deployment/airliner/get-site-nodes.py "${RENDERED}" all)
ANCHOR_PODS="release_group=${RELEASE},application=kubernetes"

# Data of the kubeadm chart document: kubeadm_data <documents> [<path>]
kubeadm_data() {
  ./tools/deployment/airliner/get-document-data.py "$1" armada/Chart/v1 kubeadm "${2:-}"
}

# Run a command on a host of the site: chroot to the host root filesystem
# in the anchor pod of the node (requires the hostfs patch of the anchor
# daemonsets, see the kubeadm chart document of the site).
host_exec() {
  local host="$1" pod
  shift
  # a running pod which isn't being deleted: during a rollout the node has
  # the old (terminating) and the new anchor pods
  pod=$(kubectl get pods -n "${NAMESPACE}" -l application=kubernetes,hostfs=true \
    --field-selector "spec.nodeName=${host},status.phase=Running" \
    -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.deletionTimestamp}{"\n"}{end}' | \
    awk '$2 == "" { print $1; exit }')
  if [[ -z "${pod}" ]]; then
    echo "No hostfs anchor pod on ${host}" >&2
    return 1
  fi
  kubectl exec -n "${NAMESPACE}" "${pod}" -- chroot /host bash -c "$*" 2>&1 | sed -e "s/^/[${host}] /"
  return "${PIPESTATUS[0]}"
}

# Wait until a resource exists (e.g. created asynchronously by an operator)
# Usage: wait_exists <timeout> <kubectl get arguments>...
wait_exists() {
  local end=$(($(date +%s) + $1))
  shift
  until kubectl get "$@" > /dev/null 2>&1; do
    if [[ "$(date +%s)" -gt "${end}" ]]; then
      echo "Timed out waiting for $*" >&2
      kubectl get "$@"
      return 1
    fi
    sleep 10
  done
}

# Anchor pods which are not replaced yet keep logs of the previous steps:
# show the logs written since the step (the sourcing script) has started.
ANCHOR_LOGS_SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

anchor_logs() {
  kubectl -n "${NAMESPACE}" logs -l "${ANCHOR_PODS}" --tail="${1:-100}" \
    --since-time="${ANCHOR_LOGS_SINCE}" --prefix --max-log-requests=10 || true
}

# The anchor annotates nodes with checksums of the configuration it has
# applied: wait until they match the configuration of the documents and the
# anchor has finished with every node.
# Usage: wait_anchor_applied <documents>
wait_anchor_applied() {
  local documents="$1" timeout="${ANCHOR_TIMEOUT:-3600}"
  local expected_kubeadm expected_kubelet="" expected_version end settled=0

  fs_sha256() {
    kubectl -n "${NAMESPACE}" get secret kubeadm-service-fs-allnodes \
      -o jsonpath="{.data.${1//./\\.}}" | base64 -d | sha256sum | cut -d ' ' -f 1
  }
  expected_kubeadm=$(fs_sha256 kubeadm_ClusterConfiguration)
  # The kubelet configuration (and binaries) are applied by the anchor only
  # if it is allowed to restart kubelet (kubelet.restart, true by default).
  if ! kubeadm_data "${documents}" values.kubelet.restart 2> /dev/null | grep -qx false; then
    expected_kubelet=$(fs_sha256 kubelet_config.yaml)
    expected_version=$(kubeadm_data "${documents}" values.cluster_config.kubernetesVersion)
  fi

  anchor_applied() {
    local name role
    while read -r name _ role _; do
      # the kubeadm configuration is applied on control plane nodes only
      if [[ "${role}" == "control-plane" && "$(kubectl get node "${name}" \
        -o jsonpath='{.metadata.annotations.last-applied-kubeadm-cfg-sha256}')" != "${expected_kubeadm}" ]]; then
        return 1
      fi
      if [[ -n "${expected_kubelet}" ]]; then
        if [[ "$(kubectl get node "${name}" \
          -o jsonpath='{.metadata.annotations.last-applied-kubelet-cfg-sha256}')" != "${expected_kubelet}" ]]; then
          return 1
        fi
        # an upgrade doesn't change the kubelet configuration: kubelet is
        # restarted with the binaries of the desired version
        if [[ "$(kubectl get node "${name}" \
          -o jsonpath='{.status.nodeInfo.kubeletVersion}')" != "${expected_version}" ]]; then
          return 1
        fi
      fi
      # the anchor drains the node to restart kubelet
      if [[ -n "$(kubectl get node "${name}" -o jsonpath='{.spec.unschedulable}')" ]]; then
        return 1
      fi
    done <<< "${NODES}"
    # anchor pods are ready when they have applied the configuration
    ! kubectl -n "${NAMESPACE}" get pods -l "${ANCHOR_PODS}" \
      -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | \
      grep -qvx True
  }

  kubectl -n "${NAMESPACE}" rollout status daemonset/kubeadm-service-masters-anchor --timeout=1800s
  kubectl -n "${NAMESPACE}" rollout status daemonset/kubeadm-service-workers-anchor --timeout=1800s

  # The anchor applies the configuration node by node: the state must hold
  # for a while, not only between two nodes.
  end=$(($(date +%s) + timeout))
  while [[ "${settled}" -lt 2 ]]; do
    if anchor_applied; then
      settled=$((settled + 1))
    else
      settled=0
      if [[ "$(date +%s)" -gt "${end}" ]]; then
        echo "Timed out waiting for the anchor to apply the configuration" >&2
        kubectl -n "${NAMESPACE}" get pods -o wide
        kubectl get nodes -o wide
        anchor_logs 200
        return 1
      fi
      # progress of the anchor: node state, kubelet restart job, recent logs
      kubectl -n "${NAMESPACE}" get pods -l "${ANCHOR_PODS}" -o wide || true
      kubectl get nodes -o wide || true
      kubectl -n "${NAMESPACE}" get jobs,pods -l kubelet-restart -o wide 2> /dev/null || true
      kubectl -n "${NAMESPACE}" describe pods -l kubelet-restart 2> /dev/null | \
        grep -E "^Name:|^Node:|State:|Reason:|Message:|Warning|Failed" || true
      anchor_logs
    fi
    [[ "${settled}" -ge 2 ]] || sleep 30
  done
  kubectl get nodes -o wide
  anchor_logs 50
}

# The cluster must be healthy: all nodes ready and schedulable, all pods of
# kube-system ready.
check_cluster_healthy() {
  local name
  while read -r name _; do
    kubectl wait --for=condition=Ready node "${name}" --timeout=300s
    test -z "$(kubectl get node "${name}" -o jsonpath='{.spec.unschedulable}')"
  done <<< "${NODES}"
  kubectl -n kube-system wait --for=condition=Ready pods --all --timeout=600s \
    --field-selector=status.phase!=Succeeded
  kubectl get pods -A -o wide
}
