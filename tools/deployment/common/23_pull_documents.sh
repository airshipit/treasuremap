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

# TODO(drewwalters96): The document pull command is not invoked from a script
# in airshipctl since it uses the -n (no checkout) option. This enables the
# Treasuremap repository to use a pinned version of airshipctl.
#
# When airshipctl removes the -n from its document pull script, that script can
# be invoked here.
airshipctl document pull --debug
