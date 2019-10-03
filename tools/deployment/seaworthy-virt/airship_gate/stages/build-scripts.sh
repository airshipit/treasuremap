#!/bin/bash

set -e

source "${GATE_UTILS}"

mkdir -p "${SCRIPT_DEPOT}"
chmod 777 "${SCRIPT_DEPOT}"

DOCKER_RUN_OPTS=("-e" "PROMENADE_DEBUG=${PROMENADE_DEBUG}")

for v in HTTPS_PROXY HTTP_PROXY NO_PROXY https_proxy http_proxy no_proxy
do
  if [[ -v "${v}" ]]
  then
    DOCKER_RUN_OPTS+=("-e" "${v}=${!v}")
  fi
done

CERTS_PATH="/certs/*.yaml"
KEYS_PATH="/gate/*.yaml"
if [[ -n "${USE_EXISTING_SECRETS}" ]]
then
    CERTS_PATH=""
    KEYS_PATH=""
fi

PROMENADE_TMP_LOCAL="$(basename "$PROMENADE_TMP_LOCAL")"
PROMENADE_TMP="${TEMP_DIR}/${PROMENADE_TMP_LOCAL}"
mkdir -p "$PROMENADE_TMP"
chmod 777 "$PROMENADE_TMP"

log Prepare hyperkube
docker run --rm -t \
    --network host \
    -v "${PROMENADE_TMP}:/tmp/${PROMENADE_TMP_LOCAL}" \
    "${DOCKER_RUN_OPTS[@]}" \
    "${IMAGE_HYPERKUBE}" \
        cp /hyperkube "/tmp/${PROMENADE_TMP_LOCAL}"

log Building scripts
docker run --rm -t \
    -w /config \
    --network host \
    -v "${DEFINITION_DEPOT}:/config" \
    -v "${GATE_DEPOT}:/gate" \
    -v "${CERT_DEPOT}:/certs" \
    -v "${SCRIPT_DEPOT}:/scripts" \
    -v "${PROMENADE_TMP}:/tmp/${PROMENADE_TMP_LOCAL}" \
    -e "PROMENADE_ENCRYPTION_KEY=${PROMENADE_ENCRYPTION_KEY}" \
    "${DOCKER_RUN_OPTS[@]}" \
    "${IMAGE_PROMENADE_CLI}" \
        promenade \
            build-all \
                --validators \
                -o /scripts \
                /config/*.yaml "${CERTS_PATH}" "${KEYS_PATH}"
