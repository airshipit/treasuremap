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

# Check out a promenade ref (e.g. an unmerged Gerrit change) to test the
# kubeadm chart from it: ./005-checkout-promenade-ref.sh refs/changes/NN/NNNNNNN/N
# Does nothing if no ref is given.

set -ex

: "${INSTALL_PATH:="../"}"
: "${PROMENADE_REPO:="https://review.opendev.org/airship/promenade"}"
PROMENADE_REF="${1:-${PROMENADE_REF:-}}"

if [[ -z "${PROMENADE_REF}" ]]; then
  exit 0
fi

if [[ ! -d "${INSTALL_PATH}/promenade" ]]; then
  git clone "${PROMENADE_REPO}" "${INSTALL_PATH}/promenade"
fi

git -C "${INSTALL_PATH}/promenade" fetch "${PROMENADE_REPO}" "${PROMENADE_REF}"
git -C "${INSTALL_PATH}/promenade" checkout --detach FETCH_HEAD
git -C "${INSTALL_PATH}/promenade" log -1
