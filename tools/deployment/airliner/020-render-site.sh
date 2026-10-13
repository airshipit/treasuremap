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

set -ex

: "${PEGLEG:="./tools/airship pegleg"}"
: "${PL_SITE:="airliner"}"
: "${RENDERED:="${PL_SITE}.yaml"}"
# Images to build from the checkouts of their projects (e.g. "armada-go
# deckhand"): jobs of these projects test their changes. The images are
# pushed to the image registry of the artifact repository of the site by
# 050-armada-apply.sh, the documents are rendered with them.
: "${BUILD_IMAGES:=""}"
: "${ARTIFACTS_REGISTRY:="artifacts.airship.internal:5000"}"

if [[ -n "${BUILD_IMAGES}" ]]; then
  # shellcheck disable=SC2086
  for image in ${BUILD_IMAGES}; do
    sed -i "s#quay.io/airshipit/${image}:#${ARTIFACTS_REGISTRY}/airshipit/${image}:#g" \
      global/software/config/versions.yaml site/*/software/config/versions.yaml
  done
  # for the build (050-armada-apply.sh) and the next renders
  echo "${BUILD_IMAGES}" > build-images
fi

# Lint documents
sudo ${PEGLEG} site -r . lint "${PL_SITE}" -x P001 -x P009

# Render documents
sudo ${PEGLEG} site -r . render "${PL_SITE}" -o "${RENDERED}"
sudo chown "$(id -u):$(id -g)" "${RENDERED}"
chmod 0600 "${RENDERED}"
