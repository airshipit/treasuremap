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

export IMAGE_DIR=${IMAGE_DIR:-"/srv/images"}
export SERVE_PORT=${SERVE_PORT:-"8099"}
export AIRSHIPCTL_WS=${AIRSHIPCTL_WS:-$PWD}
export TMP_DIR=${TMP_DIR:-"$(dirname $(mktemp -u))"}

ANSIBLE_CFG=${ANSIBLE_CFG:-"${HOME}/.ansible.cfg"}
ANSIBLE_HOSTS=${ANSIBLE_HOSTS:-"${TMP_DIR}/ansible_hosts"}
PLAYBOOK_CONFIG=${PLAYBOOK_CONFIG:-"${TMP_DIR}/config.yaml"}

mkdir -p "$TMP_DIR"
envsubst <"${AIRSHIPCTL_WS}/tools/gate/config_template.yaml" > "$PLAYBOOK_CONFIG"

# use new version of ansible, Ubuntu has old one
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt -y install software-properties-common python3-pip curl wget ca-certificates
sudo DEBIAN_FRONTEND=noninteractive apt -y --no-install-recommends install docker.io make

PACKAGES="ansible netaddr"
if [[ -z "${http_proxy}" ]]; then
  sudo pip3 install $PACKAGES
else
  sudo pip3 --proxy "${http_proxy}" install $PACKAGES
fi

echo "primary ansible_host=localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3" > "$ANSIBLE_HOSTS"
printf "[defaults]\nroles_path = %s/roles\n" "$AIRSHIPCTL_WS" > "$ANSIBLE_CFG"
