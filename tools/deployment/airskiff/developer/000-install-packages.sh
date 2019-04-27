#!/bin/bash

# Copyright 2017 The Openstack-Helm Authors.
# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

set -xe

# Docker CE Repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-add-repository \
        "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) \
        stable"
sudo apt-get update

# Purge Docker and install Docker CE
sudo systemctl unmask docker.service
sudo apt-get remove --no-install-recommends -y docker docker-engine docker.io

# TODO(drewwalters96): Update to Docker 18.09 when supported by Minikube.
sudo apt-get install --allow-downgrades --no-install-recommends -y \
        apparmor \
        ca-certificates \
        docker-ce=18.06.1~ce~3-0~ubuntu \
        git \
        make \
        jq \
        nmap \
        curl \
        python-pip \
        uuid-runtime \
        apt-transport-https \
        ca-certificates \
        gcc \
        python-dev \
        python-setuptools \
        software-properties-common

# Enable apparmor
sudo systemctl enable apparmor
sudo systemctl start apparmor

# Add $USER to docker group
# NOTE: This requires re-authentication. Restart your shell.
sudo adduser "$(whoami)" docker
