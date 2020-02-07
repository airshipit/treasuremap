#!/bin/bash

set -e

source "${GATE_UTILS}"

DESIGN_FILES=($(find "${DEFINITION_DEPOT}" -name '*.yaml' -print0 | xargs -0 -n 1 basename | xargs -n 1 printf "/tmp/design/%s\n"))
GATE_FILES=($(find "${GATE_DEPOT}" -name '*.yaml' -print0 | xargs -0 -n 1 basename | xargs -n 1 printf "/tmp/gate/%s\n"))
mkdir -p "${CERT_DEPOT}"
chmod 777 "${CERT_DEPOT}"

if [[ -n "${USE_EXISTING_SECRETS}" ]]
then
  log Certificates already provided by manifests
  exit 0
fi

log Generating certificates
docker run --rm -t \
    -w /tmp \
    -v "${DEFINITION_DEPOT}:/tmp/design" \
    -v "${GATE_DEPOT}:/tmp/gate" \
    -v "${CERT_DEPOT}:/certs" \
    -e "PROMENADE_DEBUG=${PROMENADE_DEBUG}" \
    "${IMAGE_PROMENADE_CLI}" \
        promenade \
            generate-certs \
                -o /certs \
                "${DESIGN_FILES[@]}" "${GATE_FILES[@]}"
