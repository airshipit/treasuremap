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

# Generate site secrets which are not stored in the repository:
# passphrases and the whole Kubernetes PKI (see site/<site>/pki).

set -ex

: "${PL_SITE:="aircat"}"

python3 \
    tools/deployment/airskiff/common/generate_security_keys.py \
         --layer="site" \
         --output-dir="site/${PL_SITE}/secrets/passphrases/"

rm -rf collected_certs "site/${PL_SITE}/secrets/certificates" "site/${PL_SITE}/secrets/keypairs"
./tools/update_certificates.sh "${PL_SITE}"

ls -la "site/${PL_SITE}/secrets/certificates" "site/${PL_SITE}/secrets/keypairs"
