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

# Day 2: hand the cluster built on day 0 over to Armada (armada-operator).
# The kubeadm-cluster manifest of the site is deployed: Calico (Tigera
# operator) and the kubeadm chart with the same values as on day 0 (and the
# genesis of the site components if the site has them). The anchor
# daemonsets of the kubeadm chart take over the node configuration and keep
# it in sync with the chart values.
#
# Armada is bootstrapped with static pods of this (the first control plane)
# node, as in the Airship genesis: there is no CNI before Calico is deployed
# by Armada, static pods are run by kubelet on the host network.
#   armada-artifacts - nginx serving the charts of the project checkouts
#   armada-registry  - registry of the images built from the project checkouts
#   armada-operator  - reconciles ArmadaChart resources (leader election, so
#                      an in-cluster operator can take over later)
#   armada-apply-*   - armada-go apply of the manifest (one-shot)
#
# Usage: 050-armada-apply.sh [<documents>]
# <documents> are rendered site documents to deploy, the rendered site by
# default. The cluster configuration is changed by changing the documents of
# the site (see set-document-data.py) and rendering it again.
#
# After the hand over to the Armada of the site (054-armada-handover.sh)
# the documents of the site are uploaded to Deckhand as they are (Pegleg
# collect: Deckhand renders them, the secrets are stored in Barbican) and
# applied with the Armada API, the kubeadm-full-site manifest by default.
# UPLOAD_ONLY=true uploads them only.

set -ex

: "${INSTALL_PATH:="../"}"
: "${ARTIFACTS_PATH:="${INSTALL_PATH}/artifacts"}"
# Artifact repository of the site (the host name is set up by
# tools/gate/playbooks/airliner-deploy-env.yaml): charts (nginx) and images
# (registry) served on the host network of this node
: "${ARTIFACTS_HOST:="artifacts.airship.internal"}"
: "${ARTIFACTS_PORT:="8282"}"
: "${ARTIFACTS_IMAGE:="quay.io/airshipit/nginx:alpine3.18"}"
: "${REGISTRY_PORT:="5000"}"
: "${REGISTRY_IMAGE:="quay.io/airshipit/registry:2"}"
# The distro of the images built from the checkouts: the tag of the images
# the documents refer to (DISTRO of the environment of the gate scripts may
# differ)
: "${BUILD_IMAGES_DISTRO:="ubuntu_noble"}"
: "${ARMADA_OPERATOR_CRDS:="${INSTALL_PATH}/armada-operator/config/crd/bases"}"
: "${OSH_PATH:="${INSTALL_PATH}/../openstack/openstack-helm"}"
: "${APPLY_TIMEOUT:="3600"}"
# Host directory of the bootstrap: charts, nginx config, documents to apply
: "${BOOTSTRAP_DIR:="/var/lib/armada-bootstrap"}"
: "${MANIFESTS_DIR:="/etc/kubernetes/manifests"}"
# The Armada of the site (after 054-armada-full-site.sh): namespace of the
# Airship components
: "${UCP_NAMESPACE:="ucp"}"
: "${UPLOAD_ONLY:="false"}"
: "${PEGLEG:="./tools/airship pegleg"}"

# shellcheck source=tools/deployment/airliner/common.sh
source ./tools/deployment/airliner/common.sh

DOCUMENTS=$(realpath "${1:-${RENDERED}}")
# static pods run on this node (the genesis one): mirror pods are named
# <pod>-<node>
read -r NODE_NAME NODE_IP _ <<< "$(./tools/deployment/airliner/get-site-nodes.py "${RENDERED}" local)"

# After the hand over to the Armada of the site (054-armada-handover.sh)
# the bootstrap operator isn't run, the changes are applied with the API.
ARMADA_API=false
if sudo test -f "${BOOTSTRAP_DIR}/armada-api"; then
  ARMADA_API=true
  : "${TARGET_MANIFEST:="kubeadm-full-site"}"
fi
: "${TARGET_MANIFEST:="kubeadm-cluster"}"

versions_image() {
  ./tools/deployment/airliner/get-document-data.py "${DOCUMENTS}" \
    pegleg/SoftwareVersions/v1 software-versions "images.ucp.armada-operator.$1"
}
ARMADA_OPERATOR_IMAGE=$(versions_image operator)
ARMADA_GO_IMAGE=$(versions_image go)

# Write a static pod manifest (from stdin) unless it is up to date: kubelet
# restarts the pod when the manifest changes.
static_pod() {
  local file="${MANIFESTS_DIR}/$1.yaml" manifest
  manifest=$(mktemp)
  cat > "${manifest}"
  if ! sudo cmp -s "${manifest}" "${file}"; then
    sudo install -m 0600 "${manifest}" "${file}"
  fi
  rm -f "${manifest}"
}

# admin.conf references certificate files readable by root only,
# make a self-contained copy for the current user.
mkdir -p "${HOME}/.kube"
# shellcheck disable=SC2024
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf config view --raw --flatten > "${HOME}/.kube/config"
chmod 0600 "${HOME}/.kube/config"
kubectl get nodes -o wide

# Charts the documents take from the artifact repository, built from the
# checkouts of their projects (the kubeadm chart of the promenade checkout
# is the same as on day 0)
build_chart() {
  local chart=$1
  case "${chart}" in
    kubeadm|tigera-operator)
      make -C "${INSTALL_PATH}/promenade" charts
      cp -v "${INSTALL_PATH}/promenade/charts/${chart}"-[0-9]*.tgz "${ARTIFACTS_PATH}/${chart}.tgz"
      ;;
    armada)
      make -C "${INSTALL_PATH}/armada" charts
      cp -v "${INSTALL_PATH}/armada/charts/armada"-[0-9]*.tgz "${ARTIFACTS_PATH}/armada.tgz"
      ;;
    deckhand)
      make -C "${INSTALL_PATH}/deckhand" charts
      cp -v "${INSTALL_PATH}/deckhand/deckhand"-[0-9]*.tgz "${ARTIFACTS_PATH}/deckhand.tgz"
      ;;
    ceph-ready)
      # the charts of the gates (this repository)
      helm package "./tools/deployment/airliner/charts/${chart}" -d "${ARTIFACTS_PATH}"
      mv -v "${ARTIFACTS_PATH}/${chart}"-[0-9]*.tgz "${ARTIFACTS_PATH}/${chart}.tgz"
      ;;
    *)
      # openstack-helm (helm-toolkit is built as a dependency)
      make -C "${OSH_PATH}" SKIP_CHANGELOG=1 "${chart}"
      cp -v "${OSH_PATH}/${chart}"-[0-9]*.tgz "${ARTIFACTS_PATH}/${chart}.tgz"
      ;;
  esac
}
mkdir -p "${ARTIFACTS_PATH}"
CHARTS=$(python3 -c '
import sys, yaml
prefix = sys.argv[2]
for doc in yaml.safe_load_all(open(sys.argv[1])):
    if doc and doc.get("schema") == "armada/Chart/v1":
        location = doc["data"].get("source", {}).get("location", "")
        if location.startswith(prefix) and location.endswith(".tgz"):
            print(location[len(prefix):-len(".tgz")])
' "${DOCUMENTS}" "http://${ARTIFACTS_HOST}:${ARTIFACTS_PORT}/" | sort -u)
for chart in ${CHARTS}; do
  if [[ ! -f "${ARTIFACTS_PATH}/${chart}.tgz" ]]; then
    build_chart "${chart}"
  fi
done
sudo install -d -m 0755 "${BOOTSTRAP_DIR}/charts"
sudo install -m 0644 "${ARTIFACTS_PATH}"/*.tgz "${BOOTSTRAP_DIR}/charts/"
sudo tee "${BOOTSTRAP_DIR}/nginx.conf" > /dev/null << EOF
server {
  listen ${ARTIFACTS_PORT};
  root /usr/share/nginx/html;
}
EOF

static_pod armada-artifacts << EOF
apiVersion: v1
kind: Pod
metadata:
  name: armada-artifacts
  namespace: ${NAMESPACE}
  labels:
    application: armada-bootstrap
    component: artifacts
spec:
  hostNetwork: true
  containers:
    - name: nginx
      image: ${ARTIFACTS_IMAGE}
      readinessProbe:
        tcpSocket:
          port: ${ARTIFACTS_PORT}
      volumeMounts:
        - name: charts
          mountPath: /usr/share/nginx/html
          readOnly: true
        - name: config
          mountPath: /etc/nginx/conf.d/default.conf
          readOnly: true
  volumes:
    - name: charts
      hostPath:
        path: ${BOOTSTRAP_DIR}/charts
        type: Directory
    - name: config
      hostPath:
        path: ${BOOTSTRAP_DIR}/nginx.conf
        type: File
EOF

sudo install -d -m 0755 "${BOOTSTRAP_DIR}/registry"
static_pod armada-registry << EOF
apiVersion: v1
kind: Pod
metadata:
  name: armada-registry
  namespace: ${NAMESPACE}
  labels:
    application: armada-bootstrap
    component: registry
spec:
  hostNetwork: true
  containers:
    - name: registry
      image: ${REGISTRY_IMAGE}
      env:
        - name: REGISTRY_HTTP_ADDR
          value: ":${REGISTRY_PORT}"
      readinessProbe:
        tcpSocket:
          port: ${REGISTRY_PORT}
      volumeMounts:
        - name: data
          mountPath: /var/lib/registry
  volumes:
    - name: data
      hostPath:
        path: ${BOOTSTRAP_DIR}/registry
        type: Directory
EOF

# The artifact repository first: the images built from the checkouts of
# their projects (the bootstrap operator too) are pushed to it.
for pod in armada-artifacts armada-registry; do
  wait_exists 600 -n "${NAMESPACE}" "pod/${pod}-${NODE_NAME}"
  kubectl -n "${NAMESPACE}" wait --for=condition=Ready "pod/${pod}-${NODE_NAME}" --timeout=600s
done
curl -fsSI --retry 10 --retry-all-errors --retry-delay 3 \
  "http://${ARTIFACTS_HOST}:${ARTIFACTS_PORT}/kubeadm.tgz"
curl -fsS --retry 10 --retry-all-errors --retry-delay 3 \
  "http://${ARTIFACTS_HOST}:${REGISTRY_PORT}/v2/"

# Images built from the checkouts of their projects (see 020-render-site.sh),
# pushed to the registry once: the documents refer to them.
if [[ -f build-images ]] && ! sudo test -f "${BOOTSTRAP_DIR}/images-built"; then
  read -r -a IMAGES < build-images
  for image in "${IMAGES[@]}"; do
    make -C "${INSTALL_PATH}/${image}" images PUSH_IMAGE=true \
      DOCKER_REGISTRY="${ARTIFACTS_HOST}:${REGISTRY_PORT}" DISTRO="${BUILD_IMAGES_DISTRO}"
  done
  sudo touch "${BOOTSTRAP_DIR}/images-built"
fi
curl -fsS "http://${ARTIFACTS_HOST}:${REGISTRY_PORT}/v2/_catalog"

# The bootstrap operator: not run after the hand over to the Armada of the
# site (054-armada-handover.sh)
if [[ "${ARMADA_API}" == false ]]; then
static_pod armada-operator << EOF
apiVersion: v1
kind: Pod
metadata:
  name: armada-operator
  namespace: ${NAMESPACE}
  labels:
    application: armada-bootstrap
    component: operator
spec:
  hostNetwork: true
  containers:
    - name: manager
      image: ${ARMADA_OPERATOR_IMAGE}
      command:
        - /manager
      args:
        - --leader-elect
        - --leader-elect-namespace=${NAMESPACE}
        - --health-probe-bind-address=:18081
        - --metrics-bind-address=0
      env:
        - name: KUBECONFIG
          value: /etc/kubernetes/admin.conf
      # admin.conf and its certificates are readable by root only
      securityContext:
        runAsUser: 0
      readinessProbe:
        httpGet:
          path: /readyz
          port: 18081
      volumeMounts:
        - name: kubernetes
          mountPath: /etc/kubernetes
          readOnly: true
  volumes:
    - name: kubernetes
      hostPath:
        path: /etc/kubernetes
        type: Directory
EOF
wait_exists 600 -n "${NAMESPACE}" "pod/armada-operator-${NODE_NAME}"
kubectl -n "${NAMESPACE}" wait --for=condition=Ready "pod/armada-operator-${NODE_NAME}" --timeout=600s
fi


# The charts deployed by Armada on the pod network (the Armada operator of
# the site) take charts from the artifact repository too: its host name (in
# /etc/hosts of the nodes) is resolved by CoreDNS of the site as well. The
# Corefile of kubeadm has no hosts block, add one; kubeadm upgrades keep the
# Corefile (CoreDNS migration). CoreDNS reloads the Corefile itself (reload
# plugin): no restart, its pods don't run before Calico is deployed.
COREFILE=$(kubectl -n "${NAMESPACE}" get configmap coredns -o jsonpath='{.data.Corefile}')
if ! grep -q "${ARTIFACTS_HOST}" <<< "${COREFILE}"; then
  PATCH=$(python3 -c '
import json, sys
corefile, host, ip = sys.argv[1:4]
block = "    hosts {\n        %s %s\n        fallthrough\n    }\n" % (ip, host)
corefile = corefile.replace(".:53 {\n", ".:53 {\n" + block, 1)
assert host in corefile
print(json.dumps({"data": {"Corefile": corefile}}))
' "${COREFILE}" "${ARTIFACTS_HOST}" "${NODE_IP}")
  kubectl -n "${NAMESPACE}" patch configmap coredns --type merge -p "${PATCH}"
fi
kubectl apply -f "${ARMADA_OPERATOR_CRDS}"

# The genesis node runs the genesis Ceph and the Airship components (they
# are placed by these labels), the other nodes are labeled when the site is
# scaled out to them (056-armada-full-site.sh)
kubectl label node "${NODE_NAME}" --overwrite ceph-mon=enabled ceph-osd=enabled \
  ucp-control-plane=enabled

# kubeadm-config and kubelet-config ConfigMaps were created by kubeadm init.
# The chart manages them from now on: hand them over to the Helm release.
# armada-operator applies the release server-side and takes over the fields
# owned by kubeadm.
for cm in kubeadm-config kubelet-config; do
  kubectl -n "${NAMESPACE}" label configmap "${cm}" --overwrite \
    app.kubernetes.io/managed-by=Helm
  kubectl -n "${NAMESPACE}" annotate configmap "${cm}" --overwrite \
    meta.helm.sh/release-name="${RELEASE}" \
    meta.helm.sh/release-namespace="${NAMESPACE}"
done

# The bootstrap Armada: armada-go apply (a static pod) creates (updates) the
# ArmadaChart resources of the manifest and waits for the bootstrap operator
# to reconcile them
bootstrap_apply() {
  APPLY_POD="armada-apply-$(date +%s)"
  sudo install -m 0600 "${DOCUMENTS}" "${BOOTSTRAP_DIR}/${APPLY_POD}.yaml"
  static_pod "${APPLY_POD}" << EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${APPLY_POD}
  namespace: ${NAMESPACE}
  labels:
    application: armada-bootstrap
    component: apply
spec:
  hostNetwork: true
  restartPolicy: Never
  containers:
    - name: apply
      image: ${ARMADA_GO_IMAGE}
      args:
        - apply
        - /documents.yaml
        - --target-manifest
        - ${TARGET_MANIFEST}
      env:
        - name: KUBECONFIG
          value: /etc/kubernetes/admin.conf
      securityContext:
        runAsUser: 0
      volumeMounts:
        - name: kubernetes
          mountPath: /etc/kubernetes
          readOnly: true
        - name: documents
          mountPath: /documents.yaml
          readOnly: true
  volumes:
    - name: kubernetes
      hostPath:
        path: /etc/kubernetes
        type: Directory
    - name: documents
      hostPath:
        path: ${BOOTSTRAP_DIR}/${APPLY_POD}.yaml
        type: File
EOF
  wait_exists 600 -n "${NAMESPACE}" "pod/${APPLY_POD}-${NODE_NAME}"
  END=$(($(date +%s) + APPLY_TIMEOUT))
  until [[ "${PHASE:-}" == Succeeded || "${PHASE:-}" == Failed ]]; do
    if [[ "$(date +%s)" -gt "${END}" ]]; then
      echo "Timed out waiting for armada-go apply" >&2
      PHASE=Timeout
      break
    fi
    sleep 10
    PHASE=$(kubectl -n "${NAMESPACE}" get pod "${APPLY_POD}-${NODE_NAME}" -o jsonpath='{.status.phase}' || true)
  done
  kubectl -n "${NAMESPACE}" logs "${APPLY_POD}-${NODE_NAME}" || true
  sudo rm -f "${MANIFESTS_DIR}/${APPLY_POD}.yaml" "${BOOTSTRAP_DIR}/${APPLY_POD}.yaml"
  kubectl get armadacharts -A -o wide || true
  if [[ "${PHASE}" != Succeeded ]]; then
    kubectl -n "${NAMESPACE}" logs "armada-operator-${NODE_NAME}" --tail=200 || true
    kubectl -n "${NAMESPACE}" get pods -o wide || true
    anchor_logs 200
    exit 1
  fi
}

# The deployed Armada: the documents of the site are uploaded to Deckhand (a
# new revision), the manifest is applied with the Armada API which takes the
# rendered documents of the revision from Deckhand.
api_apply() {
  local work token revision
  # Pegleg runs in a container with the repository mounted: the documents
  # are collected inside it
  local collect=".collect-${PL_SITE}"
  # port forwarding of a previous attempt
  # shellcheck disable=SC2046
  kill $(jobs -p) 2> /dev/null || true
  work=$(mktemp -d)
  chmod 0700 "${work}"
  # errexit doesn't apply here (the function is called in a condition)
  sudo rm -rf "${collect}"
  # shellcheck disable=SC2086
  sudo ${PEGLEG} site -r . collect "${PL_SITE}" -s "${collect}" || return 1
  # the documents contain secrets: kept in the private work directory only.
  # The collected files are readable by root only (the glob too).
  # shellcheck disable=SC2016,SC2024
  sudo bash -c 'cat "$1"/*.yaml' _ "${collect}" > "${work}/documents.yaml" || return 1
  sudo rm -rf "${collect}"
  for forward in keystone-api:15000:5000 deckhand-int:19000:9000 armada-api:18000:8000; do
    IFS=: read -r service local_port port <<< "${forward}"
    kubectl -n "${UCP_NAMESPACE}" port-forward "svc/${service}" "${local_port}:${port}" \
      > "${work}/${service}.log" 2>&1 &
  done
  # shellcheck disable=SC2064
  trap "kill $(jobs -p | tr '\n' ' ') 2> /dev/null || true; rm -rf '${work}'" EXIT
  for local_port in 15000 19000 18000; do
    curl -s -o /dev/null --retry 30 --retry-all-errors --retry-delay 2 "http://127.0.0.1:${local_port}/" || return 1
  done

  # admin credentials of the Keystone of the deployed components
  ./tools/deployment/airliner/get-document-data.py "${DOCUMENTS}" armada/Chart/v1 ucp-keystone \
    values.endpoints.identity.auth.admin | python3 -c '
import json, sys, yaml
a = yaml.safe_load(sys.stdin)
print(json.dumps({"auth": {
    "identity": {"methods": ["password"], "password": {"user": {
        "name": a["username"], "password": a["password"],
        "domain": {"name": a["user_domain_name"]}}}},
    "scope": {"project": {"name": a["project_name"],
                          "domain": {"name": a["project_domain_name"]}}}}}))
' > "${work}/auth.json" || return 1
  set +x
  token=$(curl -fsS -i -X POST -H "Content-Type: application/json" -d @"${work}/auth.json" \
    http://127.0.0.1:15000/v3/auth/tokens | awk -F': ' 'tolower($1) == "x-subject-token" { print $2 }' | tr -d '\r')
  [[ -n "${token}" ]] || { set -x; echo "No Keystone token" >&2; return 1; }

  curl -fsS -X PUT -H "X-Auth-Token: ${token}" -H "Content-Type: application/x-yaml" \
    --data-binary @"${work}/documents.yaml" \
    "http://127.0.0.1:19000/api/v1.0/buckets/${PL_SITE}/documents" > "${work}/bucket.yaml" || {
    set -x
    kubectl -n "${UCP_NAMESPACE}" logs deployment/deckhand-api --tail=100 || true
    return 1
  }
  # the revision of the uploaded documents (a YAML stream of them), the
  # latest one if nothing changed
  revision=$(python3 -c '
import sys, yaml
docs = []
for item in yaml.safe_load_all(open(sys.argv[1])):
    docs.extend(item if isinstance(item, list) else [item] if item else [])
print(max([d["status"]["revision"] for d in docs] or [0]))
' "${work}/bucket.yaml") || return 1
  if [[ "${revision}" == 0 ]]; then
    revision=$(curl -fsS -H "X-Auth-Token: ${token}" http://127.0.0.1:19000/api/v1.0/revisions | \
      python3 -c 'import sys, yaml; print(yaml.safe_load(sys.stdin)["results"][-1]["id"])') || return 1
  fi
  echo "Deckhand revision ${revision}"
  if [[ "${UPLOAD_ONLY}" == true ]]; then
    set -x
    return 0
  fi

  echo "Armada API apply of ${TARGET_MANIFEST}"
  curl -fsS --max-time "${APPLY_TIMEOUT}" -X POST \
    -H "X-Auth-Token: ${token}" -H "Content-Type: application/json" \
    -d "{\"hrefs\": \"deckhand+http://deckhand-int.${UCP_NAMESPACE}.svc.cluster.local:9000/api/v1.0/revisions/${revision}/rendered-documents\"}" \
    "http://127.0.0.1:18000/api/v1.0/apply?target_manifest=${TARGET_MANIFEST}" || {
    set -x
    kubectl get armadacharts -A -o wide || true
    kubectl -n "${UCP_NAMESPACE}" logs deployment/armada-api --all-containers --tail=200 || true
    return 1
  }
  set -x
  echo
  kubectl get armadacharts -A -o wide
}

# Anchor daemonsets are scheduled by these labels (see anchor.labels values):
# masters anchor on control plane nodes, workers anchor on the rest. The
# nodes are labeled before the apply: Armada waits for the anchor pods of the
# labeled nodes only. Both labels of a control plane node are set at once,
# with kubeadm=enabled alone the workers anchor would be scheduled on it.
if [[ "${UPLOAD_ONLY}" != true ]]; then
  while read -r name _ role _; do
    if [[ "${role}" == "control-plane" ]]; then
      kubectl label node "${name}" --overwrite kubeadm=enabled kubernetes-apiserver=enabled
    else
      kubectl label node "${name}" --overwrite kubeadm=enabled
    fi
  done <<< "${NODES}"
fi

# The Airship components the Armada API apply goes through
ucp_api_available() {
  local deployment
  for deployment in keystone-api barbican-api deckhand-api armada-api; do
    kubectl -n "${UCP_NAMESPACE}" rollout status "deployment/${deployment}" --timeout=600s || return 1
  done
}

if [[ "${ARMADA_API}" == true ]]; then
  # The API request lasts until the charts are ready: the anchor drains the
  # nodes meanwhile (an upgrade restarts kubelet node by node), the pods of
  # the components the apply goes through (and their port forwarding) are
  # evicted again and again while it lasts. The apply is idempotent: retry
  # it until the timeout, once the components are available again.
  API_END=$(($(date +%s) + APPLY_TIMEOUT))
  until api_apply; do
    if [[ "$(date +%s)" -gt "${API_END}" ]]; then
      echo "Timed out applying ${TARGET_MANIFEST} with the Armada API" >&2
      exit 1
    fi
    sleep 30
    ucp_api_available || true
  done
else
  bootstrap_apply
fi
if [[ "${UPLOAD_ONLY}" == true ]]; then
  exit 0
fi

# Calico components are created by the Tigera operator after its release is
# ready
wait_exists 600 -n calico-system daemonset/calico-node
wait_exists 600 -n calico-system deployment/calico-kube-controllers
kubectl -n calico-system rollout status daemonset/calico-node --timeout=600s
kubectl -n calico-system rollout status deployment/calico-kube-controllers --timeout=600s
kubectl wait --for=condition=Ready nodes --all --timeout=300s

check_cluster_healthy
