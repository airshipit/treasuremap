#!/usr/bin/env bash
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

# NOTE(mark-burnett): Keep trying to collect info even if there's an error
set +e

KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin/kubeconfig.yaml}"
source "${GATE_UTILS}"

ERROR_DIR="${TEMP_DIR}/errors"
VIA=n0
mkdir -p "${ERROR_DIR}"

log "Gathering info from failed genesis server (n0) in ${ERROR_DIR}"

log "Gathering docker info for exitted containers"
mkdir -p "${ERROR_DIR}/docker"
docker_ps "${VIA}" | tee "${ERROR_DIR}/docker/ps"
docker_info "${VIA}" | tee "${ERROR_DIR}/docker/info"

for container_id in $(docker_exited_containers "${VIA}"); do
    docker_inspect "${VIA}" "${container_id}" | tee "${ERROR_DIR}/docker/${container_id}"
    echo "=== Begin logs ===" | tee -a "${ERROR_DIR}/docker/${container_id}"
    docker_logs "${VIA}" "${container_id}" | tee -a "${ERROR_DIR}/docker/${container_id}"
done

log "Gathering kubectl output"
mkdir -p "${ERROR_DIR}/kube"
kubectl_cmd "${VIA}" describe nodes n0 | tee "${ERROR_DIR}/kube/n0"
kubectl_cmd "${VIA}" get --all-namespaces -o wide pod | tee "${ERROR_DIR}/kube/pods"
