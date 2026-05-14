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

: "${ENABLE_MAAS_UPGRADE:=false}"
: "${RELEASE:=airship-ucp-maas}"
: "${NAMESPACE:=ucp}"
: "${AIRFLOW_UI_EXTERNAL_PORT:=5590}"
: "${AIRFLOW_UI_SVC_PORT:=80}"


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



# Detect the externally-reachable IP.
# Priority: (1) cloud metadata public IPv4 (OpenStack/AWS EC2-compat),
#           (2) IP on the default-route interface.
# Avoids hardcoding the interface name and handles nodes behind NAT.
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

echo "======================================================"
kubectl logs -n "${NAMESPACE}" \
  -l "application=maas,component=import-resources" \
  --prefix --tail=-1
echo "======================================================"

EXTERNAL_IP=$(get_external_ip)

for attempt in 1 2 3; do
  pkill -f "kubectl port-forward.*svc/maas-region" 2>/dev/null || true
  fuser -k 5240/tcp 2>/dev/null || true
  sleep 2
  kubectl port-forward -n "${NAMESPACE}" svc/maas-region 5240:83 --address=0.0.0.0 </dev/null &
  MAAS_PORT_FORWARD_PID=$!
  sleep 2
  if kill -0 "${MAAS_PORT_FORWARD_PID}" 2>/dev/null; then
    disown "${MAAS_PORT_FORWARD_PID}"
    break
  fi
  echo "Port-forward attempt ${attempt} failed, freeing port 5240 and retrying..."
  fuser -k 5240/tcp 2>/dev/null || true
  sleep 2
done

END=$(($(date +%s) + 180))
until curl -so /dev/null "http://localhost:5240/MAAS"; do
  [ "$(date +%s)" -gt "${END}" ] && { echo "Timed out waiting for maas port-forward to become ready"; exit 1; }
  sleep 2
done
curl -siv "http://localhost:5240/MAAS" | head -10

set +x
echo "╔══════════════════════════════════════════════════╗"
echo "║              MAAS UI ACCESS INFO                 ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  URL:      http://${EXTERNAL_IP}:5240/MAAS/      ║"
echo "║  Login:    admin                                 ║"
echo "║  Password: password123                           ║"
echo "╚══════════════════════════════════════════════════╝"
set -x

echo "Sleeping for 120 seconds .............."
sleep 120


ENABLE_MAAS_UPGRADE=$(echo "${ENABLE_MAAS_UPGRADE}" | tr '[:upper:]' '[:lower:]')

if [[ "${ENABLE_MAAS_UPGRADE}" != "true" ]]; then
    echo "ENABLE_MAAS_UPGRADE is not set to true, skipping MAAS upgrade."
    exit 0
fi

# Login to maas
MAAS_URL="http://$(kubectl get svc -n "${NAMESPACE}" maas-region -o jsonpath='{.spec.clusterIP}'):83/MAAS"
MAAS_API_KEY="$(kubectl exec -n "${NAMESPACE}" maas-region-0 -c maas-region -- maas apikey --username=admin)"
kubectl exec -n "${NAMESPACE}" maas-region-0 -c maas-region -- maas login admin ${MAAS_URL} ${MAAS_API_KEY}

# Base exec helper to reduce repetition
maas_exec() {
  # Pass the MaaS arguments; stderr preserved for debugging
  kubectl exec -n "${NAMESPACE}" maas-region-0 -c maas-region -- maas admin "$@"
}

# Unregister rack controllers before upgrade
# NOTE: if rack controllers are not unregistered
# we end up with an orphaned rack controller
# running the previous version of maas
MAAS_RACK_CONTROLLERS=$(maas_exec rack-controllers read | jq -r ".[] | .system_id")
for sys_id in ${MAAS_RACK_CONTROLLERS}; do
  printf "Unregistering rack controller: %s\n" "${sys_id}"
  maas_exec rack-controller delete ${sys_id} force=true
done

# Uninstall the Helm release if it exists
if helm --namespace "${NAMESPACE}" status "${RELEASE}" 2>/dev/null; then
  echo "Uninstalling existing Helm release ${RELEASE} in namespace ${NAMESPACE}..."
  helm uninstall "${RELEASE}" --namespace "${NAMESPACE}"

  # Wait for the release to be fully uninstalled
  echo "Waiting for Helm release ${RELEASE} to be fully uninstalled..."
  while helm --namespace "${NAMESPACE}" status "${RELEASE}" 2>/dev/null; do
    echo "Helm release ${RELEASE} is still being removed. Waiting..."
    sleep 5
  done
  echo "Helm release ${RELEASE} has been successfully uninstalled."
fi

if kubectl get pod clcp-maas-api-test -n ucp 2>/dev/null; then
  echo "Uninstalling existing clcp-maas-api-test pod in namespace ${NAMESPACE}..."
  kubectl delete pod clcp-maas-api-test -n ucp
fi

# Get current chart values and merge with jammy image configuration (previous release)
CURRENT_VALUES=$(kubectl get armadachart "${RELEASE}" -n "${NAMESPACE}" -o jsonpath='{.data.values}')

CHART_VALUES=$(echo "${CURRENT_VALUES}" | jq '. * {
  "conf": {
    "maas": {
      "images": {
        "default_os": "ubuntu",
        "default_image": "jammy",
        "default_kernel": "ga-22.04"
      }
    }
  },
  "images": {
    "tags": {
      "maas_cache": "quay.io/airshipit/sstream-cache-jammy:latest"
    }
  }
}')

# Patch the armadachart resource
CHART_CRD_PATCH_JSON=$(mktemp)

jq -n \
    --argjson VALUES "${CHART_VALUES}" \
'[
    {
        "op": "replace",
        "path": "/data/values",
        "value": $VALUES
    }
]' > "${CHART_CRD_PATCH_JSON}"

if kubectl patch armadachart "${RELEASE}" -n "${NAMESPACE}" --type=json -p "$(cat "${CHART_CRD_PATCH_JSON}")" 1> /dev/null; then
    echo "Patch applied successfully."
else
    echo "Patch failed."
    exit 1
fi

# Cleanup
rm -f "${CHART_CRD_PATCH_JSON}"


# Wait until maas-region service exists and has a ClusterIP
END=$(($(date +%s) + 600))
until kubectl get svc -n "${NAMESPACE}" maas-region &>/dev/null; do
  [ "$(date +%s)" -gt "${END}" ] && { echo "Timed out waiting for maas-region service to be created"; exit 1; }
  echo "Waiting for maas-region service to be created..."
  sleep 10
done
END=$(($(date +%s) + 120))
until [[ -n "$(kubectl get svc -n "${NAMESPACE}" maas-region -o jsonpath='{.spec.clusterIP}' 2>/dev/null)" ]]; do
  [ "$(date +%s)" -gt "${END}" ] && { echo "Timed out waiting for maas-region service to get a ClusterIP"; exit 1; }
  echo "Waiting for maas-region service to get a ClusterIP..."
  sleep 5
done
echo "maas-region service is ready."

EXTERNAL_IP=$(get_external_ip)

# Wait for the deployment to complete (with retries to tolerate self-heal restarts)
for attempt in 1 2 3 4 5; do
  echo "Waiting for armadacharts/${RELEASE} statuses (attempt ${attempt}/5)..."

  # Temporarily disable errexit so a transient timeout doesn't abort the script
  set +e
  kubectl wait --for=jsonpath='{.status.helmStatus}'=deployed --timeout=21600s -n "${NAMESPACE}" "armadacharts/${RELEASE}"
  rc_helm=$?
  kubectl wait --for=jsonpath='{.status.waitCompleted}'=true --timeout=21600s -n "${NAMESPACE}" "armadacharts/${RELEASE}"
  rc_wait=$?
  kubectl wait --for=jsonpath='{.status.tested}'=true --timeout=21600s -n "${NAMESPACE}" "armadacharts/${RELEASE}"
  rc_test=$?
  set -e

  if [[ ${rc_helm} -eq 0 && ${rc_wait} -eq 0 && ${rc_test} -eq 0 ]]; then
    break
  fi

  if [[ ${attempt} -lt 3 ]]; then
    echo "Not ready yet (rc_helm=${rc_helm}, rc_wait=${rc_wait}, rc_test=${rc_test}); retrying in 30s..."
    sleep 30
  else
    echo "Timed out waiting for armadacharts/${RELEASE} after ${attempt} attempts (rc_helm=${rc_helm}, rc_wait=${rc_wait}, rc_test=${rc_test})."
    exit 1
  fi
done
echo "'${RELEASE}' armadachart resource patched in namespace: ${NAMESPACE}"

echo "======================================================"
kubectl logs -n "${NAMESPACE}" \
  -l "application=maas,component=import-resources" \
  --prefix --tail=-1
echo "======================================================"

# Start port-forward to the upgraded pod
for attempt in 1 2 3; do
  pkill -f "kubectl port-forward.*svc/maas-region" 2>/dev/null || true
  fuser -k 5240/tcp 2>/dev/null || true
  sleep 2
  kubectl port-forward -n "${NAMESPACE}" svc/maas-region 5240:83 --address=0.0.0.0 </dev/null &
  MAAS_PORT_FORWARD_PID=$!
  sleep 2
  if kill -0 "${MAAS_PORT_FORWARD_PID}" 2>/dev/null; then
    disown "${MAAS_PORT_FORWARD_PID}"
    break
  fi
  echo "Port-forward attempt ${attempt} failed, freeing port 5240 and retrying..."
  fuser -k 5240/tcp 2>/dev/null || true
  sleep 2
done

for attempt in 1 2 3; do
  curl -so /dev/null "http://localhost:5240/MAAS"
  sleep 2
done
curl -siv "http://localhost:5240/MAAS" | head -10

set +x
echo "╔══════════════════════════════════════════════════╗"
echo "║              MAAS UI ACCESS INFO                 ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  URL:      http://${EXTERNAL_IP}:5240/MAAS/      ║"
echo "║  Login:    admin                                 ║"
echo "║  Password: password123                           ║"
echo "╚══════════════════════════════════════════════════╝"
set -x

echo "Sleeping for 120 seconds .............."
sleep 120
