#!/bin/bash

set -ex
mv tools/gate/manifests/full-site.yaml  type/skiff/manifests/full-site.yaml

python3 \
    tools/deployment/airskiff/common/generate_security_keys.py \
         --layer=type \
         --output-dir=type/skiff/secrets/passphrases/
