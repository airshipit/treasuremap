#!/bin/bash

rsync_cmd() {
    rsync -e "ssh -F ${SSH_CONFIG_DIR}/config" "${@}"
}

ssh_cmd_raw() {
    # shellcheck disable=SC2068
    ssh -F "${SSH_CONFIG_DIR}/config" $@
}

ssh_cmd() {
    HOST=${1}
    shift
    args=$(shell-quote -- "${@}")
    if [[ -v GATE_DEBUG && ${GATE_DEBUG} = "1" ]]; then
        # shellcheck disable=SC2029
        ssh -F "${SSH_CONFIG_DIR}/config" -v "${HOST}" "${args}"
    else
        # shellcheck disable=SC2029
        ssh -F "${SSH_CONFIG_DIR}/config" "${HOST}" "${args}"
    fi
}

ssh_config_declare() {
    log Creating SSH config
    env -i \
      "SSH_CONFIG_DIR=${SSH_CONFIG_DIR}" \
      envsubst < "${TEMPLATE_DIR}/ssh-config-global.sub" > "${SSH_CONFIG_DIR}/config"
    for n in $(config_vm_names)
    do
      ssh_net="$(config_netspec_for_role "ssh")"
      env -i \
        "SSH_CONFIG_DIR=${SSH_CONFIG_DIR}" \
        "SSH_NODE_HOSTNAME=${n}" \
        "SSH_NODE_IP=$(config_vm_net_ip "${n}" "$ssh_net")" \
          envsubst < "${TEMPLATE_DIR}/ssh-config-node.sub" >> "${SSH_CONFIG_DIR}/config"
      if [[ "$(config_vm_bootstrap "${n}")" == "true" ]]
      then
        echo "    User root" >> "${SSH_CONFIG_DIR}/config"
      else
        echo "    User ubuntu" >> "${SSH_CONFIG_DIR}/config"
      fi
    done
}

ssh_keypair_declare() {
    log Validating SSH keypair exists
    if [ ! -s "${SSH_CONFIG_DIR}/id_rsa" ]; then
        if [[ "${GATE_SSH_KEY}" ]]; then
            log "Using existing SSH keys for VMs"
            cp "${GATE_SSH_KEY}" "${SSH_CONFIG_DIR}/id_rsa"
            chmod 600 "${SSH_CONFIG_DIR}/id_rsa"

            cp "${GATE_SSH_KEY}.pub" "${SSH_CONFIG_DIR}/id_rsa.pub"
        else
            log Generating SSH keypair
            ssh-keygen -N '' -f "${SSH_CONFIG_DIR}/id_rsa" &>> "${LOG_FILE}"
        fi
    fi
}

ssh_load_pubkey() {
    cat "${SSH_CONFIG_DIR}/id_rsa.pub"
}

ssh_setup_declare() {
    mkdir -p "${SSH_CONFIG_DIR}"
    ssh_keypair_declare
    ssh_config_declare
}

ssh_wait() {
    NAME=${1}
    while ! ssh_cmd "${NAME}" /bin/true; do
        sleep 0.5
    done
}
