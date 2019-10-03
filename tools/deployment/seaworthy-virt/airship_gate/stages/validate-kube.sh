#!/bin/bash
# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
#
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
if [[ -n "$GATE_DEBUG" && "$GATE_DEBUG" = "1" ]]; then
  set -x
fi

set -e

# Define NUM_NODES to appropriate values to check this number of k8s nodes.

function upload_script() {
  source "$GATE_UTILS"
  BASENAME="$(basename "${BASH_SOURCE[0]}")"
  # Copies script to genesis VM
  rsync_cmd "${BASH_SOURCE[0]}" "$GENESIS_NAME:/root/airship/"
  set -o pipefail
  ssh_cmd_raw "$GENESIS_NAME" "KUBECONFIG=${KUBECONFIG} GATE_DEBUG=${GATE_DEBUG} NUM_NODES=$1 /root/airship/${BASENAME}" 2>&1 | tee -a "$LOG_FILE"
  set +o pipefail
}

function kubectl_retry() {
  cnt=0
  while true; do
    "$KUBECTL" "$@"
    ret=$?
    cnt=$((cnt+1))
    if [[ "$ret" -ne "0" ]]; then
      if [[ "$cnt" -lt "$MAX_TRIES" ]]; then
        sleep "$PAUSE"
      else
        return 1
      fi
    else
      break
    fi
  done
}

function check_kube_nodes() {
  try=0
  while true; do
    nodes_list="$(kubectl_retry get nodes --no-headers)" || true
    ret="$?"
    try="$((try+1))"
    if [ "$ret" -ne "0" ]; then
      if [[ "$try" -lt "$MAX_TRIES" ]]; then
        sleep "$PAUSE"
      else
        echo -e "Can't get nodes"
        return 1
      fi
    fi
    nodes_list="${nodes_list}\n"
    all_nodes=$(echo -en "$nodes_list" | wc -l)
    ok_nodes=$(echo -en "$nodes_list" | grep -c -v "NotReady" || true)
    if [[ "$all_nodes" == "$1" && "$ok_nodes" == "$1" ]]; then
      echo "Nodes: ${all_nodes}"
      break
    else
      echo "Error: not enough nodes(found ${all_nodes}, ready ${ok_nodes}, expected $1)"
      return 1
    fi
  done
}

function check_kube_components() {
  try=0
  while true; do
    res=$(kubectl_retry get cs -o jsonpath="{.items[*].conditions[?(@.type == \"Healthy\")].status}") || true
    try=$((try+1))

    if echo "$res" | grep -q False; then
      if [[ "$try" -lt "$MAX_TRIES" ]]; then
        sleep "$PAUSE"
      else
        echo "Error: kubernetes components are not working properly"
        kubectl_retry get cs
        exit 1
      fi
    else
      break
    fi
  done
}

if [[ -n "$GATE_UTILS" ]]; then
  upload_script "$NUM_NODES"
else
set +e
  KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin/kubeconfig.yaml}"
  KUBECTL="${KUBECTL:-/usr/local/bin/kubectl}"
  NUM_NODES="${NUM_NODES:-4}"
  PAUSE="${PAUSE:-1}"
  MAX_TRIES="${MAX_TRIES:-3}"
  if [[ ! -f "$KUBECTL" ]]; then
    echo "Error: ${KUBECTL} not found"
    exit 1
  fi
  check_kube_nodes "$NUM_NODES"
  nodes_status=$?
  check_kube_components
  components_status=$?
  if [[ "$nodes_status" -ne "0" || "$components_status" -ne "0" ]]; then
    echo "Kubernetes validation failed"
    exit 1
  else
    echo "Kubernetes validation succeeded"
  fi
fi
