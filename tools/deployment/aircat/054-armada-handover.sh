#!/bin/bash
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

# The cluster is handed over to the Armada of the site after the genesis
# (kubeadm-cluster manifest deployed by the bootstrap Armada,
# 050-armada-apply.sh): the bootstrap operator is removed, the Armada
# operator of the site reconciles the ArmadaChart resources from now on. The
# documents of the site are uploaded to Deckhand: the rest of the nodes join
# the cluster then (tools/gate/playbooks/aircat-multinode-deploy.yaml) and
# the full site is deployed (056-armada-full-site.sh).

set -ex

: "${ARTIFACTS_HOST:="artifacts.airship.internal"}"
: "${ARTIFACTS_PORT:="8282"}"
: "${BOOTSTRAP_DIR:="/var/lib/armada-bootstrap"}"
: "${MANIFESTS_DIR:="/etc/kubernetes/manifests"}"
: "${UCP_NAMESPACE:="ucp"}"
: "${SMOKE_TEST_IMAGE:="quay.io/airshipit/network-multitool"}"

# shellcheck source=tools/deployment/aircat/common.sh
source ./tools/deployment/aircat/common.sh

NODE_NAME=$(./tools/deployment/aircat/get-site-nodes.py "${RENDERED}" local | cut -d ' ' -f 1)

# The Armada operator of the site takes the charts from the artifact
# repository by its name from the pod network
kubectl run artifacts-check --image="${SMOKE_TEST_IMAGE}" --restart=Never --rm -i \
  --command -- curl -fsSI "http://${ARTIFACTS_HOST}:${ARTIFACTS_PORT}/kubeadm.tgz"

# Hand over
sudo rm -f "${MANIFESTS_DIR}/armada-operator.yaml"
kubectl -n "${NAMESPACE}" wait --for=delete "pod/armada-operator-${NODE_NAME}" --timeout=300s || true
sudo touch "${BOOTSTRAP_DIR}/armada-api"
kubectl -n "${UCP_NAMESPACE}" get pods -l application=armada -o wide

UPLOAD_ONLY=true ./tools/deployment/aircat/050-armada-apply.sh
