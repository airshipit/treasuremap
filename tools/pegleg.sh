#!/usr/bin/env bash

set -e

 : ${WORKSPACE:=$(pwd)}
 : ${IMAGE:=quay.io/airshipit/pegleg:ae5db00f83e4473638e05397dcc5509d570dd254-ubuntu_xenial}
# : ${IMAGE:=quay.io/airshipit/pegleg:6a6346f70f4eea73ec5aa7fbe6b3c380edc6c883d018200041b2b8dc6adbe66f}
#  : ${IMAGE:=quay.io/airshipit/pegleg:latest}

: ${TERM_OPTS:=-it}

echo
echo "== NOTE: Workspace $WORKSPACE is the execution directory in the container =="
echo

# Working directory inside container to execute commands from and mount from
# host OS
container_workspace_path='/workspace'

docker run --rm $TERM_OPTS \
    --net=host \
    --workdir="$container_workspace_path" \
    -v "${HOME}/.ssh:${container_workspace_path}/.ssh" \
    -v "${WORKSPACE}:$container_workspace_path" \
    -e "PEGLEG_PASSPHRASE=$PEGLEG_PASSPHRASE" \
    -e "PEGLEG_SALT=$PEGLEG_SALT" \
    "${IMAGE}" \
    pegleg "${@}"
