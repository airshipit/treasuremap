#!/usr/bin/env bash

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

set -xe

: ${CALICOCTL_VERSION:="v3.17.3"}
curl -O -L  https://github.com/projectcalico/calicoctl/releases/download/v3.17.3/calicoctl

# Install kubectl
URL="https://github.com/projectcalico"
sudo -E curl -sSLo /usr/local/bin/calicoctl \
  "${URL}"/calicoctl/releases/download/"${CALICOCTL_VERSION}"/calicoctl

sudo -E chmod +x /usr/local/bin/calicoctl
