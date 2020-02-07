#!/bin/bash
docker_ps() {
    VIA="${1}"
    ssh_cmd "${VIA}" docker ps -a
}

docker_info() {
    VIA="${1}"
    ssh_cmd "${VIA}" docker info 2>&1
}

docker_exited_containers() {
    VIA="${1}"
    ssh_cmd "${VIA}" docker ps -q --filter "status=exited"
}

docker_inspect() {
    VIA="${1}"
    CONTAINER_ID="${2}"
    ssh_cmd "${VIA}" docker inspect "${CONTAINER_ID}"
}

docker_logs() {
    VIA="${1}"
    CONTAINER_ID="${2}"
    ssh_cmd "${VIA}" docker logs "${CONTAINER_ID}"
}
