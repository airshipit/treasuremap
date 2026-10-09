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
# operator) and the kubeadm chart with the same values as on day 0. The
# anchor daemonsets of the kubeadm chart take over the node configuration
# and keep it in sync with the chart values.
#
# Armada is bootstrapped with static pods of this (the first control plane)
# node, as in the Airship genesis: there is no CNI before Calico is deployed
# by Armada, static pods are run by kubelet on the host network.
#   armada-artifacts - nginx serving the charts of the promenade checkout
#   armada-operator  - reconciles ArmadaChart resources (leader election, so
#                      an in-cluster operator can take over later)
#   armada-apply-*   - armada-go apply of the manifest (one-shot)
#
# Usage: 050-armada-apply.sh [<documents>]
# <documents> are rendered site documents to deploy, the rendered site by
# default. The cluster configuration is changed by deploying modified
# documents (see set-document-data.py).

set -ex

: "${INSTALL_PATH:="../"}"
: "${ARTIFACTS_PATH:="${INSTALL_PATH}/artifacts"}"
# Chart sources of the site documents (see software/config/versions.yaml)
: "${ARTIFACTS_HOST:="control-plane.minikube.internal"}"
: "${ARTIFACTS_PORT:="8282"}"
: "${ARTIFACTS_IMAGE:="quay.io/airshipit/nginx:alpine3.18"}"
: "${ARMADA_OPERATOR_CRDS:="${INSTALL_PATH}/armada-operator/config/crd/bases"}"
: "${TARGET_MANIFEST:="kubeadm-cluster"}"
: "${APPLY_TIMEOUT:="3600"}"
# Host directory of the bootstrap: charts, nginx config, documents to apply
: "${BOOTSTRAP_DIR:="/var/lib/armada-bootstrap"}"
: "${MANIFESTS_DIR:="/etc/kubernetes/manifests"}"

# shellcheck source=tools/deployment/airliner/common.sh
source ./tools/deployment/airliner/common.sh

DOCUMENTS=$(realpath "${1:-${RENDERED}}")
# static pods run on this node: mirror pods are named <pod>-<node>
NODE_NAME=$(./tools/deployment/airliner/get-site-nodes.py "${RENDERED}" local | cut -d ' ' -f 1)

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

# Charts of the promenade checkout (the same as on day 0)
if [[ ! -f "${ARTIFACTS_PATH}/kubeadm.tgz" ]]; then
  make -C "${INSTALL_PATH}/promenade" charts
  mkdir -p "${ARTIFACTS_PATH}"
  for chart in kubeadm tigera-operator; do
    cp -v "${INSTALL_PATH}/promenade/charts/${chart}"-[0-9]*.tgz "${ARTIFACTS_PATH}/${chart}.tgz"
  done
fi
sudo install -d -m 0755 "${BOOTSTRAP_DIR}/charts"
sudo install -m 0644 "${ARTIFACTS_PATH}"/*.tgz "${BOOTSTRAP_DIR}/charts/"
sudo tee "${BOOTSTRAP_DIR}/nginx.conf" > /dev/null << EOF
server {
  listen ${ARTIFACTS_PORT};
  root /usr/share/nginx/html;
}
EOF

# The chart sources are resolved on the host network (hostNetwork pods get
# /etc/hosts of the node)
if ! grep -qE "[[:space:]]${ARTIFACTS_HOST}([[:space:]]|$)" /etc/hosts; then
  echo "127.0.0.1 ${ARTIFACTS_HOST}" | sudo tee -a /etc/hosts
fi

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

for pod in armada-artifacts armada-operator; do
  wait_exists 600 -n "${NAMESPACE}" "pod/${pod}-${NODE_NAME}"
  kubectl -n "${NAMESPACE}" wait --for=condition=Ready "pod/${pod}-${NODE_NAME}" --timeout=600s
done
curl -fsSI --retry 10 --retry-all-errors --retry-delay 3 \
  "http://${ARTIFACTS_HOST}:${ARTIFACTS_PORT}/kubeadm.tgz"
kubectl apply -f "${ARMADA_OPERATOR_CRDS}"

# Anchor daemonsets are scheduled by these labels (see anchor.labels values):
# masters anchor on control plane nodes, workers anchor on the rest.
while read -r name _ role _; do
  kubectl label node "${name}" --overwrite kubeadm=enabled
  if [[ "${role}" == "control-plane" ]]; then
    kubectl label node "${name}" --overwrite kubernetes-apiserver=enabled
  fi
done <<< "${NODES}"

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

# armada-go apply creates (updates) the ArmadaChart resources of the
# manifest and waits for armada-operator to reconcile them
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

# Calico components are created by the Tigera operator after its release is
# ready
wait_exists 600 -n calico-system daemonset/calico-node
wait_exists 600 -n calico-system deployment/calico-kube-controllers
kubectl -n calico-system rollout status daemonset/calico-node --timeout=600s
kubectl -n calico-system rollout status deployment/calico-kube-controllers --timeout=600s
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Armada doesn't wait for the anchor to apply the configuration on every
# node (node by node, it takes long after the release is deployed): wait for
# it here.
wait_anchor_applied "${DOCUMENTS}"
check_cluster_healthy
