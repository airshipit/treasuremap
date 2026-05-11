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

: "${NAMESPACE:=ucp}"
: "${AIRFLOW_UI_EXTERNAL_PORT:=5590}"
: "${AIRFLOW_UI_SVC_PORT:=80}"

# Detect the externally-reachable IP.
# Priority: (1) cloud metadata public IPv4 (OpenStack/AWS EC2-compat),
#           (2) IP on the default-route interface.
get_external_ip() {
  local public_ip
  public_ip=$(curl -sf --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
  if [[ -n "${public_ip}" ]]; then
    echo "${public_ip}"
    return
  fi
  local iface
  iface=$(ip route show default | awk '/default/ {print $5}' | head -1)
  ip addr show "${iface:-ens3}" | awk '/inet / {print $2}' | cut -d/ -f1 | head -1
}

# Wait until airflow-int service exists and has a ClusterIP
until kubectl get svc -n "${NAMESPACE}" airflow-int &>/dev/null; do
  echo "Waiting for airflow-int service to be created..."
  sleep 10
done
until [[ -n "$(kubectl get svc -n "${NAMESPACE}" airflow-int -o jsonpath='{.spec.clusterIP}' 2>/dev/null)" ]]; do
  echo "Waiting for airflow-int service to get a ClusterIP..."
  sleep 5
done

EXTERNAL_IP=$(get_external_ip)

# Start port-forward with retries: if the port is still held from a previous run,
# kill the holder and try again.
for attempt in 1 2 3; do
  # Kill any previous port-forward (by name, by port, and by ss PID lookup for cross-group processes).
  PF_PID=$(ss -tlnp "sport = :${AIRFLOW_UI_EXTERNAL_PORT}" | grep -oP 'pid=\K[0-9]+' | head -1 || true)
  [[ -n "${PF_PID}" ]] && kill "${PF_PID}" 2>/dev/null || true
  pkill -f "kubectl port-forward.*svc/airflow-int" 2>/dev/null || true
  fuser -k "${AIRFLOW_UI_EXTERNAL_PORT}/tcp" 2>/dev/null || true
  sleep 2
  kubectl port-forward -n "${NAMESPACE}" svc/airflow-int "${AIRFLOW_UI_EXTERNAL_PORT}:${AIRFLOW_UI_SVC_PORT}" --address=0.0.0.0 </dev/null &
  PORT_FORWARD_PID=$!
  sleep 2
  if kill -0 "${PORT_FORWARD_PID}" 2>/dev/null; then
    disown "${PORT_FORWARD_PID}"
    break
  fi
  echo "Port-forward attempt ${attempt} failed, freeing port ${AIRFLOW_UI_EXTERNAL_PORT} and retrying..."
  fuser -k "${AIRFLOW_UI_EXTERNAL_PORT}/tcp" 2>/dev/null || true
  sleep 2
done

# Wait for port-forward to be ready
until curl -so /dev/null "http://localhost:${AIRFLOW_UI_EXTERNAL_PORT}/"; do
  sleep 2
done

curl -siv "http://localhost:${AIRFLOW_UI_EXTERNAL_PORT}/" | head -10

set +x
echo "╔══════════════════════════════════════════════════╗"
echo "║           AIRFLOW UI ACCESS INFO                 ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  URL:      http://${EXTERNAL_IP}:${AIRFLOW_UI_EXTERNAL_PORT}/  ║"
echo "║  Login:    airflow                               ║"
echo "║  Password: password                              ║"
echo "╚══════════════════════════════════════════════════╝"
curl -si -u "airflow:password" "http://localhost:${AIRFLOW_UI_EXTERNAL_PORT}/" | head -3
echo "Sleeping for 120 seconds .............."
sleep 120
