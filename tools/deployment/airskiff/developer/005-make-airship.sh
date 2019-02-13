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

# NOTE(drewwalters96): Build Airship components locally, for use as a
#   as a development environment.

CURRENT_DIR="$(pwd)"
: "${INSTALL_PATH:="../"}"

cd ${INSTALL_PATH}
git clone https://git.openstack.org/openstack/airship-armada.git
cd airship-armada && make images

cd ${INSTALL_PATH}
git clone https://git.openstack.org/openstack/airship-deckhand.git
cd airship-deckhand && make

cd ${INSTALL_PATH}
git clone https://git.openstack.org/openstack/airship-shipyard.git
cd airship-shipyard && make

cd ${INSTALL_PATH}
git clone https://git.openstack.org/openstack/airship-pegleg.git

# Clone dependencies
git clone https://git.openstack.org/openstack/openstack-helm-infra.git

cd openstack-helm-infra
git checkout ef3adc4d0e5d26e74590d2f78400f7e1d800dbcb

cd "${CURRENT_DIR}"
