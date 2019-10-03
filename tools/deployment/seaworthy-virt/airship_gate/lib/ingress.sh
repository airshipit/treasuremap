#!/bin/bash

DNS_ZONE_FILE="${TEMP_DIR}/ingress.dns"
COREFILE="${TEMP_DIR}/ingress.corefile"
RESOLV_CONF="${TEMP_DIR}/resolv.conf"

ingress_dns_config() {
  ingress_domain="$(config_ingress_domain)"

  #shellcheck disable=SC2016
  INGRESS_DOMAIN="${ingress_domain}" envsubst '${INGRESS_DOMAIN}' < "${TEMPLATE_DIR}/ingress_header.sub" > "${DNS_ZONE_FILE}"

  read -r -a ingress_ip_list <<< "$(config_ingress_ips)"

  for ip in "${ingress_ip_list[@]}"
  do
    # TODO(sthussey) shift config_ingress_entries to printf w/ quotes
    # shellcheck disable=SC2046
    read -r -a ip_entries <<< $(config_ingress_entries "$ip")
    for entry in "${ip_entries[@]}"
    do
      HOSTNAME="${entry}" HOSTIP="${ip}" envsubst < "${TEMPLATE_DIR}/ingress_entry.sub" >> "${DNS_ZONE_FILE}"
    done
  done

  DNS_DOMAIN="${ingress_domain}" ZONE_FILE="$(basename "$DNS_ZONE_FILE")" DNS_SERVERS="$UPSTREAM_DNS" envsubst < "${TEMPLATE_DIR}/ingress_corefile.sub" > "${COREFILE}"
}

ingress_resolv_conf() {
  # Update node DNS settings
  touch "$RESOLV_CONF"
  for server in $UPSTREAM_DNS; do
    if ! grep "nameserver $server" "$RESOLV_CONF"; then
      echo "nameserver $server" >> "$RESOLV_CONF"
    fi
  done
}

ingress_dns_start() {
  # nodename where DNS should run
  nodename="$1"
  remote_work_dir="/var/tmp/coredns"

  remote_zone_file="${remote_work_dir}/$(basename "$DNS_ZONE_FILE")"
  remote_corefile="${remote_work_dir}/$(basename "$COREFILE")"
  remote_resolv_conf="/etc/$(basename "$RESOLV_CONF")"
  ssh_cmd "${nodename}" mkdir -p "${remote_work_dir}"
  rsync_cmd "$DNS_ZONE_FILE" "${nodename}:${remote_zone_file}"
  rsync_cmd "$COREFILE" "${nodename}:${remote_corefile}"
  rsync_cmd "$RESOLV_CONF" "${nodename}:${remote_resolv_conf}"
  ssh_cmd "${nodename}" systemctl stop systemd-resolved
  ssh_cmd "${nodename}" systemctl disable systemd-resolved
  ssh_cmd "${nodename}" docker run -d -v /var/tmp/coredns:/data -w /data --network host --restart always -P "$IMAGE_COREDNS" -conf "$(basename "$remote_corefile")"
}
