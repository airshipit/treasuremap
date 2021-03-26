#!/usr/bin/env bash

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -ex

TMP=$(mktemp -d)

MANIFEST_FILE="$TMP/network-policy.yaml"
export SITE=${SITE:="test-site"}

export KUBECONFIG=${KUBECONFIG:="$HOME/.airship/kubeconfig"}
export KUBECONFIG_TARGET_CONTEXT=${KUBECONFIG_TARGET_CONTEXT:="target-cluster"}
: ${TREASUREMAP_PROJECT:="${PWD}"}

#Generate all of the policies and deploy using calicoctl
kustomize build --enable_alpha_plugins $TREASUREMAP_PROJECT/manifests/site/$SITE/target/network-policies -o ${MANIFEST_FILE}

#What about per node basis. Also usage of calico apply/replace
DATASTORE_TYPE=kubernetes calicoctl apply -f ${MANIFEST_FILE}
