#!/bin/bash
#
# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

###############################################################################
#                                                                             #
# Set up and deploy an Airship environment for demonstration purposes.        #
# Many of the defaults and sources used here are NOT production ready, and    #
# this should not be used as a copy/paste source for any production use.      #
#                                                                             #
###############################################################################

AIAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

usage ()
{
  echo "Usage: $(basename $0) {-y|-h}" 1>&2
  echo "       -y                     don't ask questions, trust autodetection" 1>&2
  echo "       -h                     this help" 1>&2
}
# See how we were called.
case "$1" in
  ""     ) ;;
  "-y"   ) ASSUME_YES=1;;
  "-h"|* ) usage; exit 1;;
esac

echo ""
echo "Welcome to Airship in a Bottle"
echo ""
echo " /--------------------\\"
echo "|                      \\"
echo "|        |---|          \\----"
echo "|        | x |                \\"
echo "|        |---|                 |"
echo "|          |                  /"
echo "|     \____|____/       /----"
echo "|                      /"
echo " \--------------------/"
echo ""
echo ""
echo "A prototype example of deploying the Airship suite on a single VM."
echo ""
sleep 1
echo ""
echo "This example will run through:"
echo " - Setup"
echo " - Genesis of Airship (Kubernetes)"
echo " - Basic deployment of Openstack (including Nova, Neutron, and Horizon using Openstack Helm)"
echo " - VM creation automation using Heat"
echo ""
echo "The expected runtime of this script is greater than 1 hour"
echo ""
sleep 1
echo ""
echo "The minimum recommended size of the Ubuntu 16.04 VM is 4 vCPUs, 20GB of RAM with 32GB disk space."
CPU_COUNT=$(grep -c processor /proc/cpuinfo)
RAM_TOTAL=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
# Blindly assume that all storage on this VM is under root FS
DISK_SIZE=$(df --output=source,size / | awk '/dev/ {print $2}')
source /etc/os-release
if [[ $CPU_COUNT -lt 4 || $RAM_TOTAL -lt 20000000 || $DISK_SIZE -lt 30000000 || $NAME != "Ubuntu" || $VERSION_ID != "16.04" ]]; then
  echo "Error: minimum VM recommendations are not met. Exiting."
  exit 1
fi
if [[ $(id -u) -ne 0 ]]; then
  echo "Please execute this script as root!"
  exit 1
fi
sleep 1
echo "Let's collect some information about your VM to get started."
sleep 1

# IP and Hostname setup
get_local_ip ()
{
  ip addr | awk "/inet/ && /${HOST_IFACE}/{sub(/\/.*$/,\"\",\$2); print \$2}"
}
HOST_IFACE=$(ip route | grep "^default" | head -1 | awk '{ print $5 }')
LOCAL_IP=$(get_local_ip)

if [[ $ASSUME_YES -ne 1 ]]; then
  read -p "Is your HOST IFACE $HOST_IFACE? (Y/n) " YN_HI
  if [[ ! "$YN_HI" =~ ^([yY]|"")$ ]]; then
    read -p "What is your HOST IFACE? " HOST_IFACE
  fi
  LOCAL_IP=$(get_local_ip)

  read -p "Is your LOCAL IP $LOCAL_IP? (Y/n) " YN_IP
  if [[ ! "$YN_IP" =~ ^([yY]|"")$ ]]; then
    read -p "What is your LOCAL IP? " LOCAL_IP
  fi
fi

# Shells out to get the hostname for the single-node deployment to avoid some
# config conflicts
set -x
export SHORT_HOSTNAME=$(hostname -s)
set +x

# Updates the /etc/hosts file
HOSTS="${LOCAL_IP} ${SHORT_HOSTNAME}"
HOSTS_REGEX="${LOCAL_IP}.*${SHORT_HOSTNAME}"
if grep -q "$HOSTS_REGEX" "/etc/hosts"; then
  echo "Not updating /etc/hosts, entry ${HOSTS} already exists."
else
  echo "Updating /etc/hosts with: ${HOSTS}"
  cat << EOF | tee -a /etc/hosts
$HOSTS
EOF
fi

# x/32 will work for CEPH in a single node deploy.
CIDR="$LOCAL_IP/32"

# Variable setup
set -x
# The IP address of the genesis node
export HOSTIP=$LOCAL_IP
# The CIDR of the network for the genesis node
export HOSTCIDR=$CIDR
# The network interface on the genesis node
export NODE_NET_IFACE=$HOST_IFACE

export TARGET_SITE="aiab"
set +x

# Changes DNS servers in common-addresses.yaml to the system's DNS servers
get_dns_servers ()
{
  if hash nmcli 2>/dev/null; then
    nmcli dev show | awk '/IP4.DNS/ {print $2}' | xargs
  else
    cat /etc/resolv.conf | awk '/nameserver/ {print $2}' | xargs
  fi
}

if grep -q "10.96.0.10" "/etc/resolv.conf"; then
  echo "Not changing DNS servers, /etc/resolv.conf already updated."
else
  DNS_CONFIG_FILE="${AIAB_DIR}/../../../site/${TARGET_SITE}/networks/common-addresses.yaml"
  declare -a DNS_SERVERS=($(get_dns_servers))
  NS1=${DNS_SERVERS[0]:-8.8.8.8}
  NS2=${DNS_SERVERS[1]:-$NS1}
  echo "Using DNS servers $NS1 and $NS2."
  sed -i "s/8.8.8.8/$NS1/" $DNS_CONFIG_FILE
  sed -i "s/8.8.4.4/$NS2/" $DNS_CONFIG_FILE
fi

echo ""
echo "Starting Airship deployment..."
sleep 1
${AIAB_DIR}/common/deploy-airship.sh demo
