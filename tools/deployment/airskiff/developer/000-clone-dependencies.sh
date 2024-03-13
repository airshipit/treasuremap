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
: "${OSH_COMMIT:="2d9457e34ca4200ed631466bd87569b0214c92e7"}"
: "${OSH_INFRA_COMMIT:="cfff60ec10a6c386f38db79bb9f59a552c2b032f"}"
: "${CLONE_ARMADA:=true}"
: "${CLONE_ARMADA_GO:=true}"
: "${CLONE_ARMADA_OPERATOR:=true}"
: "${CLONE_DECKHAND:=true}"
: "${CLONE_SHIPYARD:=true}"
: "${CLONE_PORTHOLE:=true}"
: "${CLONE_PROMENADE:=true}"
: "${CLONE_MAAS:=true}"
: "${CLONE_OSH:=true}"

CLONE_ARMADA=$(echo "$CLONE_ARMADA" | tr '[:upper:]' '[:lower:]')
CLONE_ARMADA_GO=$(echo "$CLONE_ARMADA_GO" | tr '[:upper:]' '[:lower:]')
CLONE_ARMADA_OPERATOR=$(echo "$CLONE_ARMADA_OPERATOR" | tr '[:upper:]' '[:lower:]')
CLONE_DECKHAND=$(echo "$CLONE_DECKHAND" | tr '[:upper:]' '[:lower:]')
CLONE_SHIPYARD=$(echo "$CLONE_SHIPYARD" | tr '[:upper:]' '[:lower:]')
CLONE_PORTHOLE=$(echo "$CLONE_PORTHOLE" | tr '[:upper:]' '[:lower:]')
CLONE_PROMENADE=$(echo "$CLONE_PROMENADE" | tr '[:upper:]' '[:lower:]')
CLONE_MAAS=$(echo "$CLONE_MAAS" | tr '[:upper:]' '[:lower:]')
CLONE_OSH=$(echo "$CLONE_OSH" | tr '[:upper:]' '[:lower:]')

export CLONE_ARMADA
export CLONE_ARMADA_GO
export CLONE_ARMADA_OPERATOR
export CLONE_DECKHAND
export CLONE_SHIPYARD
export CLONE_PORTHOLE
export CLONE_PROMENADE
export CLONE_MAAS
export CLONE_OSH

cd "${INSTALL_PATH}"

# Clone Airship projects
if [[ ${CLONE_ARMADA} = true ]] ; then
    git clone https://opendev.org/airship/armada.git
fi
if [[ ${CLONE_ARMADA_GO} = true ]] ; then
    git clone https://opendev.org/airship/armada-go.git
fi
if [[ ${CLONE_ARMADA_OPERATOR} = true ]] ; then
    git clone https://opendev.org/airship/armada-operator.git
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

