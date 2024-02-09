#!/bin/bash

set -ex

# start http server with artifacts
docker rm artifacts --force || true
docker run --name artifacts -p 8282:80 -v $(pwd)/../artifacts:/usr/share/nginx/html -d nginx
sleep 10
curl --verbose -I http://control-plane.minikube.internal:8282/memcached.tgz