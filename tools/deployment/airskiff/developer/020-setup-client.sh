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

# Install OpenStack client and create OpenStack client configuration file.

sudo -H mkdir -p /etc/openstack
sudo -H chown -R "$(id -un)": /etc/openstack
tee /etc/openstack/clouds.yaml << EOF
clouds:
  airship:
    region_name: RegionOne
    identity_api_version: 3
    auth:
      username: 'admin'
      password: 'password123'
      project_name: 'admin'
      project_domain_name: 'default'
      user_domain_name: 'default'
      auth_url: 'http://keystone-api.ucp.svc.cluster.local:5000/v3'
  openstack:
    region_name: RegionOne
    identity_api_version: 3
    auth:
      username: 'admin'
      password: 'password123'
      project_name: 'admin'
      project_domain_name: 'default'
      user_domain_name: 'default'
      auth_url: 'http://keystone-api.openstack.svc.cluster.local:5000/v3'
  openstack_helm:
    region_name: RegionOne
    identity_api_version: 3
    auth:
      username: 'admin'
      password: 'password'
      project_name: 'admin'
      project_domain_name: 'default'
      user_domain_name: 'default'
      auth_url: 'http://keystone.openstack.svc.cluster.local/v3'
EOF


# Deploy docker-based openstack client
sudo tee /usr/local/bin/openstack << EOF
#!/bin/bash

docker run \
    -v /etc/openstack/clouds.yaml:/etc/openstack/clouds.yaml \
    -e OS_CLOUD=\${OS_CLOUD} \
    quay.io/airshipit/porthole-openstack-utility:latest-ubuntu_focal \
        openstack \$@
EOF
sudo chmod +x /usr/local/bin/openstack
