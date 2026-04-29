#!/bin/bash

set -ex

grep maas global/software/config/versions.yaml
grep sstream global/software/config/versions.yaml
grep default_image global/software/charts/ucp/drydock/maas.yaml
grep default_kernel global/software/charts/ucp/drydock/maas.yaml


cp -a tools/gate/manifests/bootstrap.yaml  type/skiff/manifests/bootstrap.yaml
cp -a tools/gate/manifests/shipyard.yaml type/skiff/charts/ucp/shipyard/shipyard.yaml
