#!/bin/bash

# This script regenerates and updates certificate YAML files
# Usage: ./update_certificates.sh <site_name>

set -e  # Exit on error

# Check for required parameters
if [ $# -ne 1 ]; then
    echo "Usage: $0 <site_name>"
    echo "Example: $0 airsloop"
    exit 1
fi

SITE_NAME="$1"



mkdir collected_certs

sudo tools/airship pegleg site -r . secrets generate certificates  ${SITE_NAME} --save-location collected_certs --regenerate-all --days 825

sudo tools/airship pegleg site -r . secrets decrypt  ${SITE_NAME} --path collected_certs --overwrite

sudo chown -R ${USER} collected_certs

cp -a collected_certs/* ./

rm -rf collected_certs/
