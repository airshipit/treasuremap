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

# Convert both values to lowercase (or uppercase)
MAKE_ARMADA_IMAGES=$(echo "$MAKE_ARMADA_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_ARMADA_GO_IMAGES=$(echo "$MAKE_ARMADA_GO_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_ARMADA_OPERATOR_IMAGES=$(echo "$MAKE_ARMADA_OPERATOR_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_DECKHAND_IMAGES=$(echo "$MAKE_DECKHAND_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_SHIPYARD_IMAGES=$(echo "$MAKE_SHIPYARD_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_PORTHOLE_IMAGES=$(echo "$MAKE_PORTHOLE_IMAGES" | tr '[:upper:]' '[:lower:]')
MAKE_PROMENADE_IMAGES=$(echo "$MAKE_PROMENADE_IMAGES" | tr '[:upper:]' '[:lower:]')

export MAKE_ARMADA_IMAGES
export MAKE_ARMADA_GO_IMAGES
export MAKE_ARMADA_OPERATOR_IMAGES
export MAKE_DECKHAND_IMAGES
export MAKE_SHIPYARD_IMAGES
export MAKE_PORTHOLE_IMAGES
export MAKE_PROMENADE_IMAGES

cd "${INSTALL_PATH}"

# Start docker registry
docker rm registry --force || true
docker run -d -p 5000:5000 --restart=always --name registry registry:2
curl -Ik "http://${DOCKER_REGISTRY}"

# Make charts in Airship and OSH-INFRA projects
if [[ ${MAKE_ARMADA_IMAGES} = true ]] ; then
    pushd armada
    make images
    docker push "${DOCKER_REGISTRY}/airshipit/armada:latest-${DISTRO}"
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/armada:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/armada:latest-${DISTRO}#g" ./site/airskiff/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/armada:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/armada:latest-${DISTRO}#g" ./global/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_ARMADA_GO_IMAGES} = true ]] ; then
    pushd armada-go
    make images
    docker push "${DOCKER_REGISTRY}/airshipit/armada-go:latest-${DISTRO}"
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/armada-go:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/armada-go:latest-${DISTRO}#g" ./site/airskiff/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/armada-go:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/armada-go:latest-${DISTRO}#g" ./global/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_ARMADA_OPERATOR_IMAGES} = true ]] ; then
    pushd armada-operator
    make images
    docker push "${DOCKER_REGISTRY}/airshipit/armada-operator:latest-${DISTRO}"
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/armada-operator:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/armada-operator:latest-${DISTRO}#g" ./site/airskiff/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/armada-operator:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/armada-operator:latest-${DISTRO}#g" ./global/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_DECKHAND_IMAGES} = true ]] ; then
    pushd deckhand
    make images
    docker push "${DOCKER_REGISTRY}/airshipit/deckhand:latest-${DISTRO}"
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/deckhand:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/deckhand:latest-${DISTRO}#g" ./site/airskiff/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/deckhand:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/deckhand:latest-${DISTRO}#g" ./global/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_SHIPYARD_IMAGES} = true ]] ; then
    pushd shipyard
    make images
    docker push "${DOCKER_REGISTRY}/airshipit/airflow:latest-${DISTRO}"
    docker push "${DOCKER_REGISTRY}/airshipit/shipyard:latest-${DISTRO}"
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/airflow:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/airflow:latest-${DISTRO}#g" ./site/airskiff/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/shipyard:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/shipyard:latest-${DISTRO}#g" ./site/airskiff/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/airflow:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/airflow:latest-${DISTRO}#g" ./global/software/config/versions.yaml
    sed -i "s#quay.io/airshipit/shipyard:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/shipyard:latest-${DISTRO}#g" ./global/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_PORTHOLE_IMAGES} = true ]] ; then
    pushd porthole
    make images
    # Define a list of images
    IMAGE_LIST=("calicoctl-utility" "ceph-utility" "compute-utility" "etcdctl-utility" "mysqlclient-utility" "openstack-utility" "postgresql-utility")
    for IMAGE in "${IMAGE_LIST}"
    do
        docker push "${DOCKER_REGISTRY}/airshipit/porthole-${IMAGE}:latest-${DISTRO}"
    done
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/porthole-${IMAGE}:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/porthole-${IMAGE}:latest-${DISTRO}#g" ./global/software/config/versions.yaml
    popd
fi
if [[ ${MAKE_PROMENADE_IMAGES} = true ]] ; then
    pushd promenade
    make images
    docker push "${DOCKER_REGISTRY}/airshipit/promenade:latest-${DISTRO}"
    popd
    pushd treasuremap
    sed -i "s#quay.io/airshipit/promenade:latest-${DISTRO}#${DOCKER_REGISTRY}/airshipit/promenade:latest-${DISTRO}#g" ./global/software/config/versions.yaml
    popd
fi

docker images
cd "${CURRENT_DIR}"
