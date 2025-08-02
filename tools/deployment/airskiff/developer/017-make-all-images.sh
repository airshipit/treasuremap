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
: "${DISTRO:=ubuntu_focal}"
: "${DOCKER_REGISTRY:=localhost:5000}"
: "${MAKE_ARMADA_IMAGES:=false}"
: "${MAKE_ARMADA_GO_IMAGES:=false}"
: "${MAKE_ARMADA_OPERATOR_IMAGES:=false}"
: "${MAKE_DECKHAND_IMAGES:=false}"
: "${MAKE_SHIPYARD_IMAGES:=false}"
: "${MAKE_PORTHOLE_IMAGES:=false}"
: "${MAKE_PROMENADE_IMAGES:=false}"
: "${MAKE_PEGLEG_IMAGES:=false}"
: "${MAKE_MAAS_IMAGES:=false}"
: "${MAKE_DRYDOCK_IMAGES:=false}"
: "${MAKE_KUBERTENES_ENTRYPOINT_IMAGES:=false}"


: "${DISTRO:=ubuntu_jammy}"

# Convert both values to lowercase (or uppercase)
MAKE_ARMADA_IMAGES=$(echo "$MAKE_ARMADA_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_ARMADA_GO_IMAGES=$(echo "$MAKE_ARMADA_GO_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_ARMADA_OPERATOR_IMAGES=$(echo "$MAKE_ARMADA_OPERATOR_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_DECKHAND_IMAGES=$(echo "$MAKE_DECKHAND_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_SHIPYARD_IMAGES=$(echo "$MAKE_SHIPYARD_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_PORTHOLE_IMAGES=$(echo "$MAKE_PORTHOLE_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_PROMENADE_IMAGES=$(echo "$MAKE_PROMENADE_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_PEGLEG_IMAGES=$(echo "$MAKE_PEGLEG_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_MAAS_IMAGES=$(echo "$MAKE_MAAS_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_DRYDOCK_IMAGES=$(echo "$MAKE_DRYDOCK_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_KUBERTENES_ENTRYPOINT_IMAGES=$(echo "$MAKE_KUBERTENES_ENTRYPOINT_IMAGES" | tr '[:upper:]' '[:lower:]')

export MAKE_ARMADA_IMAGES
export MAKE_ARMADA_GO_IMAGES
export MAKE_ARMADA_OPERATOR_IMAGES
export MAKE_DECKHAND_IMAGES
export MAKE_SHIPYARD_IMAGES
export MAKE_PORTHOLE_IMAGES
export MAKE_PROMENADE_IMAGES
export MAKE_PEGLEG_IMAGES
export MAKE_MAAS_IMAGES
export MAKE_DRYDOCK_IMAGES
export MAKE_KUBERTENES_ENTRYPOINT_IMAGES

export STRIPPED_DISTRO="$(echo ${DISTRO} | sed 's/^ubuntu_//')"

cd "${INSTALL_PATH}"

# Start docker registry
docker rm registry --force || true
docker run -d -p 5000:5000 --restart=always --name registry quay.io/airshipit/registry:2
curl -Ik "http://${DOCKER_REGISTRY}"

# Make charts in Airship and OSH-INFRA projects
if [[ ${MAKE_ARMADA_IMAGES} = true ]] ; then
    pushd armada
    make images
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/armada:latest-#${DOCKER_REGISTRY}/airshipit/armada:latest-#g" ./site/airskiff/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/armada:latest-#${DOCKER_REGISTRY}/airshipit/armada:latest-#g" ./global/software/config/versions.yaml
    grep armada global/software/config/versions.yaml
    grep armada site/airskiff/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_ARMADA_GO_IMAGES} = true ]] ; then
    pushd armada-go
    make images
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/armada-go:latest-#${DOCKER_REGISTRY}/airshipit/armada-go:latest-#g" ./global/software/config/versions.yaml
    grep armada-go global/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_ARMADA_OPERATOR_IMAGES} = true ]] ; then
    pushd armada-operator
    make images
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/armada-operator:latest-#${DOCKER_REGISTRY}/airshipit/armada-operator:latest-#g" ./global/software/config/versions.yaml
    grep armada-operator global/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_DECKHAND_IMAGES} = true ]] ; then
    pushd deckhand
    make images
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/deckhand:latest-#${DOCKER_REGISTRY}/airshipit/deckhand:latest-#g" ./site/airskiff/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/deckhand:latest-#${DOCKER_REGISTRY}/airshipit/deckhand:latest-#g" ./global/software/config/versions.yaml
    grep deckhand global/software/config/versions.yaml
    grep deckhand site/airskiff/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_SHIPYARD_IMAGES} = true ]] ; then
    pushd shipyard
    make images
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/airflow:latest-#${DOCKER_REGISTRY}/airshipit/airflow:latest-#g" ./site/airskiff/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/shipyard:latest-#${DOCKER_REGISTRY}/airshipit/shipyard:latest-#g" ./site/airskiff/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/airflow:latest-#${DOCKER_REGISTRY}/airshipit/airflow:latest-#g" ./global/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/shipyard:latest-#${DOCKER_REGISTRY}/airshipit/shipyard:latest-#g" ./global/software/config/versions.yaml
    grep airflow global/software/config/versions.yaml
    grep airflow site/airskiff/software/config/versions.yaml
    grep shipyard global/software/config/versions.yaml
    grep shipyard site/airskiff/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_PORTHOLE_IMAGES} = true ]] ; then
    pushd porthole
    make images
    popd
    # Define a list of images
    IMAGE_LIST=("calicoctl-utility" "ceph-utility" "compute-utility" "etcdctl-utility" "mysqlclient-utility" "openstack-utility" "postgresql-utility")
    for IMAGE in ${IMAGE_LIST}
    do

        pushd treasuremap
        sed -i "s#quay.io/airshipit/porthole-${IMAGE}:latest-#${DOCKER_REGISTRY}/airshipit/porthole-${IMAGE}:latest-#g" ./global/software/config/versions.yaml
        grep ${IMAGE} global/software/config/versions.yaml
        popd
    done
fi
if [[ ${MAKE_PROMENADE_IMAGES} = true ]] ; then
    pushd promenade
    make images
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/promenade:latest-#${DOCKER_REGISTRY}/airshipit/promenade:latest-#g" ./global/software/config/versions.yaml
    grep promenade global/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_PEGLEG_IMAGES} = true ]] ; then
    pushd pegleg
    make images
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/pegleg:latest-#${DOCKER_REGISTRY}/airshipit/pegleg:latest-#g" ./global/software/config/versions.yaml
    grep pegleg global/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_MAAS_IMAGES} = true ]] ; then
    pushd maas
    make images
    popd
    pushd treasuremap
# ...existing code...

if [[ "$STRIPPED_DISTRO" == "jammy" ]]; then
    echo "Running commands for Ubuntu Jammy"
    sed -i "s/default_image: .*/default_image: 'jammy'/" global/software/charts/ucp/drydock/maas.yaml
    sed -i "s/default_kernel: .*/default_kernel: 'ga-22.04'/" global/software/charts/ucp/drydock/maas.yaml
    sed -i "s#quay.io/airshipit/maas-region-controller-[a-zA-Z0-9]\+:latest#${DOCKER_REGISTRY}/airshipit/maas-region-controller-${STRIPPED_DISTRO}:latest#g" ./global/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/maas-rack-controller-[a-zA-Z0-9]\+:latest#${DOCKER_REGISTRY}/airshipit/maas-rack-controller-${STRIPPED_DISTRO}:latest#g" ./global/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/sstream-cache-[a-zA-Z0-9]\+:latest#${DOCKER_REGISTRY}/airshipit/sstream-cache-${STRIPPED_DISTRO}:latest#g" ./global/software/config/versions.yaml
    # Add Jammy-specific commands here
elif [[ "$STRIPPED_DISTRO" == "focal" ]]; then
    echo "Running commands for Ubuntu Focal"
    # Add Focal-specific commands here
    sed -i "s/default_image: .*/default_image: 'focal'/" global/software/charts/ucp/drydock/maas.yaml
    sed -i "s/default_kernel: .*/default_kernel: 'ga-20.04'/" global/software/charts/ucp/drydock/maas.yaml
    sed -i "s#quay.io/airshipit/maas-region-controller-[a-zA-Z0-9]\+:latest#${DOCKER_REGISTRY}/airshipit/maas-region-controller-${STRIPPED_DISTRO}:latest#g" ./global/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/maas-rack-controller-[a-zA-Z0-9]\+:latest#${DOCKER_REGISTRY}/airshipit/maas-rack-controller-${STRIPPED_DISTRO}:latest#g" ./global/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/sstream-cache-[a-zA-Z0-9]\+:latest#${DOCKER_REGISTRY}/airshipit/sstream-cache-${STRIPPED_DISTRO}:latest#g" ./global/software/config/versions.yaml
fi
    grep maas global/software/config/versions.yaml
    grep sstream global/software/config/versions.yaml
    grep default_image global/software/charts/ucp/drydock/maas.yaml
    grep default_kernel global/software/charts/ucp/drydock/maas.yaml
    popd
fi
if [[ ${MAKE_DRYDOCK_IMAGES} = true ]] ; then
    pushd drydock
    make images
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/drydock:latest-#${DOCKER_REGISTRY}/airshipit/drydock:latest-#g" ./global/software/config/versions.yaml
    grep drydock global/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_KUBERTENES_ENTRYPOINT_IMAGES} = true ]] ; then
    pushd kubernetes-entrypoint
    make images
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/kubernetes-entrypoint:latest-#${DOCKER_REGISTRY}/airshipit/kubernetes-entrypoint:latest-#g" ./global/software/config/versions.yaml
    grep kubernetes-entrypoint global/software/config/versions.yaml
    popd
fi

docker images
cd "${CURRENT_DIR}"
