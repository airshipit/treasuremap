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

set -ex

source "${GATE_UTILS}"

cd "${TEMP_DIR}"

# Omit the cert_yaml bundle
OMIT_CERTS=0
# Omit the gate_yaml bundle
OMIT_GATE=0

while getopts "og" opt; do
    case "${opt}" in
        o)
            OMIT_CERTS=1
            ;;
        g)
            OMIT_GATE=1
            ;;
        *)
            echo "Unknown option"
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

check_configdocs_result(){
  RESULT=$1
  ERROR_CNT=$(echo "${RESULT}" | grep -oE 'Errors: [0-9]+')

  if [[ "${ERROR_CNT}" != "Errors: 0" ]]
  then
    log "Shipyard create configdocs did not pass validation."
    echo "${RESULT}" >> "${LOG_FILE}"
    return 1
  fi
}

CREATE_CONFIGDOCS_RETRIES=${CREATE_CONFIGDOCS_RETRIES:-5}

create_configdocs_design() {
  for ((i=0; i<${CREATE_CONFIGDOCS_RETRIES}; i++)); do
    if check_configdocs_result "$(shipyard_cmd create configdocs "$@")"; then
      log "Create confidocs succeeded."
      return 0
    fi
    log "Failed on atemp $i, retrying ..."
    sleep 30
  done
  log "Create configdocs failed after $i retries."
  return 1
}

# Copy site design to genesis node
ssh_cmd "${BUILD_NAME}" mkdir -p "${BUILD_WORK_DIR}/site"
rsync_cmd "${DEFINITION_DEPOT}"/*.yaml "${BUILD_NAME}:${BUILD_WORK_DIR}/site/"
create_configdocs_design design --directory="${BUILD_WORK_DIR}/site" --replace

# Skip certs/gate if already part of site manifests
if [[ -n "${USE_EXISTING_SECRETS}" ]]
then
  OMIT_CERTS=1
  OMIT_GATE=1
fi

if [[ "${OMIT_CERTS}" == "0" ]]
then
  ssh_cmd "${BUILD_NAME}" mkdir -p "${BUILD_WORK_DIR}/certs"
  rsync_cmd "${CERT_DEPOT}"/*.yaml "${BUILD_NAME}:${BUILD_WORK_DIR}/certs/"
  create_configdocs_design certs --directory="${BUILD_WORK_DIR}/certs" --append
fi

if [[ "${OMIT_GATE}" == "0" ]]
then
  ssh_cmd "${BUILD_NAME}" mkdir -p "${BUILD_WORK_DIR}/gate"
  rsync_cmd "${GATE_DEPOT}"/*.yaml "${BUILD_NAME}:${BUILD_WORK_DIR}/gate/"
  create_configdocs_design gate --directory="${BUILD_WORK_DIR}/gate" --append
fi

check_configdocs_result "$(shipyard_cmd commit configdocs)"
