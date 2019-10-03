#!/usr/bin/env bash
# Copyright 2019 AT&T Intellectual Property.  All other rights reserved.
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

set -ex

source "${GATE_UTILS}"

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin/kubeconfig.yaml}"

ssh_cmd "${GENESIS_NAME}" apt-get install -y jq

# Copies script and virtmgr private key to genesis VM
ssh_cmd "${GENESIS_NAME}" mkdir -p /root/airship
rsync_cmd "${REPO_ROOT}/tools/deployment/seaworthy-virt/airship_gate/bin/debug-report-lite.sh" "${GENESIS_NAME}:/root/airship/"

set -o pipefail
ssh_cmd_raw "${GENESIS_NAME}" "KUBECONFIG=${KUBECONFIG} /root/airship/debug-report-lite.sh" 2>&1 | tee -a "${LOG_FILE}"
set +o pipefail

rsync_cmd "${GENESIS_NAME}:/root/debug-${GENESIS_NAME}.tgz" .

