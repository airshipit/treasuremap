#!/bin/bash

QUAGGA_DAEMONS="${TEMP_DIR}/daemons"
QUAGGA_DEBIAN_CONF="${TEMP_DIR}/debian.conf"
QUAGGA_BGPD_CONF="${TEMP_DIR}/bgpd.conf"

bgp_router_config() {
  quagga_as_number="$(config_bgp_as "quagga_as")"
  calico_as_number="$(config_bgp_as "calico_as")"
  bgp_net="$(config_netspec_for_role "bgp")"
  quagga_ip="$(config_vm_net_ip "build" "$bgp_net")"

  # shellcheck disable=SC2016
  QUAGGA_AS=${quagga_as_number} CALICO_AS=${calico_as_number} QUAGGA_IP=${quagga_ip} envsubst '${QUAGGA_AS} ${CALICO_AS} ${QUAGGA_IP}' < "${TEMPLATE_DIR}/bgpd_conf.sub" > "${QUAGGA_BGPD_CONF}"

  cp "${TEMPLATE_DIR}/daemons.sub" "${QUAGGA_DAEMONS}"
  cp "${TEMPLATE_DIR}/debian_conf.sub" "${QUAGGA_DEBIAN_CONF}"

}

bgp_router_start() {
  # nodename where BGP router should run
  nodename=$1
  remote_work_dir="/var/tmp/quagga"

  remote_daemons_file="${remote_work_dir}/$(basename "$QUAGGA_DAEMONS")"
  remote_debian_conf_file="${remote_work_dir}/$(basename "$QUAGGA_DEBIAN_CONF")"
  remote_bgpd_conf_file="${remote_work_dir}/$(basename "$QUAGGA_BGPD_CONF")"

  ssh_cmd "${nodename}" mkdir -p "${remote_work_dir}"

  rsync_cmd "$QUAGGA_DAEMONS" "${nodename}:${remote_daemons_file}"
  rsync_cmd "$QUAGGA_DEBIAN_CONF" "${nodename}:${remote_debian_conf_file}"
  rsync_cmd "$QUAGGA_BGPD_CONF" "${nodename}:${remote_bgpd_conf_file}"

  ssh_cmd "${nodename}" docker run -ti -d --net=host --privileged -v /var/tmp/quagga:/etc/quagga --restart always --name Quagga "$IMAGE_QUAGGA"
}
