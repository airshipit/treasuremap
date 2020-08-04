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

set -e

source "${GATE_UTILS}"

# Copies script and virtmgr private key to genesis VM
# waits for the genesis node to complete reboot, if it is rebooted during
# genesis setup stage.
GENESIS_RSYNC_RETRIES=${GENESIS_RSYNC_RETRIES:-10}
retries=0
while ! rsync_cmd "${SCRIPT_DEPOT}/genesis.sh" "${GENESIS_NAME}:/root/airship/"; do
  if [[ "${retries}" < "${GENESIS_RSYNC_RETRIES}" ]]; then
    log "Genesis node is not reachable yet. Retrying in 30 seconds."
    retries=$((retries+1))
    sleep 30
    continue
  fi
  log_error "Genesis was not reachable after max retries: "${GENESIS_RSYNC_RETRIES}"."
  exit 1
done

set -o pipefail
ssh_cmd_raw "${GENESIS_NAME}" "PROMENADE_ENCRYPTION_KEY=${PROMENADE_ENCRYPTION_KEY} /root/airship/genesis.sh" 2>&1 | tee -a "${LOG_FILE}"
set +o pipefail

if ! ssh_cmd "${GENESIS_NAME}" docker images | tail -n +2 | grep -v registry:5000 ; then
    log_warn "Using some non-cached docker images.  This will slow testing."
    ssh_cmd "${GENESIS_NAME}" docker images | tail -n +2 | grep -v registry:5000 | tee -a "${LOG_FILE}"
fi
