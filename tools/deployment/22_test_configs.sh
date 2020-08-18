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

: ${AIRSHIPCTL_PROJECT:="../airshipctl"}
: ${TREASUREMAP_PROJECT:="$(pwd)"}

export AIRSHIPCTL_WS=${AIRSHIPCTL_WS:-$AIRSHIPCTL_PROJECT}
export AIRSHIP_CONFIG_MANIFEST_DIRECTORY=${AIRSHIP_CONFIG_MANIFEST_DIRECTORY:-$TREASUREMAP_PROJECT}
export AIRSHIP_SITE_NAME=${AIRSHIP_SITE_NAME:-"manifests/site/test-site"}

cd ${AIRSHIPCTL_PROJECT}
./tools/deployment/22_test_configs.sh

# TODO: may not need/want this since treasuremap repo is already present,
# and branch checkout seems not to be working anyway for some reason?

# Add the manifest defintion for Treasuremap
#airshipctl config set-manifest dummy_manifest \
#    --repo treasuremap \
#    --url https://opendev.org/airship/treasuremap \
#    --branch v2 \
#    --primary

