#!/bin/bash

# Copyright 2019 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -xe

INSTALL_PREFIX=$1
INSTALL_PREFIX=${INSTALL_PREFIX:-'/tmp/kubeval'}
KUBEVAL_URL=https://github.com/instrumenta/kubeval/releases/download
KUBEVAL_VER=${KUBEVAL_VER:-'0.14.0'}
URL="${KUBEVAL_URL}/${KUBEVAL_VER}/kubeval-linux-amd64.tar.gz"

TMP=$(mktemp -d)
pushd $TMP
curl -fL $URL | tar -xz
install -D -t ${INSTALL_PREFIX}/bin kubeval
popd
rm -rf $TMP
