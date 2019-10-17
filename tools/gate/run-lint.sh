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

ROOT=$1
KUBEVAL_BIN=${KUBEVAL_BIN:-/tmp/kubeval/bin}
PATH=${KUBEVAL_BIN}:$PATH

EXCLUDE_DIRS=(
    '*/\.git/*'
    '*/kustomizeconfig/*'
    '*/tools/*'
)

EXCLUDE_FILES=(
    '.zuul.yaml'
    'kustomization.yaml'
)

function join { local d=$1; shift; printf '%s' "${@/#/$d}"; }

FILTER="$(join ' -not -path ' ${EXCLUDE_DIRS[*]})"
FILTER="$FILTER $(join ' -not -name ' ${EXCLUDE_FILES[*]})"
find $ROOT -type f \( -name "*\.yaml" $FILTER  \) | xargs -r kubeval
