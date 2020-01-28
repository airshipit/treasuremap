#!/bin/bash

# Copyright 2019, AT&T Intellectual Property
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
: "${OSH_INFRA_PATH:="../openstack-helm-infra"}"

# Configure proxy settings if $PROXY is set
if [ -n "${PROXY}" ]; then
  . tools/deployment/airskiff/common/setup-proxy.sh
fi

# Deploy K8s with Minikube
cd "${OSH_INFRA_PATH}"
bash -c "./tools/deployment/common/005-deploy-k8s.sh"

kubectl label nodes --all --overwrite ucp-control-plane=enabled

# Add user to Docker group
# NOTE: This requires re-authentication. Restart your shell.
sudo adduser "$(whoami)" docker
sudo su - "$USER" -c bash <<'END_SCRIPT'
if echo $(groups) | grep -qv 'docker'; then
    echo "You need to logout to apply group permissions"
    echo "Please logout and login"
fi
END_SCRIPT

# clean up /etc/resolv.conf, if it includes a localhost dns address
sudo sed -i.bkp '/^nameserver.*127.0.0.1/d
                 w /dev/stdout' /etc/resolv.conf

cd "${CURRENT_DIR}"
