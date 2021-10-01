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

echo "Generating secrets using airshipctl"
FORCE_REGENERATE=all airshipctl phase run secret-update

echo "Generating ~/.airship/kubeconfig"
export EXTERNAL_KUBECONFIG=${EXTERNAL_KUBECONFIG:-""}
export SITE=${SITE:-"virtual-airship-core"}

if [[ -z "$EXTERNAL_KUBECONFIG" ]]; then
   # we want to take config from bundle - remove kubeconfig file so
   # airshipctl could regenerated it from kustomize
   [ -f "~/.airship/kubeconfig" ] && rm ~/.airship/kubeconfig
   # we need to use tmp file, because airshipctl uses it and fails
   # if we write directly
   airshipctl cluster get-kubeconfig > ~/.airship/tmp-kubeconfig
   mv ~/.airship/tmp-kubeconfig ~/.airship/kubeconfig
fi

# Validate that we generated everything correctly
decrypted1=$(airshipctl phase run secret-show)
if [[ -z "${decrypted1}" ]]; then
        echo "Got empty decrypted value"
        exit 1
fi
