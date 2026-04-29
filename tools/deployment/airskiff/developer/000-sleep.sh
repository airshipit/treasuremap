#!/bin/bash

set -ex

: "${ENABLE_SLEEP:=false}"

ENABLE_SLEEP=$(echo "${ENABLE_SLEEP}" | tr '[:upper:]' '[:lower:]')

if [[ "${ENABLE_SLEEP}" == "true" ]]; then
    while true; do
        echo "Sleeping for 100 seconds..."
        sleep 100
    done
fi