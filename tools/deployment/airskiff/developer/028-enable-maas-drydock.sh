#!/bin/bash

set -ex
cp -a tools/gate/manifests/bootstrap.yaml  type/skiff/manifests/bootstrap.yaml
cp -a tools/gate/manifests/shipyard.yaml type/skiff/charts/ucp/shipyard/shipyard.yaml
