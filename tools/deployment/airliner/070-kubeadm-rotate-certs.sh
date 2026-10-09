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

# Certificate rotation: issue a new set of certificates of the site with the
# same CAs (Pegleg), render the site and deploy it with Armada. The anchor
# delivers the new certificates to the nodes. Run 060-smoke-test.sh after it
# to check that the components serve the new certificates.

set -ex

# shellcheck source=tools/deployment/airliner/common.sh
source ./tools/deployment/airliner/common.sh

CERTS_DIR="site/${PL_SITE}/secrets/certificates"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT
chmod 0700 "${WORK_DIR}"
cp "${RENDERED}" "${WORK_DIR}/old.yaml"

# All certificates except CAs (*_ca.yaml) are issued again
find "${CERTS_DIR}" -name '*_certificate.yaml' -print -delete
REGENERATE_ALL=false ./tools/update_certificates.sh "${PL_SITE}"
./tools/deployment/airliner/020-render-site.sh

# CAs are kept, the rest of the certificates are new and issued by them
fingerprint() {
  kubeadm_data "$1" "$2" | openssl x509 -noout -fingerprint -sha256
}
CAS="ca etcd_ca etcd_ca_peer front_proxy_ca"
for ca in ${CAS}; do
  test "$(fingerprint "${WORK_DIR}/old.yaml" "values.certs.${ca}.crt")" == \
    "$(fingerprint "${RENDERED}" "values.certs.${ca}.crt")"
  kubeadm_data "${RENDERED}" "values.certs.${ca}.crt" >> "${WORK_DIR}/cas.pem"
done
CERTS="admin apiserver apiserver_etcd_client apiserver_kubelet_client controller_manager
  etcd_healthcheck_client front_proxy_client scheduler"
while read -r name _ role _; do
  CERTS="${CERTS} nodes.${name}.kubelet"
  if [[ "${role}" == "control-plane" ]]; then
    CERTS="${CERTS} nodes.${name}.etcd_server nodes.${name}.etcd_peer"
  fi
done <<< "${NODES}"
for cert in ${CERTS}; do
  test "$(fingerprint "${WORK_DIR}/old.yaml" "values.certs.${cert}.crt")" != \
    "$(fingerprint "${RENDERED}" "values.certs.${cert}.crt")"
  kubeadm_data "${RENDERED}" "values.certs.${cert}.crt" | \
    openssl verify -CAfile "${WORK_DIR}/cas.pem"
done

# The anchor daemonsets are restarted by the changed certificates (their
# pod templates have a checksum of the delivered files) and sync them.
./tools/deployment/airliner/050-armada-apply.sh

# The new certificates are delivered to the nodes: serving certificates
# (060-smoke-test.sh checks the ones served by the components) and client
# certificates of the components and kubeconfigs
host_fingerprint() {
  host_exec "$1" "openssl x509 -noout -fingerprint -sha256 -in $2" | sed -e 's/^\[[^]]*\] //'
}
check_host_cert() {
  local host="$1" file="$2" path="$3"
  test "$(host_fingerprint "${host}" "${file}")" == "$(fingerprint "${RENDERED}" "${path}")"
}
while read -r name _ role _; do
  check_host_cert "${name}" /etc/kubernetes/pki/kubelet.pem "values.certs.nodes.${name}.kubelet.crt"
  [[ "${role}" == "control-plane" ]] || continue
  while read -r file path; do
    check_host_cert "${name}" "${file}" "${path}"
  done << EOF_CERTS
/etc/kubernetes/pki/apiserver.crt values.certs.apiserver.crt
/etc/kubernetes/pki/apiserver-etcd-client.crt values.certs.apiserver_etcd_client.crt
/etc/kubernetes/pki/apiserver-kubelet-client.crt values.certs.apiserver_kubelet_client.crt
/etc/kubernetes/pki/front-proxy-client.crt values.certs.front_proxy_client.crt
/etc/kubernetes/pki/controller-manager.pem values.certs.controller_manager.crt
/etc/kubernetes/pki/scheduler.pem values.certs.scheduler.crt
/etc/kubernetes/pki/etcd/server.crt values.certs.nodes.${name}.etcd_server.crt
/etc/kubernetes/pki/etcd/peer.crt values.certs.nodes.${name}.etcd_peer.crt
/etc/kubernetes/pki/etcd/healthcheck-client.crt values.certs.etcd_healthcheck_client.crt
/etc/kubernetes/admin/pki/admin.pem values.certs.admin.crt
EOF_CERTS
done <<< "${NODES}"
