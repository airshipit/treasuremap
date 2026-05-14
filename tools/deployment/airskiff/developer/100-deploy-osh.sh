#!/bin/bash
#
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

# Lint deployment documents
: "${AIRSHIP_PATH:="./tools/airship"}"
: "${PEGLEG:="sudo ${AIRSHIP_PATH} pegleg"}"
: "${SHIPYARD:="${AIRSHIP_PATH} shipyard"}"
: "${PL_SITE:="airskiff"}"
: "${NAMESPACE:=ucp}"
: "${AIRFLOW_UI_EXTERNAL_PORT:=5590}"
: "${AIRFLOW_UI_SVC_PORT:=80}"

# Source OpenStack credentials for Airship utility scripts
source ./tools/deployment/airskiff/common/os-env.sh

# Re-establish port-forward only if not already responding.
# A previous gate step (050) may have started it and it's still alive —
# in that case pkill/fuser can't see it (different Zuul process group),
# so we check first and only restart if the forward is actually dead.
if ! curl -so /dev/null --max-time 3 "http://localhost:${AIRFLOW_UI_EXTERNAL_PORT}/"; then
  echo "Airflow port-forward not responding, restarting..."
  # ss sees all processes by port regardless of process group
  PF_PID=$(ss -tlnp "sport = :${AIRFLOW_UI_EXTERNAL_PORT}" | grep -oP 'pid=\K[0-9]+' | head -1 || true)
  [[ -n "${PF_PID}" ]] && kill "${PF_PID}" 2>/dev/null || true
  pkill -f "kubectl port-forward.*svc/airflow-int" 2>/dev/null || true
  fuser -k "${AIRFLOW_UI_EXTERNAL_PORT}/tcp" 2>/dev/null || true
  sleep 2
  kubectl port-forward -n "${NAMESPACE}" svc/airflow-int "${AIRFLOW_UI_EXTERNAL_PORT}:${AIRFLOW_UI_SVC_PORT}" --address=0.0.0.0 </dev/null &
  disown $!
fi

END=$(($(date +%s) + 180))
until curl -so /dev/null "http://localhost:${AIRFLOW_UI_EXTERNAL_PORT}/"; do
  [ "$(date +%s)" -gt "${END}" ] && { echo "Timed out waiting for airflow port-forward to become ready"; exit 1; }
  sleep 2
done

curl -siv "http://localhost:${AIRFLOW_UI_EXTERNAL_PORT}/" | head -10


# NOTE(drewwalters96): Disable Pegleg linting errors P001 and P009; a
#  a cleartext storage policy is acceptable for non-production use cases
#  and maintain consistency with other treasuremap sites.
${PEGLEG} site -r . lint "${PL_SITE}" -x P001 -x P009

# Collect deployment documents
: "${PL_OUTPUT:="peggles"}"
mkdir -p ${PL_OUTPUT}

TERM_OPTS="-l info" ${PEGLEG} site -r . collect ${PL_SITE} -s ${PL_OUTPUT}

sudo chown -R ${USER} peggles

# Start the deployment
${SHIPYARD} create configdocs airskiff-design \
             --replace \
             --directory=${PL_OUTPUT}
${SHIPYARD} commit configdocs
${SHIPYARD} create action update_software --allow-intermediate-commits

df -h
