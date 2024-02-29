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
: "${ARTIFACTS_PATH:="../artifacts"}"
: "${HTK_COMMIT:="cfff60ec10a6c386f38db79bb9f59a552c2b032f"}"
: "${MAKE_CHARTS_OPENSTACK_HELM:=true}"
: "${MAKE_CHARTS_OSH_INFRA:=true}"
: "${MAKE_CHARTS_ARMADA:=true}"
: "${MAKE_CHARTS_DECKHAND:=true}"
: "${MAKE_CHARTS_SHIPYARD:=true}"
: "${MAKE_CHARTS_MAAS:=true}"
: "${MAKE_CHARTS_PORTHOLE:=true}"
: "${MAKE_CHARTS_PROMENADE:=true}"


MAKE_CHARTS_OPENSTACK_HELM=$(echo "$MAKE_CHARTS_OPENSTACK_HELM" | tr '[:upper:]' '[:lower:]')
MAKE_CHARTS_OSH_INFRA=$(echo "$MAKE_CHARTS_OSH_INFRA" | tr '[:upper:]' '[:lower:]')
MAKE_CHARTS_ARMADA=$(echo "$MAKE_CHARTS_ARMADA" | tr '[:upper:]' '[:lower:]')
MAKE_CHARTS_DECKHAND=$(echo "$MAKE_CHARTS_DECKHAND" | tr '[:upper:]' '[:lower:]')
MAKE_CHARTS_SHIPYARD=$(echo "$MAKE_CHARTS_SHIPYARD" | tr '[:upper:]' '[:lower:]')
MAKE_CHARTS_MAAS=$(echo "$MAKE_CHARTS_MAAS" | tr '[:upper:]' '[:lower:]')
MAKE_CHARTS_PORTHOLE=$(echo "$MAKE_CHARTS_PORTHOLE" | tr '[:upper:]' '[:lower:]')
MAKE_CHARTS_PROMENADE=$(echo "$MAKE_CHARTS_PROMENADE" | tr '[:upper:]' '[:lower:]')
export MAKE_CHARTS_OPENSTACK_HELM
export MAKE_CHARTS_OSH_INFRA
export MAKE_CHARTS_ARMADA
export MAKE_CHARTS_DECKHAND
export MAKE_CHARTS_SHIPYARD
export MAKE_CHARTS_MAAS
export MAKE_CHARTS_PORTHOLE
export MAKE_CHARTS_PROMENADE

mkdir -p "${ARTIFACTS_PATH}"

cd "${INSTALL_PATH}"

# Make charts in Airship and OSH-INFRA projects
if [[ ${MAKE_CHARTS_ARMADA} = true ]] ; then
    pushd armada
    make charts
    cd charts
    for i in $(find  . -maxdepth 1  -name "*.tgz"  -print | sed -e 's/\-[0-9.]*\.tgz//'| cut -d / -f 2 | sort)
    do
        find . -name "$i-[0-9.]*.tgz" -print -exec cp -av {} "../../artifacts/$i.tgz" \;
    done
    popd
fi
if [[ ${MAKE_CHARTS_DECKHAND} = true ]] ; then
    pushd deckhand
    make charts
    for i in $(find  . -maxdepth 1  -name "*.tgz"  -print | sed -e 's/\-[0-9.]*\.tgz//'| cut -d / -f 2 | sort)
    do
        find . -name "$i-[0-9.]*.tgz" -print -exec cp -av {} "../artifacts/$i.tgz" \;
    done
    popd
fi
if [[ ${MAKE_CHARTS_SHIPYARD} = true ]] ; then
    pushd shipyard
    make charts
    for i in $(find  . -maxdepth 1  -name "*.tgz"  -print | sed -e 's/\-[0-9.]*\.tgz//'| cut -d / -f 2 | sort)
    do
        find . -name "$i-[0-9.]*.tgz" -print -exec cp -av {} "../artifacts/$i.tgz" \;
    done
    popd
fi
if [[ ${MAKE_CHARTS_OSH_INFRA} = true ]] ; then
    pushd openstack-helm-infra
    make all
    for i in $(find  . -maxdepth 1  -name "*.tgz"  -print | sed -e 's/\-[0-9.]*\.tgz//'| cut -d / -f 2 | sort)
    do
        find . -name "$i-[0-9.]*.tgz" -print -exec cp -av {} "../artifacts/$i.tgz" \;
    done
    popd
fi
if [[ ${MAKE_CHARTS_OPENSTACK_HELM} = true ]] ; then
    pushd openstack-helm
    make all
    for i in $(find  . -maxdepth 1  -name "*.tgz"  -print | sed -e 's/\-[0-9.]*\.tgz//'| cut -d / -f 2 | sort)
    do
        find . -name "$i-[0-9.]*.tgz" -print -exec cp -av {} "../artifacts/$i.tgz" \;
    done
    popd
fi
if [[ ${MAKE_CHARTS_MAAS} = true ]] ; then
    pushd maas
    make charts
    for i in $(find  . -maxdepth 1  -name "*.tgz"  -print | sed -e 's/\-[0-9.]*\.tgz//'| cut -d / -f 2 | sort)
    do
        find . -name "$i-[0-9.]*.tgz" -print -exec cp -av {} "../artifacts/$i.tgz" \;
    done
    popd
fi
if [[ ${MAKE_CHARTS_PORTHOLE} = true ]] ; then
    pushd porthole
    make charts
    cd charts
    for i in $(find  . -maxdepth 1  -name "*.tgz"  -print | sed -e 's/\-[0-9.]*\.tgz//'| cut -d / -f 2 | sort)
    do
        find . -name "$i-[0-9.]*.tgz" -print -exec cp -av {} "../../artifacts/$i.tgz" \;
    done
    popd
fi
if [[ ${MAKE_CHARTS_PROMENADE} = true ]] ; then
    pushd promenade
    make charts
    cd charts
    for i in $(find  . -maxdepth 1  -name "*.tgz"  -print | sed -e 's/\-[0-9.]*\.tgz//'| cut -d / -f 2 | sort)
    do
        find . -name "$i-[0-9.]*.tgz" -print -exec cp -av {} "../../artifacts/$i.tgz" \;
    done
    popd
fi

cd "${CURRENT_DIR}"
df -h