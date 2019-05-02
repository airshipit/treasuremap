#!/bin/bash
#
# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
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

# Credentials that can be exported to work with Shipyard.
# To set your environment variables to the values in this script, run using:
# source creds.sh
#

SHIPYARD_KEYSTONE_PASSWORD=$(awk '
## format we are looking for:
#schema: deckhand/Passphrase/v1
#metadata:
#  schema: metadata/Document/v1
#  name: ucp_shipyard_keystone_password
#  layeringDefinition:
#    abstract: false
#    layer: site
#  storagePolicy: cleartext
#data: password18
    /^schema: deckhand\/Passphrase\/v1/ {
        getline
        getline
        getline
        if ($2=="ucp_shipyard_keystone_password") {
            getline
            getline
            getline
            getline
            getline
            print $2
            exit
      }
      else {
          getline
      }
}' treasuremap.yaml)

export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_DOMAIN_NAME=default
export OS_PROJECT_NAME=service
export OS_USERNAME=shipyard
export OS_PASSWORD="${SHIPYARD_KEYSTONE_PASSWORD}"
export OS_AUTH_URL=http://keystone.ucp.svc.cluster.local:80/v3
