#!/bin/bash


: "${USE_ARMADA_GO:=false}"
# Convert both values to lowercase (or uppercase)
USE_ARMADA_GO=$(echo "$USE_ARMADA_GO" | tr '[:upper:]' '[:lower:]')
export USE_ARMADA_GO

if [[ ${USE_ARMADA_GO} = true ]] ; then
    cp -a tools/gate/manifests/armada.yaml global/software/charts/ucp/armada/armada.yaml
fi
