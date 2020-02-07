#!/bin/bash
# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
#
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

set -e

source "${GATE_UTILS}"

# Docker registry (cache) setup
# note: currently not used
# registry_up

# Create temp_dir structure
mkdir -p "${TEMP_DIR}/console"

# SSH setup
ssh_setup_declare

# Virsh setup
pool_declare
img_base_declare

# Make libvirtd available via SSH
make_virtmgr_account
gen_libvirt_key
