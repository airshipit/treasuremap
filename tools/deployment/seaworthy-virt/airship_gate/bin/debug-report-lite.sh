#!/usr/bin/env bash
# Copyright 2019 AT&T Intellectual Property.  All other rights reserved.
#
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


set -ux

SUBDIR_NAME=debug-$(hostname)

# NOTE(mark-burnett): This should add calicoctl to the path.
export PATH=${PATH}:/opt/cni/bin

TEMP_DIR=$(mktemp -d)
export TEMP_DIR
export BASE_DIR="${TEMP_DIR}/${SUBDIR_NAME}"
export HELM_DIR="${BASE_DIR}/helm"
export CALICO_DIR="${BASE_DIR}/calico"

mkdir -p "${BASE_DIR}"

export OBJECT_TYPE="${OBJECT_TYPE:="pods"}"
export CLUSTER_TYPE="${CLUSTER_TYPE:="namespace"}"
export PARALLELISM_FACTOR="${PARALLELISM_FACTOR:=2}"

function get_releases () {
    helm list --all --short
}

function get_release () {
    input=($1)
    RELEASE=${input[0]}
    helm status "${RELEASE}" > "${HELM_DIR}/${RELEASE}.txt"

}
export -f get_release

if which helm; then
    mkdir -p "${HELM_DIR}"
    helm list --all > "${HELM_DIR}/list"
    get_releases | \
        xargs -r -n 1 -P "${PARALLELISM_FACTOR}" -I {} bash -c 'get_release "$@"' _ {}
fi

kubectl get --all-namespaces -o wide pods > "${BASE_DIR}/pods.txt"
kubectl get pods --all-namespaces -o yaml  > "${BASE_DIR}/pods_long.yaml"
kubectl describe pods --all-namespaces > "${BASE_DIR}/pods_describe.txt"

./tools/deployment/seaworthy-virt/airship_gate/bin/namespace-objects.sh
./tools/deployment/seaworthy-virt/airship_gate/bin/cluster-objects.sh

iptables-save > "${BASE_DIR}/iptables"

cat /var/log/syslog > "${BASE_DIR}/syslog"
cat /var/log/armada/bootstrap-armada.log > "${BASE_DIR}/bootstrap-armada.log"

ip addr show > "${BASE_DIR}/ifconfig"
ip route show > "${BASE_DIR}/ip-route"
cp -p /etc/resolv.conf "${BASE_DIR}/"

env | sort --ignore-case > "${BASE_DIR}/environment"
docker images > "${BASE_DIR}/docker-images"

if which calicoctl; then
    mkdir -p "${CALICO_DIR}"
    for kind in bgpPeer hostEndpoint ipPool nodes policy profile workloadEndpoint; do
        calicoctl get "${kind}" -o yaml > "${CALICO_DIR}/${kind}.yaml"
    done
fi

tar zcf "${SUBDIR_NAME}.tgz" -C "${TEMP_DIR}" "${SUBDIR_NAME}"
