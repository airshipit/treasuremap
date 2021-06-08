#!/usr/bin/env bash

# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

set -xe

TMP_DIR=${TMP_DIR:-"$(dirname $(mktemp -u))"}
ANSIBLE_HOSTS=${ANSIBLE_HOSTS:-"${TMP_DIR}/ansible_hosts"}
PLAYBOOK_CONFIG=${PLAYBOOK_CONFIG:-"${TMP_DIR}/config.yaml"}
export AIRSHIPCTL_WS=${AIRSHIPCTL_WS:-$PWD}
export AIRSHIP_CONFIG_PHASE_REPO_URL=${AIRSHIP_CONFIG_PHASE_REPO_URL:-$PWD}

sudo -E --preserve-env=AIRSHIPCTL_WS ANSIBLE_STDOUT_CALLBACK=debug ansible-playbook -i "$ANSIBLE_HOSTS" \
	playbooks/airship-treasuremap-gate-runner.yaml \
	-e @"$PLAYBOOK_CONFIG" -v
