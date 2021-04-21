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

export KUBECONFIG=${KUBECONFIG:-"$HOME/.airship/kubeconfig"}
export KUBECONFIG_TARGET_CONTEXT=${KUBECONFIG_TARGET_CONTEXT:-"target-cluster"}
: ${AIRSHIPCTL_PROJECT:="../airshipctl"}

export WORKER_NODE=${WORKER_NODE:-"$(airshipctl phase render workers-target \
	-k BareMetalHost 2> /dev/null | \
	yq .metadata.name | \
	sed 's/"//g')"}

# Annotate node for hostconfig-operator
hosts=$(kubectl \
  --kubeconfig $KUBECONFIG \
  --context $KUBECONFIG_TARGET_CONTEXT \
  --request-timeout 10s get nodes -o name)

for i in "${!hosts[@]}"
do
    kubectl \
      --kubeconfig $KUBECONFIG \
      --context $KUBECONFIG_TARGET_CONTEXT \
      --request-timeout 10s annotate --overwrite ${hosts[i]} secret=hco-ssh-auth
    kubectl \
      --kubeconfig $KUBECONFIG \
      --context $KUBECONFIG_TARGET_CONTEXT \
      --request-timeout 10s label --overwrite ${hosts[i]} kubernetes.io/role=master
done

cd ${AIRSHIPCTL_PROJECT}
./tools/deployment/35_deploy_worker_node.sh

hosts=$(kubectl \
  --kubeconfig $KUBECONFIG \
  --context $KUBECONFIG_TARGET_CONTEXT \
  --request-timeout 10s get nodes -o name)

# Annotate node for hostconfig-operator
for i in "${!hosts[@]}"
do
    kubectl \
      --kubeconfig $KUBECONFIG \
      --context $KUBECONFIG_TARGET_CONTEXT \
      --request-timeout 10s annotate --overwrite ${hosts[i]} secret=hco-ssh-auth
    kubectl \
      --kubeconfig $KUBECONFIG \
      --context $KUBECONFIG_TARGET_CONTEXT \
      --request-timeout 10s label --overwrite ${hosts[i]} kubernetes.io/role=master
done
