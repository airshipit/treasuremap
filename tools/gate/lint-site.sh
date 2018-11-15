#!/bin/bash

# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
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

: "${PEGLEG_PATH:=../airship-pegleg}"
: "${PEGLEG_IMG:=quay.io/airshipit/pegleg:b7556bd89e99f2a6539e97d5a4ac6738751b9c55}"

: "${PEGLEG:=${PEGLEG_PATH}/tools/pegleg.sh}"

# TODO(drewwalters96): make Treasuremap sites P001 and P009 compliant.
IMAGE=${PEGLEG_IMG} TERM_OPTS=" " \
  ${PEGLEG} site -r . lint "$1" -x P001 -x P009
