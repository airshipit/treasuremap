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
