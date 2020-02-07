#!/usr/bin/env bash
# Copyright 2017 The Openstack-Helm Authors.
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

set -e

export CLUSTER_TYPE="${CLUSTER_TYPE:="node,clusterrole,clusterrolebinding,storageclass,namespace"}"
export PARALLELISM_FACTOR="${PARALLELISM_FACTOR:=2}"

function list_objects () {
    printf "%s" ${CLUSTER_TYPE} | xargs -d ',' -I {} -P1 -n1 bash -c 'echo "$@"' _ {}
}

export -f list_objects

function name_objects () {
    export OBJECT=$1
    kubectl get "${OBJECT}" -o name | xargs -L1 -I {} -P1 -n1 bash -c "echo ${OBJECT} ${1#*/}" _ {}
}

export -f name_objects

function get_objects () {
    input=($1)
    export OBJECT=${input[0]}
    export NAME=${input[1]#*/}
    echo "${OBJECT}/${NAME}"
    export BASE_DIR="${BASE_DIR:="/tmp"}"
    DIR="${BASE_DIR}/objects/cluster/${OBJECT}"
    mkdir -p "${DIR}"
    kubectl get "${OBJECT}" "${NAME}" -o yaml > "${DIR}/${NAME}.yaml"
    kubectl describe "${OBJECT}" "${NAME}" > "${DIR}/${NAME}.txt"
}

export -f get_objects
list_objects | \
xargs -r -n 1 -P ${PARALLELISM_FACTOR} -I {} bash -c 'name_objects "$@"' _ {} | \
xargs -r -n 1 -P ${PARALLELISM_FACTOR} -I {} bash -c 'get_objects "$@"' _ {}
