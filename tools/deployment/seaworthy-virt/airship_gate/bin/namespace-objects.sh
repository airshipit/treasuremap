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

export OBJECT_TYPE="${OBJECT_TYPE:="configmaps,cronjobs,daemonsets,deployment,endpoints,ingresses,jobs,networkpolicies,pods,podsecuritypolicies,persistentvolumeclaims,rolebindings,roles,secrets,serviceaccounts,services,statefulsets"}"
export PARALLELISM_FACTOR="${PARALLELISM_FACTOR:=2}"

function get_namespaces () {
  kubectl get namespaces -o name | awk -F '/' '{ print $NF }'
}

function list_namespaced_objects () {
  export NAMESPACE=$1
  printf "%s" "${OBJECT_TYPE}" | xargs -d ',' -I {} -P1 -n1 bash -c "echo ${NAMESPACE} ${1#*/}" _ {}
}

export -f list_namespaced_objects

function name_objects () {
  input=($1)
  export NAMESPACE=${input[0]}
  export OBJECT=${input[1]}
  kubectl get -n "${NAMESPACE}" "${OBJECT}" -o name | xargs -L1 -I {} -P1 -n1 bash -c "echo ${NAMESPACE} ${OBJECT} ${1#*/}" _ {}
}

export -f name_objects

function get_objects () {
  input=($1)
  export NAMESPACE=${input[0]}
  export OBJECT=${input[1]}
  export NAME=${input[2]#*/}
  echo "${NAMESPACE}/${OBJECT}/${NAME}"
  export BASE_DIR="${BASE_DIR:="/tmp"}"
  DIR="${BASE_DIR}/namespaces/${NAMESPACE}/${OBJECT}"
  mkdir -p "${DIR}"
  kubectl get -n "${NAMESPACE}" "${OBJECT}" "${NAME}" -o yaml > "${DIR}/${NAME}.yaml"
  kubectl describe -n "${NAMESPACE}" "${OBJECT}" "${NAME}" > "${DIR}/${NAME}.txt"

  LOG_DIR="${BASE_DIR}/pod-logs"
  mkdir -p ${LOG_DIR}

  if [ ${OBJECT_TYPE} = "pods" ]; then
    POD_DIR="${LOG_DIR}/${NAME}"
    mkdir -p "${POD_DIR}"
    CONTAINERS=$(kubectl get pod "${NAME}" -n "${NAMESPACE}" -o json | jq -r '.spec.containers[].name')
    for CONTAINER in ${CONTAINERS}; do
      kubectl logs -n "${NAMESPACE}" "${NAME}" -c "${CONTAINER}" > "${POD_DIR}/${CONTAINER}.txt"
    done
  fi
}

export -f get_objects

get_namespaces | \
xargs -r -n 1 -P ${PARALLELISM_FACTOR} -I {} bash -c 'list_namespaced_objects "$@"' _ {} | \
xargs -r -n 1 -P ${PARALLELISM_FACTOR} -I {} bash -c 'name_objects "$@"' _ {} | \
xargs -r -n 1 -P ${PARALLELISM_FACTOR} -I {} bash -c 'get_objects "$@"' _ {}
