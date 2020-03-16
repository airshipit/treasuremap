#!/bin/bash
img_base_declare() {
    log Validating base image exists
    if ! virsh vol-key --pool "${VIRSH_POOL}" --vol airship-gate-base.img > /dev/null; then
        log Installing base image from "${BASE_IMAGE_URL}"

        cd "${TEMP_DIR}"
        curl -q -L -o base.img "${BASE_IMAGE_URL}"

        {
            virsh vol-create-as \
                --pool "${VIRSH_POOL}" \
                --name airship-gate-base.img \
                --format qcow2 \
                --capacity "${BASE_IMAGE_SIZE}" \
                --prealloc-metadata
            virsh vol-upload \
                --vol airship-gate-base.img \
                --file base.img \
                --pool "${VIRSH_POOL}"
        } &>> "${LOG_FILE}"
    fi
}

netconfig_gen_mtu() {
    MTU="$1"

    set +e
    IFS= read -r -d '' MTU_TMP <<'EOF'
    mtu: ${MTU}
EOF
    set -e

    MTU="$MTU" envsubst <<< "$MTU_TMP" >> network-config
}

netconfig_gen_physical() {
    IFACE_NAME="$1"
    MTU="$2"

    set +e
    IFS= read -r -d '' PHYS_TMP <<'EOF'
  - type: physical
    name: ${IFACE_NAME}
EOF
    set -e

    IFACE_NAME="$IFACE_NAME" envsubst <<< "$PHYS_TMP" >> network-config

    if [ ! -z "$MTU" ]
    then
       netconfig_gen_mtu "$MTU"
    fi
}

netconfig_gen_subnet() {
    IP_ADDR="$1"
    IP_MASK="$2"
    GW_ADDR="$3"

    set +e
    IFS= read -r -d '' SUBNET_TMP <<'EOF'
    subnets:
      - type: static
        address: ${IP_ADDR}
        netmask: ${IP_MASK}
EOF

    IFS= read -r -d '' SUBNET_GW_TMP <<'EOF'
        gateway:  ${GW_ADDR}
EOF
    set -e

    IP_ADDR="$IP_ADDR" IP_MASK="$IP_MASK" envsubst <<< "$SUBNET_TMP" >> network-config

    if [ ! -z "$GW_ADDR" ]
    then
      GW_ADDR="$GW_ADDR" envsubst <<< "$SUBNET_GW_TMP" >> network-config
    fi

}

netconfig_gen_vlan() {
    IFACE_NAME="$1"
    VLAN_TAG="$2"
    MTU="$3"

    set +e
    IFS= read -r -d '' VLAN_TMP <<'EOF'
  - type: vlan
    name: ${IFACE_NAME}.${VLAN_TAG}
    vlan_link: ${IFACE_NAME}
    vlan_id: ${VLAN_TAG}
EOF
    set -e

    IFACE_NAME="$IFACE_NAME" VLAN_TAG="$VLAN_TAG" envsubst <<< "$VLAN_TMP" >> network-config

    if [ ! -z "$MTU" ]
    then
       netconfig_gen_mtu "$MTU"
    fi

}

netconfig_gen_nameservers() {
    NAMESERVERS="$1"

    set +e
    IFS= read -r -d '' NS_TMP <<'EOF'
  - type: nameserver
    address: [${DNS_SERVERS}]
EOF
    set -e

    DNS_SERVERS="$NAMESERVERS" envsubst <<< "$NS_TMP" >> network-config
}

netconfig_gen() {
    NAME="$1"

    IFS= cat << 'EOF' > network-config
version: 1
config:
EOF

    # Generate physical interfaces
    for iface in $(config_vm_iface_list "$NAME")
    do
       iface_network=$(config_vm_iface_network "$NAME" "$iface")
       netconfig_gen_physical "$iface" "$(config_net_mtu "$iface_network")"

       if [ "$(config_net_is_layer3 "$iface_network")" == "true" ]
       then
           iface_ip="$(config_vm_net_ip "$NAME" "$iface_network")"
           netmask="$(cidr_to_netmask "$(config_net_cidr "$iface_network")")"
           net_gw="$(config_net_gateway "$iface_network")"
           netconfig_gen_subnet "$iface_ip" "$netmask" "$net_gw"
       else
           if [ ! -z "$(config_vm_iface_vlans "$NAME" "$iface")" ]
           then
               for vlan in $(config_vm_iface_vlans "$NAME" "$iface")
               do
                   netconfig_gen_vlan "$iface" "$vlan" "$(config_net_mtu "$iface_network" "$vlan")"
                   if [ "$(config_net_is_layer3 "$iface_network" "$vlan")" == "true" ]
                   then
                     iface_ip="$(config_vm_net_ip "$NAME" "$iface_network" "$vlan")"
                     netmask="$(cidr_to_netmask "$(config_net_cidr "$iface_network" "$vlan")")"
                     net_gw="$(config_net_gateway "$iface_network" "$vlan")"
                     netconfig_gen_subnet "$iface_ip" "$netmask" "$net_gw"
                   fi
               done
           fi
       fi
    done

    DNS_SERVERS=$(echo "$UPSTREAM_DNS" | tr ' ' ',')
    netconfig_gen_nameservers "$DNS_SERVERS"

    sed -i -e '/^$/d' network-config
}

iso_gen() {
    NAME=${1}
    ADDL_USERDATA="${2}"
    disk_layout="$(config_vm_disk_layout "$NAME")"
    vm_disks="$(config_disk_list "$disk_layout")"

    if virsh vol-key --pool "${VIRSH_POOL}" --vol "cloud-init-${NAME}.iso" &> /dev/null; then
        log Removing existing cloud-init ISO for "${NAME}"
        virsh vol-delete \
            --pool "${VIRSH_POOL}" \
            --vol "cloud-init-${NAME}.iso" &>> "${LOG_FILE}"
    fi

    log "Creating cloud-init ISO for ${NAME}"
    ISO_DIR=${TEMP_DIR}/iso/${NAME}
    mkdir -p "${ISO_DIR}"
    cd "${ISO_DIR}"

    netconfig_gen "$NAME"

    SSH_PUBLIC_KEY=$(ssh_load_pubkey)

    export NAME
    export SSH_PUBLIC_KEY
    NTP_POOLS="$(join_array ',' "$NTP_POOLS")"
    export NTP_POOLS
    NTP_SERVERS="$(join_array ',' "$NTP_SERVERS")"
    export NTP_SERVERS
    envsubst < "${TEMPLATE_DIR}/user-data.sub" > user-data

    fs_header="false"
    for disk in $vm_disks
    do
      disk_format="$(config_disk_format "$disk_layout" "$disk")"
      if [[ ! -z "$disk_format" ]]
      then
        if [[ "$fs_header" = "false" ]]
        then
          echo "fs_header:" >> user-data
          fs_header="true"
        fi
        FS_TYPE="$(config_format_type "$disk_format")" DISK_DEVICE="$disk" envsubst < "${TEMPLATE_DIR}/disk-data.sub" >> user-data
      fi
    done

    echo >> user-data

    mount_header="false"
    for disk in $vm_disks
    do
      disk_format="$(config_disk_format "$disk_layout" "$disk")"
      if [[ ! -z "$disk_format" ]]
      then
        if [[ "$mount_header" = "false" ]]
        then
          echo "mounts:" >> user-data
          mount_header="true"
        fi

        MOUNTPOINT="$(config_format_mount "$disk_format")" DISK_DEVICE="$disk" envsubst < "${TEMPLATE_DIR}/mount-data.sub" >> user-data
      fi
    done

    echo >> user-data

    if [[ ! -z "${ADDL_USERDATA}" ]]
    then
      echo -e "${ADDL_USERDATA}" >> user-data
    fi

    envsubst < "${TEMPLATE_DIR}/meta-data.sub" > meta-data

    {
        genisoimage \
            -V cidata \
            -input-charset utf-8 \
            -joliet \
            -rock \
            -o cidata.iso \
                meta-data \
                network-config \
                user-data

        virsh vol-create-as \
            --pool "${VIRSH_POOL}" \
            --name "cloud-init-${NAME}.iso" \
            --capacity "$(stat -c %s "${ISO_DIR}/cidata.iso")" \
            --format raw

        virsh vol-upload \
            --pool "${VIRSH_POOL}" \
            --vol "cloud-init-${NAME}.iso" \
            --file "${ISO_DIR}/cidata.iso"
    } &>> "${LOG_FILE}"
}

iso_path() {
    NAME=${1}
    echo "${TEMP_DIR}/iso/${NAME}/cidata.iso"
}

net_list() {
  namekey="$1"
  if [[ -z "$namekey" ]]
  then
    grepargs=("-v" '^$')
  else
    grepargs=("^${namekey}")
  fi

  virsh net-list --name | grep "${grepargs[@]}"
}

nets_clean() {
    namekey=$(get_namekey)

    for netname in $(net_list "$namekey")
    do
      log Destroying Airship gate "$netname"

      for iface in $(ip -oneline l show type vlan | grep "$netname" | awk -F ' ' '{print $2}' | tr -d ':' | awk -F '@' '{print $1}')
      do
        # shellcheck disable=SC2024
        sudo ip l del dev "$iface" &>> "$LOG_FILE"
      done
      virsh net-destroy "$netname" &>> "${LOG_FILE}"
      virsh net-undefine "$netname" &>> "${LOG_FILE}"
    done
}

net_create() {
  netname="$1"
  namekey=$(get_namekey)
  virsh_netname="${namekey}"_"${netname}"

  if [[ $(config_net_is_layer3 "$net") == "true" ]]; then
    net_template="${TEMPLATE_DIR}/l3network-definition.sub"

    NETNAME="${virsh_netname}" NETIP="$(config_net_selfip "$netname")" NETMASK="$(cidr_to_netmask "$(config_net_cidr "$netname")")" NETMAC="$(config_net_mac "$netname")" envsubst < "$net_template" > "${TEMP_DIR}/net-${netname}.xml"
  else
    net_template="${TEMPLATE_DIR}/l2network-definition.sub"

    NETNAME="${virsh_netname}" envsubst < "$net_template" > "${TEMP_DIR}/net-${netname}.xml"
  fi

  log Creating network "${namekey}"_"${netname}"

  virsh net-define "${TEMP_DIR}/net-${netname}.xml" &>> "${LOG_FILE}"
  virsh net-start "${virsh_netname}"
  virsh net-autostart "${virsh_netname}"

  for vlan in $(config_net_vlan_list "$netname")
  do
    if [[ $(config_net_is_layer3 "$netname") == "true" ]]
    then
      iface_name="${virsh_netname}-${vlan}"
      iface_mtu=$(confg_net_mtu "$netname" "$vlan")
      if [[ -z "$iface_mtu" ]]
      then
        iface_mtu="1500"
      fi
      iface_mac="$(config_net_mac "$netname" "$vlan")"
      sudo ip link add link "${virsh_netname}" name "${iface_name}" type vlan id "${vlan}" mtu $iface_mtu address "$iface_mac"
      sudo ip addr add "$(config_net_selfip_cidr "$netname" "$vlan")" dev "${iface_name}"
      sudo ip link set dev "${iface_name}" up
    fi
  done
}

nets_declare() {
    nets_clean

    for net in $(config_net_list); do
      net_create "$net"
    done
}

pool_declare() {
    log Validating virsh pool setup
    if ! virsh pool-uuid "${VIRSH_POOL}" &> /dev/null; then
        log Creating pool "${VIRSH_POOL}"
        virsh pool-define-as --name "${VIRSH_POOL}" --type dir --target "${VIRSH_POOL_PATH}" &>> "${LOG_FILE}"
        virsh pool-start "${VIRSH_POOL}"
        virsh pool-autostart "${VIRSH_POOL}"
    fi
}

vm_clean() {
    NAME=${1}
    if virsh list --name | grep "${NAME}" &> /dev/null; then
        virsh destroy "${NAME}" &>> "${LOG_FILE}"
    fi

    if virsh list --name --all | grep "${NAME}" &> /dev/null; then
        log Removing VM "${NAME}"
        virsh undefine --remove-all-storage --domain "${NAME}" &>> "${LOG_FILE}"
    fi
}

vm_clean_all() {
    log Removing all VMs
    VM_NAMES=($(config_vm_names))
    for NAME in ${VM_NAMES[*]}
    do
        vm_clean "${NAME}"
    done
    wait
}

# TODO(sh8121att) - Sort out how to ensure the proper NIC
# is used for PXE boot
vm_render_interface() {
  vm="$1"
  iface="$2"

  namekey="$(get_namekey)"

  mac="$(config_vm_iface_mac "$vm" "$iface")"
  model="$(config_vm_iface_model "$vm" "$iface")"
  network="$(config_vm_iface_network "$vm" "$iface")"
  network="${namekey}_${network}"
  slot="$(config_vm_iface_slot "$vm" "$iface")"
  port="$(config_vm_iface_port "$vm" "$iface")"

  config_string="model=${model},network=${network}"

  if [[ ! -z "$mac" ]]
  then
    config_string="${config_string},mac=${mac}"
  fi

  if [[ ! -z "$slot" ]]
  then
    config_string="${config_string},address.type=pci,address.slot=${slot}"
    if [[ ! -z "$port" ]]
    then
      config_string="${config_string},address.function=${port}"
    fi

  fi


  echo -n "$config_string"
}

vm_create_interfaces() {
  vm="$1"

  network_opts=""
  for interface in $(config_vm_iface_list "$vm")
  do
    nic_opts="$(vm_render_interface "$vm" "$interface")"
    network_opts="$network_opts --network ${nic_opts}"
  done

  echo "$network_opts"
}

vm_create_vols(){
    NAME="$1"
    disk_layout="$(config_vm_disk_layout "$NAME")"
    vm_disks="$(config_disk_list "$disk_layout")"
    bs_disk="$(config_layout_bootstrap "$disk_layout")"
    bs_vm="$(config_vm_bootstrap "${NAME}")"

    vols=()
    for disk in $vm_disks
    do
      io_prof=$(config_disk_ioprofile "${disk_layout}" "${disk}")
      size=$(config_disk_size "${disk_layout}" "${disk}")

      if [[ "$bs_vm" = "true" && "$bs_disk" = "$disk" ]]
      then
        vol_create_disk "$NAME" "$disk" "$size" "true"
      else
        vol_create_disk "$NAME" "$disk" "$size"
      fi

      if [[ "$io_prof" == "fast" ]]
      then
        DISK_OPTS="bus=virtio,cache=none,format=qcow2,io=native"
      elif [[ "$io_prof" == "safe" ]]
      then
        DISK_OPTS="bus=virtio,cache=directsync,discard=unmap,format=qcow2,io=native"
      elif [[ "$io_prof" == "unsafe" ]]
      then
        DISK_OPTS="bus=virtio,cache=unsafe,format=qcow2"
      else
        DISK_OPTS="bus=virtio,format=qcow2"
      fi

      vol_cmd="--disk vol=${VIRSH_POOL}/airship-gate-${NAME}-${disk}.img,target=${disk},size=${size},${DISK_OPTS}"
      vols+=($vol_cmd)
    done

    echo "${vols[@]}"
}

vol_create_disk() {
    NAME=${1}
    DISK=${2}
    SIZE=${3}
    BS=${4}

    if virsh vol-list --pool "${VIRSH_POOL}" | grep "airship-gate-${NAME}-${DISK}.img" &> /dev/null; then
        log Deleting previous volume "airship-gate-${NAME}-${DISK}.img"
        virsh vol-delete --pool "${VIRSH_POOL}" "airship-gate-${NAME}-${DISK}.img" &>> "${LOG_FILE}"
    fi

    log Creating volume "${DISK}" for "${NAME}"
    if [[ "$BS" == "true" ]]; then
        virsh vol-create-as \
            --pool "${VIRSH_POOL}" \
            --name "airship-gate-${NAME}-${DISK}.img" \
            --capacity "${SIZE}"G \
            --format qcow2 \
            --backing-vol 'airship-gate-base.img' \
            --backing-vol-format qcow2 &>> "${LOG_FILE}"
    else
        virsh vol-create-as \
            --pool "${VIRSH_POOL}" \
            --name "airship-gate-${NAME}-${DISK}.img" \
            --capacity "${SIZE}"G \
            --format qcow2 &>> "${LOG_FILE}"
    fi
}

vm_create() {
    NAME=${1}
    DISK_OPTS="$(vm_create_vols "${NAME}")"
    NETWORK_OPTS="$(vm_create_interfaces "${NAME}")"

    if [[ "$(config_vm_bootstrap "${NAME}")" == "true" ]]; then
        iso_gen "${NAME}" "$(config_vm_userdata "${NAME}")"
        wait

        log Creating VM "${NAME}" and bootstrapping the boot drive
        # shellcheck disable=SC2086
        virt-install \
            --name "${NAME}" \
            --os-variant ubuntu16.04 \
            --virt-type kvm \
            --cpu "$(config_vm_cpu "${NAME}")" \
            --serial "file,path=${TEMP_DIR}/console/${NAME}.log" \
            --graphics vnc,listen=0.0.0.0 \
            --noautoconsole \
            $NETWORK_OPTS \
            --vcpus "$(config_vm_vcpus "${NAME}")" \
            --memory "$(config_vm_memory "${NAME}")" \
            --import \
            $DISK_OPTS \
            --disk "vol=${VIRSH_POOL}/cloud-init-${NAME}.iso,device=cdrom" &>> "${LOG_FILE}"

        ssh_wait "${NAME}"
        ssh_cmd "${NAME}" cloud-init status --wait
        ssh_cmd "${NAME}" sync

    else
        log Creating VM "${NAME}"
        # shellcheck disable=SC2086
        virt-install \
            --name "${NAME}" \
            --os-variant ubuntu16.04 \
            --virt-type kvm \
            --cpu "$(config_vm_cpu "${NAME}")" \
            --graphics vnc,listen=0.0.0.0 \
            --serial file,path="${TEMP_DIR}/console/${NAME}.log" \
            --noautoconsole \
            $NETWORK_OPTS \
            --vcpus "$(config_vm_vcpus "${NAME}")" \
            --memory "$(config_vm_memory "${NAME}")" \
            --import \
            $DISK_OPTS &>> "${LOG_FILE}"
    fi
    virsh autostart "${NAME}"
}

vm_create_validate() {
    NAME=${1}
    vm_create "${name}"
    if [[ "$(config_vm_bootstrap "${name}")" == "true" ]]
    then
      vm_validate "${name}"
    fi
}

vm_create_all() {
    log Starting all VMs

    VM_NAMES=($(config_vm_names))
    for name in ${VM_NAMES[*]}
    do
      vm_create_validate "${name}" &
    done
    wait
}

vm_start() {
    NAME=${1}
    log Starting VM "${NAME}"
    virsh start "${NAME}" &>> "${LOG_FILE}"
    ssh_wait "${NAME}"
}

vm_stop() {
    NAME=${1}
    log Stopping VM "${NAME}"
    virsh destroy "${NAME}" &>> "${LOG_FILE}"
}

vm_stop_non_genesis() {
    log Stopping all non-genesis VMs in parallel
    for NAME in $(config_non_genesis_vms); do
        vm_stop "${NAME}" &
    done
    wait
}

vm_restart_all() {
    for NAME in $(config_vm_names); do
        vm_stop "${NAME}" &
    done
    wait

    for NAME in $(config_vm_names); do
        vm_start "${NAME}" &
    done
    wait
}

vm_validate() {
    NAME=${1}
    if ! virsh list --name | grep "${NAME}" &> /dev/null; then
        log VM "${NAME}" did not start correctly.
        exit 1
    fi
}

#Find the correct group name for libvirt access
get_libvirt_group() {
    grep -oE '^libvirtd?:' /etc/group | tr -d ':'
}

# Make a user 'virtmgr' if it does not exist and add it to the libvirt group
make_virtmgr_account() {
    for libvirt_group in $(get_libvirt_group)
    do
        if ! grep -qE '^virtmgr:' /etc/passwd
        then
            sudo useradd -m -s /bin/sh -g "${libvirt_group}" virtmgr
        else
            sudo usermod -g "${libvirt_group}" virtmgr
        fi
    done
}

# Generate a new keypair
gen_libvirt_key() {
    log Removing any existing virtmgr SSH keys
    sudo rm -rf ~virtmgr/.ssh
    sudo mkdir -p ~virtmgr/.ssh

    if [[ "${GATE_SSH_KEY}" ]]; then
        log "Using existing SSH keys for virtmgr"
        sudo cp "${GATE_SSH_KEY}" ~virtmgr/.ssh/airship_gate
        sudo cp "${GATE_SSH_KEY}.pub" ~virtmgr/.ssh/airship_gate.pub
    else
        log "Generating new SSH keypair for virtmgr"
        #shellcheck disable=SC2024
        sudo ssh-keygen -N '' -b 2048 -t rsa -f ~virtmgr/.ssh/airship_gate &>> "${LOG_FILE}"
    fi
}

# Install private key into site definition
install_libvirt_key() {
    PUB_KEY=$(sudo cat ~virtmgr/.ssh/airship_gate.pub)
    export PUB_KEY

    mkdir -p "${TEMP_DIR}/tmp"
    envsubst < "${TEMPLATE_DIR}/authorized_keys.sub" > "${TEMP_DIR}/tmp/virtmgr.authorized_keys"
    sudo cp "${TEMP_DIR}/tmp/virtmgr.authorized_keys" ~virtmgr/.ssh/authorized_keys
    sudo chown -R virtmgr ~virtmgr/.ssh
    sudo chmod 700 ~virtmgr/.ssh
    sudo chmod 600 ~virtmgr/.ssh/authorized_keys

    if [[ -n "${USE_EXISTING_SECRETS}" ]]; then
        log "Using existing manifests for secrets"
        return 0
    fi

    mkdir -p "${GATE_DEPOT}"
    cat << EOF > "${GATE_DEPOT}/airship_drydock_kvm_ssh_key.yaml"
---
schema: deckhand/CertificateKey/v1
metadata:
  schema: metadata/Document/v1
  name: airship_drydock_kvm_ssh_key
  layeringDefinition:
    layer: site
    abstract: false
  storagePolicy: cleartext
data: |-
EOF
    sudo cat ~virtmgr/.ssh/airship_gate | sed -e 's/^/  /' >> "${GATE_DEPOT}/airship_drydock_kvm_ssh_key.yaml"
}
