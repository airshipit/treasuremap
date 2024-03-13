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
: "${ARMADA:="./tools/airship armada"}"
: "${ARMADA_OPERATOR:="./tools/airship armada-operator"}"
: "${TARGET_MANIFEST:="cluster-bootstrap"}"
: "${USE_ARMADA_GO:=false}"

USE_ARMADA_GO=$(echo "$USE_ARMADA_GO" | tr '[:upper:]' '[:lower:]')
export USE_ARMADA_GO

# Render documents
${PEGLEG} site -r . render "${PL_SITE}" -o airskiff.yaml

# Set permissions o+r, beacause these files need to be readable
# for Armada in the container
AIRSKIFF_PERMISSIONS=$(stat --format '%a' airskiff.yaml)
# KUBE_CONFIG_PERMISSIONS=$(stat --format '%a' ~/.kube/config)

sudo chmod 0644 airskiff.yaml
# sudo chmod 0644 ~/.kube/config

# Download latest Armada image and deploy Airship components
if [[ ${USE_ARMADA_GO} = true ]] ; then
    ${ARMADA_OPERATOR} apply /airskiff.yaml --debug --target-manifest "${TARGET_MANIFEST}"
else
    ${ARMADA} apply /airskiff.yaml --debug --target-manifest "${TARGET_MANIFEST}"
fi
# # Set back permissions of the files
sudo chmod "${AIRSKIFF_PERMISSIONS}" airskiff.yaml
# sudo chmod "${KUBE_CONFIG_PERMISSIONS}" ~/.kube/config

kubectl get pods -A
