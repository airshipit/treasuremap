#!/bin/bash
set -e

LIB_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
export LIB_DIR
REPO_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../../../../..")
export REPO_ROOT

source "$LIB_DIR"/config.sh
source "$LIB_DIR"/const.sh
source "$LIB_DIR"/docker.sh
source "$LIB_DIR"/kube.sh
source "$LIB_DIR"/log.sh
source "$LIB_DIR"/nginx.sh
source "$LIB_DIR"/promenade.sh
source "$LIB_DIR"/registry.sh
source "$LIB_DIR"/ssh.sh
source "$LIB_DIR"/virsh.sh
source "$LIB_DIR"/airship.sh
source "$LIB_DIR"/ingress.sh
source "$LIB_DIR"/bgp.sh

if [[ -v GATE_DEBUG && ${GATE_DEBUG} = "1" ]]; then
    set -x
fi
