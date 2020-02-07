#!/usr/bin/env bash
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

SCRIPT_DIR=$(realpath "$(dirname "${0}")")
WORKSPACE=$(realpath "${SCRIPT_DIR}/..")
GATE_UTILS=${WORKSPACE}/seaworthy-virt/airship_gate/lib/all.sh

GATE_COLOR=${GATE_COLOR:-1}

export GATE_COLOR
export GATE_UTILS
export WORKSPACE

source "${GATE_UTILS}"

REQUIRE_RELOG=0

log_stage_header "Installing Packages"
export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get update -qq
sudo -E apt-get install -q -y --no-install-recommends \
    curl \
    docker.io \
    fio \
    genisoimage \
    jq \
    libstring-shellquote-perl \
    libvirt-bin \
    qemu-kvm \
    qemu-utils \
    virtinst

log_stage_header "Joining User Groups"
for grp in docker libvirtd libvirt; do
    if ! groups | grep $grp > /dev/null; then
        sudo adduser "$(id -un)" $grp || echo "Group $grp not found, not added to user"
        REQUIRE_RELOG=1
    fi
done

make_virtmgr_account

HTTPS_PROXY=${HTTPS_PROXY:-${https_proxy}}
HTTPS_PROXY=${HTTP_PROXY:-${http_proxy}}

if [[ ! -z "${HTTPS_PROXY}" ]]
then
    log_stage_header "Configuring Apt Proxy"
    cat << EOF | sudo tee /etc/apt/apt.conf.d/50proxyconf
Acquire::https::proxy "${HTTPS_PROXY}";
Acquire::http::proxy "${HTTPS_PROXY}";
EOF

    log_stage_header "Configuring Docker Proxy"
    sudo mkdir -p /etc/systemd/system/docker.service.d/
    cat << EOF | sudo tee /etc/systemd/system/docker.service.d/proxy.conf
[Service]
Environment="HTTP_PROXY=${HTTP_PROXY}"
Environment="HTTPS_PROXY=${HTTPS_PROXY}"
Environment="NO_PROXY=${NO_PROXY}"
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart docker
fi

log_stage_header "Setting Kernel Parameters"
if [ "xY" != "x$(cat /sys/module/kvm_intel/parameters/nested)" ]; then
    log_note Enabling nested virtualization.
    sudo modprobe -r kvm_intel
    sudo modprobe kvm_intel nested=1 || log_error Nested Virtualization not supported
    echo "options kvm-intel nested=1" | sudo tee /etc/modprobe.d/kvm-intel.conf
fi

if ! sudo virt-host-validate qemu &> /dev/null; then
    log_note Host did not validate virtualization check:
    sudo virt-host-validate qemu || true
fi

if [[ ! -d ${VIRSH_POOL_PATH} ]]; then
    sudo mkdir -p "${VIRSH_POOL_PATH}"
fi

log_stage_header "Disabling br_netfilter"
cat << EOF | sudo tee /etc/sysctl.d/60-bridge.conf
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0
EOF
cat << EOF | sudo tee /etc/udev/rules.d/99-bridge.rules
ACTION=="add", SUBSYSTEM=="module", KERNEL=="br_netfilter", \
                RUN+="/lib/systemd/systemd-sysctl --prefix=/net/bridge"
EOF
besteffort sudo sysctl -p /etc/sysctl.d/60-bridge.conf

if [[ ${REQUIRE_RELOG} -eq 1 ]]; then
    echo
    log_note "You must ${C_HEADER}log out${C_CLEAR} and back in before the gate is ready to run."
fi

log_huge_success
