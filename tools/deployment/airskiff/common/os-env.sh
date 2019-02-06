#!/bin/bash
#
# Copyright 2019, AT&T Intellectual Property
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

export OS_PROJECT_DOMAIN_NAME=`grep -m 1 project_domain_name /etc/openstack/clouds.yaml | cut -d "'" -f 2`
export OS_USER_DOMAIN_NAME=`grep -m 1 user_domain_name /etc/openstack/clouds.yaml | cut -d "'" -f 2`
export OS_PROJECT_NAME=`grep -m 1 project_name /etc/openstack/clouds.yaml | cut -d "'" -f 2`
export OS_USERNAME=`grep -m 1 username /etc/openstack/clouds.yaml | cut -d "'" -f 2`
export OS_PASSWORD=`grep -m 1 password /etc/openstack/clouds.yaml | cut -d "'" -f 2`
export OS_AUTH_URL=`grep -m 1 auth_url /etc/openstack/clouds.yaml | cut -d "'" -f 2`
