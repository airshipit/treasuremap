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

CURRENT_DIR="$(pwd)"
: "${INSTALL_PATH:="../"}"

# Update Pegleg versions file
sed -i -e "/\s      type:/a\        proxy_server: ${PROXY}" \
  global/software/config/versions.yaml

# Update Armada bootstrap manifest
sed -i -e "/type: git/a\    proxy_server: ${PROXY}" \
  tools/deployment/airskiff/manifests/airship.yaml

# Configure OpenStack-Helm proxy variables
cd ${INSTALL_PATH}
tee -a openstack-helm-infra/tools/gate/devel/local-vars.yaml << EOF
proxy:
  http: ${PROXY}
  https: ${PROXY}
  noproxy: localhost,127.0.0.1,172.17.0.1,.svc.cluster.local
EOF

# Add DNS nameservers present in /etc/resolv.conf to OSH playbook vars
sed -ne "s/nameserver //p" /etc/resolv.conf | while read -r ns; do
  sed -i -e "/external_dns_nameservers:/ a\      - ${ns}" \
    openstack-helm-infra/tools/images/kubeadm-aio/assets/opt/playbooks/vars.yaml
done

cd "${CURRENT_DIR}"
