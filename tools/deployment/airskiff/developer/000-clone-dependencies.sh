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

: "${INSTALL_PATH:="../"}"
: "${OSH_COMMIT:="75c30f43db44218e7842611e880fd8d7a30fa79c"}"
: "${OSH_INFRA_COMMIT:="db3537e56b182a54e7f6931ce57e2a190714019b"}"
: "${CLONE_ARMADA:=true}"
: "${CLONE_DECKHAND:=true}"
: "${CLONE_SHIPYARD:=true}"
: "${CLONE_PORTHOLE:=true}"
: "${CLONE_PROMENADE:=true}"
: "${CLONE_MAAS:=true}"
: "${CLONE_OSH:=true}"

cd "${INSTALL_PATH}"

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
if [[ ${CLONE_PROMENADE} = true ]] ; then
    git clone https://opendev.org/airship/promenade.git
fi


# Clone dependencies
if [[ ${CLONE_MAAS} = true ]] ; then
    git clone "https://review.opendev.org/airship/maas.git"
fi
if [[ ${CLONE_PORTHOLE} = true ]] ; then
    git clone "https://review.opendev.org/airship/porthole.git"
fi
if [[ ${CLONE_OSH} = true ]] ; then
    git clone https://opendev.org/openstack/openstack-helm.git
    pushd openstack-helm
    git checkout "${OSH_COMMIT}"
    popd
fi


git clone https://opendev.org/openstack/openstack-helm-infra.git
pushd openstack-helm-infra
git checkout "${OSH_INFRA_COMMIT}"
popd

