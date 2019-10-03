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

SCRIPT_DIR=$(realpath "$(dirname "${0}")")
WORKSPACE=$(realpath "${SCRIPT_DIR}/..")
GATE_UTILS=${WORKSPACE}/seaworthy-virt/airship_gate/lib/all.sh

GATE_COLOR=${GATE_COLOR:-1}

MANIFEST_ARG=${1:-"multinode_deploy"}
if [ -z "$GATE_MANIFEST" ]
then
  GATE_MANIFEST=${WORKSPACE}/seaworthy-virt/airship_gate/manifests/${MANIFEST_ARG}.json
fi

export GATE_COLOR
export GATE_MANIFEST
export GATE_UTILS
export WORKSPACE

source "${GATE_UTILS}"

sudo chmod -R 755 "${TEMP_DIR}"

STAGES_DIRS=()

while read -r libdir;do
  if [[ -d "$libdir" && -r "$libdir" && -x "$libdir" ]]; then
    STAGES_DIRS+=( "$libdir" )
  else
    log_warn "Could not find stage library $libdir, skipping..."
  fi
done <<< "$(jq -c ".configuration.stage_libraries // [] | .[]" < "$GATE_MANIFEST")"

STAGES_DIRS+=( "${WORKSPACE}/seaworthy-virt/airship_gate/stages" )

log_temp_dir
echo

STAGES=$(mktemp)
jq -cr '.stages | .[]' "${GATE_MANIFEST}" > "${STAGES}"

# NOTE(mark-burnett): It is necessary to use a non-stdin file descriptor for
# the read below, since we will be calling SSH, which will consume the
# remaining data on STDIN.
exec 3< "$STAGES"
while read -r -u 3 stage; do
    NAME=$(echo "${stage}" | jq -r .name)
    STAGE_SCRIPT="$(echo "${stage}" | jq -r .script)"
    STAGE_CMD=""
    for dir in "${STAGES_DIRS[@]}"; do
      if [ -x "${dir}/${STAGE_SCRIPT}" ]; then
        STAGE_CMD="${dir}/${STAGE_SCRIPT}"
        break;
      fi
    done
    if [ -z "$STAGE_CMD" ]; then
      log_error "$STAGE_SCRIPT not found!"
      exit 1
    fi
    log_stage_header "${NAME}"
    if echo "${stage}" | jq -r '.arguments | @sh' | xargs "${STAGE_CMD}" ; then
        log_stage_success
    else
        log_color_reset
        log_stage_error "${NAME}" "${LOG_FILE}"
        if echo "${stage}" | jq -e .on_error > /dev/null; then
            log_stage_diagnostic_header
            ON_ERROR=${WORKSPACE}/seaworthy-virt/airship_gate/on_error/$(echo "${stage}" | jq -r .on_error)
            set +e
            $ON_ERROR
        fi
        log_stage_error "${NAME}" "${TEMP_DIR}"
        exit 1
    fi
    log_stage_footer "${NAME}"
    echo
done

log_note "Site Definition YAMLs found in ${DEFINITION_DEPOT}"

echo
log_huge_success
