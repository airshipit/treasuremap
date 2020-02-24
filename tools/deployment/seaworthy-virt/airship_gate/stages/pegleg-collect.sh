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

mkdir -p "${DEFINITION_DEPOT}"
chmod 777 "${DEFINITION_DEPOT}"

render_pegleg_cli() {
    cli_string=("pegleg" "-v" "site")

    if [[ "${GERRIT_SSH_USER}" ]]
    then
      cli_string+=("-u" "${GERRIT_SSH_USER}")
    fi

    if [[ "${GERRIT_SSH_KEY}" ]]
    then
      cli_string+=("-k" "/workspace/${GERRIT_SSH_KEY}")
    fi

    primary_repo="$(config_pegleg_primary_repo)"

    if [[ -d "${REPO_ROOT}/${primary_repo}" ]]
    then
      cli_string+=("-r" "/workspace/${primary_repo}")
    else
      log "${primary_repo} not a valid primary repository"
      return 1
    fi

    aux_repos=($(config_pegleg_aux_repos))

    if [[ ${#aux_repos[@]} -gt 0 ]]
    then
        for r in ${aux_repos[*]}
        do
          cli_string+=("-e" "${r}=/workspace/${r}")
        done
    fi

    cli_string+=("collect" "-s" "/collect")

    cli_string+=("$(config_pegleg_sitename)")

    printf " %s " "${cli_string[@]}"
}

collect_design_docs() {
  # shellcheck disable=SC2091
  # shellcheck disable=SC2046
  docker run \
    --rm -t \
    --network host \
    -v "${HOME}/.ssh":/root/.ssh \
    -v "${REPO_ROOT}":/workspace \
    -v "${DEFINITION_DEPOT}":/collect \
    -e "PEGLEG_PASSPHRASE=$PEGLEG_PASSPHRASE" \
    -e "PEGLEG_SALT=$PEGLEG_SALT" \
    "${IMAGE_PEGLEG_CLI}" \
    $(render_pegleg_cli)
}

collect_initial_docs() {
  collect_design_docs
  log "Generating virtmgr key documents"
  gen_libvirt_key && install_libvirt_key
  collect_ssh_key
}

log "Collecting site definition to ${DEFINITION_DEPOT}"

if [[ "$1" != "update" ]];
then
  collect_initial_docs
else
  collect_design_docs
fi

# TODO(dc6350): as of 11/4/2019, Pegleg is running as root and
# producing files with permission 640, and Promenade tasks running
# as non-root users cannot read them. This line makes the files
# world-readable and can be removed when Pegleg is no longer
# running as root.
sudo chmod 644 "${DEFINITION_DEPOT}"*.yaml
