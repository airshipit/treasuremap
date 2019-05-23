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

: "${INSTALL_PATH:="$(pwd)/../"}"
: "${PEGLEG:="./tools/airship pegleg"}"
: "${PL_SITE:="airskiff"}"
: "${TARGET_MANIFEST:="ucp-bootstrap"}"

# Render documents
${PEGLEG} site -r . render "${PL_SITE}" -o airskiff.yaml

# Download latest Armada image and deploy Airship components
docker run --rm --net host -p 8000:8000 --name armada \
    -v ~/.kube/config:/armada/.kube/config \
    -v "$(pwd)"/airskiff.yaml:/airskiff.yaml \
    -v "${INSTALL_PATH}":/airship-components \
    quay.io/airshipit/armada:latest \
    apply /airskiff.yaml --target-manifest $TARGET_MANIFEST
