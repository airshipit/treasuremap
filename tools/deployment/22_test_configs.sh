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

export AIRSHIP_SITE_NAME=${AIRSHIP_SITE_NAME:-"test-site"}
export AIRSHIP_CONFIG_METADATA_PATH=${AIRSHIP_CONFIG_METADATA_PATH:-"treasuremap/manifests/site/$AIRSHIP_SITE_NAME/metadata.yaml"}

# Primary repo options
export AIRSHIP_CONFIG_PRIMARY_REPO_URL=${AIRSHIP_CONFIG_PRIMARY_REPO_URL:-"${TREASUREMAP_PROJECT}"}
export AIRSHIPCTL_REPO_URL=${AIRSHIPCTL_REPO_URL:-"https://opendev.org/airship/airshipctl.git"}
export TREASUREMAP_REF=${TREASUREMAP_REF:-"$(git rev-parse HEAD)"}

cd ${AIRSHIPCTL_PROJECT}
# NOTE(drewwalters96): Override $AIRSHIPCTL_REF to pin airshipctl to a specific
# git commit. Defaults to cloned version.
export AIRSHIPCTL_REF=${AIRSHIPCTL_REF:-"$(git rev-parse HEAD)"}

./tools/deployment/22_test_configs.sh

# Add the airshipctl manifest defintion
airshipctl config set-manifest treasuremap_ci \
        --repo airshipctl \
        --url "${AIRSHIPCTL_REPO_URL}" \
        --commithash "${AIRSHIPCTL_REF}"

airshipctl config set-manifest treasuremap_ci \
        --repo primary \
        --url "${AIRSHIP_CONFIG_PRIMARY_REPO_URL}" \
        --commithash "${TREASUREMAP_REF}"

airshipctl config set-context ephemeral-cluster --manifest treasuremap_ci
airshipctl config set-context target-cluster --manifest treasuremap_ci
