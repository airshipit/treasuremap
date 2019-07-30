#!/bin/bash

# Copyright 2017 The Openstack-Helm Authors.
# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

set -xe

CURRENT_DIR="$(pwd)"
: "${INSTALL_PATH:="../"}"
: "${OSH_INFRA_COMMIT:="09366598b57a9ecd19fd34f5f844685bb6f2aabd"}"
: "${CLONE_ARMADA:=true}"
: "${CLONE_DECKHAND:=true}"
: "${CLONE_SHIPYARD:=true}"

cd ${INSTALL_PATH}

# Clone Airship projects
if [[ ${CLONE_ARMADA} = true ]] ; then
    git clone https://opendev.org/airship/armada.git
fi
if [[ ${CLONE_DECKHAND} = true ]] ; then
    git clone https://opendev.org/airship/deckhand.git
fi
if [[ ${CLONE_SHIPYARD} = true ]] ; then
    git clone https://opendev.org/airship/shipyard.git
fi

# Clone dependencies
git clone https://opendev.org/openstack/openstack-helm-infra.git

cd openstack-helm-infra
git checkout "${OSH_INFRA_COMMIT}"

cd "${CURRENT_DIR}"
