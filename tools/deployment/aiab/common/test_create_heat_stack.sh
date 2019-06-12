#!/bin/bash
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

set -e

AIAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../" >/dev/null 2>&1 && pwd )"
OPENSTACK="${AIAB_DIR}/../../openstack"

# External subnet is local to the environment and generally can be anything
# other then clash with default all-in-one OSH setup that uses 127.24.4.0/24
export OSH_BR_EX_ADDR="172.24.8.1/24"
export OSH_EXT_SUBNET="172.24.8.0/24"

# Install curl if it's not already installed
apt -y install --no-install-recommends curl

pushd "${AIAB_DIR}"

printf "\nCreating KeyPair\n"
${OPENSTACK} keypair create heat-vm-key > id_rsa
chmod 600 id_rsa

printf "Downloading heat-public-net-deployment.yaml\n"
curl -LO https://raw.githubusercontent.com/openstack/openstack-helm/master/tools/gate/files/heat-public-net-deployment.yaml

printf "Creating public-net Heat Stack\n"
${OPENSTACK} stack create --wait \
    --parameter subnet_cidr=${OSH_EXT_SUBNET} \
    --parameter subnet_gateway=${OSH_BR_EX_ADDR%/*} \
    -t /target/heat-public-net-deployment.yaml \
    public-net

printf "Downloading heat-basic-vm-deployment.yaml\n"
curl -LO https://raw.githubusercontent.com/openstack/openstack-helm/master/tools/gate/files/heat-basic-vm-deployment.yaml

printf "Creating test-stack-01\n"
${OPENSTACK} stack create -t /target/heat-basic-vm-deployment.yaml test-stack-01 --wait
popd

printf "Heat Stack List\n"
${OPENSTACK} stack list

printf "Nova Server List\n"
${OPENSTACK} server list

FLOATING_IP=$(${OPENSTACK} stack output show \
    test-stack-01 \
    floating_ip \
    -f value -c output_value)

printf "Configuring required network settings\n"
sudo ip addr add ${OSH_BR_EX_ADDR} dev br-ex
sudo ip link set br-ex up
sudo iptables -P FORWARD ACCEPT
DEFAULT_ROUTE_DEV="$(sudo ip -4 route list 0/0 | awk '{ print $5; exit }')"
sudo iptables -t nat -A POSTROUTING -o ${DEFAULT_ROUTE_DEV} -s ${OSH_EXT_SUBNET} -j MASQUERADE

function wait_for_ssh_port {
  # Default wait timeout is 300 seconds
  set +x
  end=$(date +%s)
  if ! [ -z $2 ]; then
   end=$((end + $2))
  else
   end=$((end + 300))
  fi
  while true; do
      # Use Nmap as its the same on Ubuntu and RHEL family distros
      nmap -Pn -p22 $1 | awk '$1 ~ /22/ {print $2}' | grep -q 'open' && \
          break || true
      sleep 1
      now=$(date +%s)
      [ $now -gt $end ] && echo "Could not connect to $1 port 22 in time" && exit -1
  done
  set -x
}
wait_for_ssh_port $FLOATING_IP

install -m 0700 -d ~/.ssh
ssh-keyscan "${FLOATING_IP}" >> ~/.ssh/known_hosts
printf "The test VM is accessible via SSH:  ssh -i id_rsa cirros@${FLOATING_IP}\n"
