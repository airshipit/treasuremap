#!/bin/bash

nginx_down() {
    REGISTRY_ID=$(docker ps -qa -f name=promenade-nginx)
    if [ "x${REGISTRY_ID}" != "x" ]; then
        log Removing nginx server
        docker rm -fv "${REGISTRY_ID}" &>> "${LOG_FILE}"
    fi
}

nginx_up() {
    log Starting nginx server to serve configuration files
    mkdir -p "${NGINX_DIR}"
    docker run -d \
        -p 7777:80 \
        --restart=always \
        --name promenade-nginx \
        -v "${TEMP_DIR}/nginx:/usr/share/nginx/html:ro" \
            nginx:stable &>> "${LOG_FILE}"
}

nginx_cache_and_replace_tar_urls() {
    log "Finding tar_url options to cache.."
    TAR_NUM=0
    mkdir -p "${NGINX_DIR}"
    for file in "$@"; do
        grep -Po "^ +tar_url: \K.+$" "${file}" | while read -r tar_url ; do
            # NOTE(mark-burnet): Does not yet ignore repeated files.
            DEST_PATH="${NGINX_DIR}/cached-tar-${TAR_NUM}.tgz"
            log "Caching ${tar_url} in file: ${DEST_PATH}"
            REPLACEMENT_URL="${NGINX_URL}/cached-tar-${TAR_NUM}.tgz"
            curl -Lo "${DEST_PATH}" "${tar_url}"
            sed -i "s;${tar_url};${REPLACEMENT_URL};" "${file}"
            TAR_NUM=$((TAR_NUM + 1))
        done
    done
}
