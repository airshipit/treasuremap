#!/bin/bash

install_ingress_ca() {
  ingress_ca=$(config_ingress_ca)
  if [[ -z "$ingress_ca" ]]
  then
    echo "Not installing ingress root CA."
    return
  fi
  local_file="${TEMP_DIR}/ingress_ca.pem"
  remote_file="${BUILD_WORK_DIR}/ingress_ca.pem"
  cat <<< "$ingress_ca" > "$local_file"
  rsync_cmd "$local_file" "${BUILD_NAME}":"$remote_file"
}

shipard_cmd_stdout() {
  # needed to reach airship endpoints
  dns_netspec="$(config_netspec_for_role "dns")"
  dns_server=$(config_vm_net_ip "${BUILD_NAME}" "$dns_netspec")
  install_ingress_ca
  ssh_cmd "${BUILD_NAME}" \
    docker run -t --network=host \
    --dns "${dns_server}" \
    -v "${BUILD_WORK_DIR}:/work" \
    -e OS_AUTH_URL="${AIRSHIP_KEYSTONE_URL}" \
    -e OS_USERNAME=shipyard \
    -e OS_USER_DOMAIN_NAME=default \
    -e OS_PASSWORD="${SHIPYARD_PASSWORD}" \
    -e OS_PROJECT_DOMAIN_NAME=default \
    -e OS_PROJECT_NAME=service \
    -e REQUESTS_CA_BUNDLE=/work/ingress_ca.pem \
    --entrypoint /usr/local/bin/shipyard "${IMAGE_SHIPYARD_CLI}" "$@" 2>&1
}

shipyard_cmd() {
  if [[ ! -z "${LOG_FILE}" ]]
  then
    set -o pipefail
    shipard_cmd_stdout "$@" | tee -a "${LOG_FILE}"
    set +o pipefail
  else
    shipard_cmd_stdout "$@"
  fi
}

drydock_cmd_stdout() {
  dns_netspec="$(config_netspec_for_role "dns")"
  dns_server="$(config_vm_net_ip "${BUILD_NAME}" "$dns_netspec")"
  install_ingress_ca
  ssh_cmd "${BUILD_NAME}" \
    docker run -t --network=host \
    --dns "${dns_server}" \
    -v "${BUILD_WORK_DIR}:/work" \
    -e DD_URL=http://drydock-api.ucp.svc.cluster.local:9000 \
    -e OS_AUTH_URL="${AIRSHIP_KEYSTONE_URL}" \
    -e OS_USERNAME=shipyard \
    -e OS_USER_DOMAIN_NAME=default \
    -e OS_PASSWORD="${SHIPYARD_PASSWORD}" \
    -e OS_PROJECT_DOMAIN_NAME=default \
    -e OS_PROJECT_NAME=service \
    -e REQUESTS_CA_BUNDLE=/work/ingress_ca.pem \
    --entrypoint /usr/local/bin/drydock "${IMAGE_DRYDOCK_CLI}" "$@" 2>&1
}
drydock_cmd() {
  if [[ ! -z "${LOG_FILE}" ]]
  then
    set -o pipefail
    drydock_cmd_stdout "$@" | tee -a "${LOG_FILE}"
    set +o pipefail
  else
    drydock_cmd_stdout "$@"
  fi
}

# Create a shipyard action
# and poll until completion
shipyard_action_wait() {
  action="$1"
  timeout="${2:-3600}"
  poll_time="${3:-60}"

  if [[ $action == "update_site" ]]
  then
    options="--allow-intermediate-commits"
  else
    options=""
  fi

  end_time=$(date -d "+${timeout} seconds" +%s)

  log "Starting Shipyard action ${action}, will timeout in ${timeout} seconds."

  ACTION_ID=$(shipyard_cmd create action ${options} "${action}")
  ACTION_ID=$(echo "${ACTION_ID}" | grep -oE 'action/[0-9A-Z]+')

  echo "Action ${ACTION_ID} has been created."

  while true;
  do
    if [[ $(date +%s) -ge ${end_time} ]]
    then
      log "Shipyard action ${action} did not complete in ${timeout} seconds."
      ACTION=$(shipyard_cmd describe "${ACTION_ID}")
      log "${ACTION}"
      return 2
    fi

    ACTION_STATUS=$(shipyard_cmd describe "${ACTION_ID}" | grep -i "Lifecycle" | \
            awk '{print $2}')

    ACTION_STEPS=$(shipyard_cmd describe "${ACTION_ID}" | grep -i "step/" | \
            awk '{print $3}')

    # Verify lifecycle status
    if [ "${ACTION_STATUS}" == "Failed" ]; then
            echo -e "\n${ACTION_ID} FAILED\n"
            shipyard_cmd describe "${ACTION_ID}"
            exit 1
    fi

    if [ "${ACTION_STATUS}" == "Complete" ]; then
            # Verify status of each action step
            for step in ${ACTION_STEPS}; do
              if [ "${step}" == "failed" ]; then
                echo -e "\n${ACTION_ID} FAILED\n"
                shipyard_cmd describe "${ACTION_ID}"
                exit 1
              fi
            done

            echo -e "\n${ACTION_ID} completed SUCCESSFULLY\n"
            shipyard_cmd describe "${ACTION_ID}"
            exit 0
    fi

    log "$(shipyard_cmd describe "${ACTION_ID}")"
    sleep "${poll_time}"
  done
}

# Re-use the ssh key from ssh-config
# for MAAS-deployed nodes
collect_ssh_key() {
  mkdir -p "${GATE_DEPOT}"
  if [[ ! -r ${SSH_CONFIG_DIR}/id_rsa.pub ]]
  then
    ssh_keypair_declare
  fi

  if [[ -n "${USE_EXISTING_SECRETS}" ]]; then
      log "Using existing manifests for secrets"
      return 0
  fi

  cat << EOF > "${GATE_DEPOT}/airship_ubuntu_ssh_key.yaml"
---
schema: deckhand/Certificate/v1
metadata:
  schema: metadata/Document/v1
  name: ubuntu_ssh_key
  layeringDefinition:
    layer: site
    abstract: false
  storagePolicy: cleartext
data: |-
EOF
   sed -e 's/^/  /' >> "${GATE_DEPOT}/airship_ubuntu_ssh_key.yaml" < "${SSH_CONFIG_DIR}/id_rsa.pub"
}

