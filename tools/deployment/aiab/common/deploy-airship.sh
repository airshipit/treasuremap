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
# Set up and deploy an Airship environment for development/testing purposes.  #
# Many of the defaults and sources used here are NOT production ready, and    #
# this should not be used as a copy/paste source for any production use.      #
#                                                                             #
###############################################################################

set -x

# The last step to run through in this script. Valid Values are "collect",
# "genesis", "deploy", and "demo". By default this will run through to the end
# of the genesis steps
LAST_STEP_NAME=${1:-"genesis"}

if [[ ${LAST_STEP_NAME} == "collect" ]]; then
  STEP_BREAKPOINT=10
elif [[ ${LAST_STEP_NAME} == "genesis" ]]; then
  STEP_BREAKPOINT=20
elif [[ ${LAST_STEP_NAME} == "deploy" ]]; then
  STEP_BREAKPOINT=30
elif [[ ${LAST_STEP_NAME} == "demo" ]]; then
  STEP_BREAKPOINT=40
else
  STEP_BREAKPOINT=20
fi

# The directory of the repo where current script is located.
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/../../../../ >/dev/null 2>&1 && pwd )"

# The directory that will contain the copies of designs and repos from this
# script. By default it is a directory where the repository is cloned.
export WORKSPACE=${WORKSPACE:-"${REPO_DIR}/../"}

# The site to deploy
TARGET_SITE=${TARGET_SITE:-"aiab"}

# Setup blank defaults for proxy variables
http_proxy=${http_proxy:-""}
https_proxy=${https_proxy:-""}
no_proxy=${no_proxy:-""}

# The host name for the single-node deployment. e.g.: 'genesis'
SHORT_HOSTNAME=${SHORT_HOSTNAME:-""}
# The host ip for this single-node deployment. e.g.: '10.0.0.9'
HOSTIP=${HOSTIP:-""}
# The cidr for the network for the host. e.g.: '10.0.0.0/24'
HOSTCIDR=${HOSTCIDR:-""}
# The interface on the host/genesis node. e.g.: 'ens3'
NODE_NET_IFACE=${NODE_NET_IFACE:-""}
# Allowance for Genesis/Armada to settle in seconds:
POST_GENESIS_DELAY=${POST_GENESIS_DELAY:-60}

# Command shortcuts
PEGLEG="${REPO_DIR}/tools/airship pegleg"
SHIPYARD="${REPO_DIR}/tools/airship shipyard"
PROMENADE="${REPO_DIR}/tools/airship promenade"

function check_preconditions() {
  set +x
  fail=false
  if ! [ $(id -u) = 0 ] ; then
    echo "Please execute this script as root!"
    fail=true
  fi
  if [ -z ${HOSTIP} ] ; then
    echo "The HOSTIP variable must be set. E.g. 10.0.0.9"
    fail=true
  fi
  if [ -z ${SHORT_HOSTNAME} ] ; then
    echo "The SHORT_HOSTNAME variable must be set. E.g. testvm1"
    fail=true
  fi
  if [ -z ${HOSTCIDR} ] ; then
    echo "The HOSTCIDR variable must be set. E.g. 10.0.0.0/24"
    fail=true
  fi
  if [ -z ${NODE_NET_IFACE} ] ; then
    echo "The NODE_NET_IFACE variable must be set. E.g. ens3"
    fail=true
  fi
  if [[ -z $(grep $SHORT_HOSTNAME /etc/hosts | grep $HOSTIP) ]]
  then
    echo "No /etc/hosts entry found for $SHORT_HOSTNAME. Please add one."
    fail=true
  fi
  if [ $fail = true ] ; then
    echo "Preconditions failed"
    exit 1
  fi
  set -x
}

function setup_workspace() {
  # Setup workspace directories
  mkdir -p ${WORKSPACE}/collected
  mkdir -p ${WORKSPACE}/genesis
  # Open permissions for output from Promenade
  chmod -R 777 ${WORKSPACE}/genesis
}

function configure_docker() {
  if [[ ! -z "${https_proxy}" ]] || [[ ! -z "${http_proxy}" ]]
  then
    echo "Configuring Docker to use a proxy..."
    mkdir -p /etc/systemd/system/docker.service.d/
    cat << EOF > /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=${http_proxy}"
Environment="HTTPS_PROXY=${https_proxy}"
Environment="NO_PROXY=${no_proxy}"
EOF
    systemctl daemon-reload
    systemctl restart docker
  fi
}

function configure_apt() {
  if [[ ! -z "${https_proxy}" ]] || [[ ! -z "${http_proxy}" ]]
  then
    echo "Configuring apt to use a proxy..."
    mkdir -p /etc/apt/
    cat << EOF > /etc/apt/apt.conf
Acquire::http::proxy "${http_proxy}";
Acquire::https::proxy "${https_proxy}";
EOF
  fi
}

function configure_dev_configurables() {
  cat << EOF >> ${WORKSPACE}/treasuremap/site/${TARGET_SITE}/deployment/dev-configurables.yaml
data:
  hostname: ${SHORT_HOSTNAME}
  hostip: ${HOSTIP}
  hostcidr: ${HOSTCIDR}
  interface: ${NODE_NET_IFACE}
  maas-ingress: '192.169.1.5/32'
EOF
}

function install_dependencies() {
    apt -qq update
    # Install docker
    apt -y install --no-install-recommends docker.io jq nmap nfs-common
}

function run_pegleg_collect() {
  pushd ${WORKSPACE}
  # Make sure certificates generated during prior runs are deleted.
  rm -f treasuremap/site/${TARGET_SITE}/secrets/certificates.yaml
  # Run pegleg collect to get the documents combined.
  ${PEGLEG} site -r /target/treasuremap collect ${TARGET_SITE} -s /target/collected
  popd
}

function generate_certs() {
  # Runs the generation of certs by Promenade and builds bootstrap scripts
  # Note: In the really real world, CAs and certs would be provided as part of
  #   the supplied design. In this dev/test environment, self signed is fine.
  # Moves the generated certificates from /genesis to the design, so that a
  # Lint can be run
  set +x
  echo "=== Generating updated certificates ==="
  set -x
  pushd ${WORKSPACE}
  # Copy the collected yamls into the target for the certs
  cp collected/*.yaml genesis/
  # Generate certificates
  ${PROMENADE} generate-certs -o /target/genesis /target/genesis/treasuremap.yaml
  # Copy the generated certs back into the deployment_files structure
  cp genesis/certificates.yaml treasuremap/site/${TARGET_SITE}/secrets/
  popd
}

function lint_design() {
  # After the certificates are in the deployment files run a pegleg lint
  pushd ${WORKSPACE}
  ${PEGLEG} site -r /target/treasuremap lint -x P001 ${TARGET_SITE}
  popd
}

function generate_genesis() {
  # Generate the genesis scripts
  pushd ${WORKSPACE}
  ${PROMENADE} build-all -o /target/genesis --validators \
    /target/genesis/treasuremap.yaml \
    /target/genesis/certificates.yaml
  popd
}

function run_genesis() {
  # Runs the genesis script that was generated
  ${WORKSPACE}/genesis/genesis.sh
}

function validate_genesis() {
  # Vaidates the genesis deployment
  ${WORKSPACE}/genesis/validate-genesis.sh
}

function genesis_complete() {
  # Setup kubeconfig
  if [ ! -d "$HOME/.kube" ] ; then
    mkdir ~/.kube
  fi
  cp -r /etc/kubernetes/admin/pki ~/.kube/pki
  cat /etc/kubernetes/admin/kubeconfig.yaml | sed -e 's/\/etc\/kubernetes\/admin/./' > ~/.kube/config

  set +x
  echo "-----------"
  echo "Waiting ${POST_GENESIS_DELAY} seconds for Genesis process to settle. This is a good time to grab one more coffee :)"
  echo "-----------"
  sleep ${POST_GENESIS_DELAY}
  echo " "
  echo "Genesis complete. "
  print_shipyard_info1
  set -x
}

function print_shipyard_info1() {
  SHIPYARD_KEYSTONE_PASS=$(awk '/^data:/ {print $2}' ${WORKSPACE}/treasuremap/site/${TARGET_SITE}/secrets/passphrases/ucp_shipyard_keystone_password.yaml)
  set +x
  # signals that genesis completed
  echo " "
  echo "The .yaml files in ${WORKSPACE} contain the site design that may be suitable for use with Shipyard. "
  echo "The Shipyard Keystone password ${SHIPYARD_KEYSTONE_PASS} may be found in ${WORKSPACE}/treasuremap/site/${TARGET_SITE}/secrets/passphrases/ucp_shipyard_keystone_password.yaml"
  echo " "
  set -x
}

function setup_deploy_site() {
  # creates a directory /${WORKSPACE}/site with all the things necessary to run
  # deploy_site
  mkdir -p ${WORKSPACE}/site
  cp ${WORKSPACE}/treasuremap/tools/deployment/aiab/common/creds.sh ${WORKSPACE}/site
  cp ${WORKSPACE}/genesis/*.yaml ${WORKSPACE}/site
  print_shipyard_info2
}

function print_shipyard_info2() {
  set +x
  echo " "
  echo "${WORKSPACE}/site is set up with creds.sh which can be sourced to set up credentials for use in running Shipyard"
  echo "${WORKSPACE}/site contains .yaml files that represent the single-node site deployment. (treasuremap.yaml, certificates.yaml)"
  echo " "
  echo "----------------------------------------------------------------------------------"
  echo "The following commands will execute Shipyard to setup and run a deploy_site action"
  echo "----------------------------------------------------------------------------------"
  echo "cd ${WORKSPACE}/site"
  echo "source creds.sh"
  echo "${SHIPYARD} create configdocs design --filename=/home/shipyard/host/treasuremap.yaml"
  echo "${SHIPYARD} create configdocs secrets --filename=/home/shipyard/host/certificates.yaml --append"
  echo "${SHIPYARD} commit configdocs"
  echo "${SHIPYARD} create action deploy_site"
  echo " "
  echo "-----------"
  echo "Other Notes"
  echo "-----------"
  echo "If you need to run Armada directly to deploy charts (fix something broken?), the following may be of use:"
  echo "export ARMADA_IMAGE=quay.io/airshipit/armada"
  echo "docker run -t -v ~/.kube:/armada/.kube -v ${WORKSPACE}/site:/target --net=host \${ARMADA_IMAGE} apply /target/your-yaml.yaml"
  echo " "
  set -x
}

function execute_deploy_site() {
  set +x
  echo " "
  echo "This is an automated deployment using Shipyard, running commands noted previously"
  echo "Please stand by while Shipyard deploys the site"
  echo " "
  pushd ${WORKSPACE}/site
  source creds.sh
  set -x
  ${SHIPYARD} create configdocs design --filename=/target/treasuremap.yaml
  ${SHIPYARD} create configdocs secrets --filename=/target/certificates.yaml --append
  ${SHIPYARD} commit configdocs
  ${SHIPYARD} create action deploy_site
  ${REPO_DIR}/tools/gate/wait-for-shipyard.sh
  popd
}

function execute_create_heat_stack() {
  # TODO: (bryan-strassner) prevent this running unless we're running from a
  #     compatible site defintion that includes OpenStack
  set +x
  echo " "
  echo "Performing basic sanity checks by creating heat stacks"
  echo " "
  set -x
  # Switch to directory where the script is located
  pushd ${WORKSPACE}/treasuremap/tools/deployment/aiab/common/
  bash test_create_heat_stack.sh
  popd
}

function publish_horizon_dashboard() {
  kubectl -n openstack expose service/horizon-int --type=NodePort --name=horizon-dashboard
}

function print_dashboards() {
  AIRFLOW_PORT=$(kubectl -n ucp get service airflow-web-int -o jsonpath="{.spec.ports[0].nodePort}")
  HORIZON_PORT=$(kubectl -n openstack get service horizon-dashboard -o jsonpath="{.spec.ports[0].nodePort}")
  MAAS_PORT=$(kubectl -n ucp get service maas-region-ui -o jsonpath="{.spec.ports[0].nodePort}")
  MASS_PASS=$(awk '/^data:/ {print $2}' ${WORKSPACE}/treasuremap/site/${TARGET_SITE}/secrets/passphrases/ucp_maas_admin_password.yaml)
  set +x
  echo " "
  echo "OpenStack Horizon dashboard is available on this host at the following URL:"
  echo " "
  echo "  http://${HOSTIP}:${HORIZON_PORT}"
  echo " "
  # TODO: (roman_g) can we source it from somewhere?
  echo "Credentials:"
  echo "  Domain: default"
  echo "  Username: admin"
  echo "  Password: password"
  echo " "
  echo "OpenStack CLI commands could be launched via \`./openstack\` script, e.g.:"
  echo "  # cd ${WORKSPACE}/treasuremap/tools/"
  echo "  # ./openstack stack list"
  echo "  ..."
  echo "  "
  echo "Other dashboards:"
  echo " "
  echo "  MAAS: http://${HOSTIP}:${MAAS_PORT}/MAAS/ admin/${MASS_PASS}"
  echo "  Airship Shipyard Airflow DAG: http://${HOSTIP}:${AIRFLOW_PORT}/"
  echo " "
  echo "Airship itself does not have a dashboard."
  echo " "
  # TODO: (roman_g) endpoints.yaml path below does not seem to be a reliable location
  echo "Other endpoints and credentials are listed in the following locations:"
  echo "  ${WORKSPACE}/type/sloop/config/endpoints.yaml"
  echo "  ${WORKSPACE}/treasuremap/site/${TARGET_SITE}/secrets/passphrases/"
  echo "Exposed ports of services can be listed with the following command:"
  echo "  # kubectl get services --all-namespaces | grep -v ClusterIP"
  echo "  ..."
  echo " "
  set -x
}

function your_next_steps() {
  set +x
  echo " "
  echo "---------------------------------------------------------------"
  echo " "
  echo "Airship has completed deployment of OpenStack (OpenStack-Helm)."
  echo " "
  echo "Explore Airship Treasuremap repository and documentation"
  echo "available at the following URLs:"
  echo " "
  echo "  https://opendev.org/airship/treasuremap/"
  echo "  https://airship-treasuremap.readthedocs.io/"
  echo " "
  echo "---------------------------------------------------------------"
  echo " "
  set -x
}

function clean() {
  # Perform any cleanup of temporary or unused artifacts
  set +x
  echo "To remove files generated during this script's execution, delete ${WORKSPACE}."
  echo "This VM is disposable. Re-deployment in this same VM will lead to unpredictable results."
  set -x
}

function error() {
  # Processes errors
  set +x
  echo "Error when $1."
  set -x
  exit 1
}

trap clean EXIT


# Common steps for all breakpoints specified
check_preconditions || error "checking for preconditions"
configure_apt || error "configuring apt behind proxy"
setup_workspace || error "setting up workspace directories"
configure_dev_configurables || error "adding dev-configurables values"
install_dependencies || error "installing dependencies"
configure_docker || error "configuring docker behind proxy"

# collect
if [[ ${STEP_BREAKPOINT} -ge 10 ]]; then
  echo "This is a good time to grab a coffee :)"
  run_pegleg_collect || error "running pegleg collect"
fi

# genesis
if [[ ${STEP_BREAKPOINT} -ge 20 ]]; then
  generate_certs || error "setting up certs with Promenade"
  lint_design || error "linting the design"
  generate_genesis || error "generating genesis"
  run_genesis || error "running genesis"
  validate_genesis || error "validating genesis"
  genesis_complete || error "printing out some info about next steps"
  setup_deploy_site || error "preparing the /site directory for deploy_site"
fi

# deploy
if [[ ${STEP_BREAKPOINT} -ge 30 ]]; then
  execute_deploy_site || error "executing deploy_site from the /site directory"
fi

# demo
if [[ ${STEP_BREAKPOINT} -ge 40 ]]; then
  execute_create_heat_stack || error "creating heat stack"
  publish_horizon_dashboard || error "publishing Horizon dashboard"
  print_shipyard_info1
  print_shipyard_info2
  print_dashboards || error "printing dashboards list"
  ## Done
  your_next_steps
fi
