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

echo "======================================================"
kubectl logs -n "${NAMESPACE}" \
  -l "application=maas,component=import-resources" \
  --prefix --tail=-1
echo "======================================================"

EXTERNAL_IP=$(ip addr show ens3 | awk '/inet / {print $2}' | cut -d/ -f1)
MAAS_REGION_SVC_IP=$(kubectl get svc -n "${NAMESPACE}" maas-region -o jsonpath='{.spec.clusterIP}')
sudo iptables-legacy -t nat -S PREROUTING | grep -- '--dport 5240 -j DNAT' | while IFS= read -r rule; do
  read -ra args <<< "${rule#-A PREROUTING }"
  sudo iptables-legacy -t nat -D PREROUTING "${args[@]}"
done
sudo iptables-legacy -t nat -S POSTROUTING | grep -- '--dport 83 -j MASQUERADE' | while IFS= read -r rule; do
  read -ra args <<< "${rule#-A POSTROUTING }"
  sudo iptables-legacy -t nat -D POSTROUTING "${args[@]}"
done
sudo iptables-legacy -t nat -A PREROUTING -d "${EXTERNAL_IP}" -p tcp --dport 5240 -j DNAT --to-destination "${MAAS_REGION_SVC_IP}:83"
sudo iptables-legacy -t nat -A POSTROUTING -d "${MAAS_REGION_SVC_IP}" -p tcp --dport 83 -j MASQUERADE
curl -si http://${EXTERNAL_IP}:5240/MAAS | head -3

set +x
echo "╔══════════════════════════════════════════════════╗"
echo "║              MAAS UI ACCESS INFO                 ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  URL:      http://${EXTERNAL_IP}:5240/MAAS/      ║"
echo "║  Login:    admin                                 ║"
echo "║  Password: password123                           ║"
echo "╚══════════════════════════════════════════════════╝"
set -x
sleep 30

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
until kubectl get svc -n "${NAMESPACE}" maas-region &>/dev/null; do
  echo "Waiting for maas-region service to be created..."
  sleep 10
done
until [[ -n "$(kubectl get svc -n "${NAMESPACE}" maas-region -o jsonpath='{.spec.clusterIP}' 2>/dev/null)" ]]; do
  echo "Waiting for maas-region service to get a ClusterIP..."
  sleep 5
done
echo "maas-region service is ready."

# Remove stale DNAT rules for dport 5240
sudo iptables-legacy -t nat -S PREROUTING | grep -- '--dport 5240 -j DNAT' | while IFS= read -r rule; do
  read -ra args <<< "${rule#-A PREROUTING }"
  sudo iptables-legacy -t nat -D PREROUTING "${args[@]}"
done
# Remove stale MASQUERADE rules for dport 83
sudo iptables-legacy -t nat -S POSTROUTING | grep -- '--dport 83 -j MASQUERADE' | while IFS= read -r rule; do
  read -ra args <<< "${rule#-A POSTROUTING }"
  sudo iptables-legacy -t nat -D POSTROUTING "${args[@]}"
done

EXTERNAL_IP=$(ip addr show ens3 | awk '/inet / {print $2}' | cut -d/ -f1)
MAAS_REGION_SVC_IP=$(kubectl get svc -n "${NAMESPACE}" maas-region -o jsonpath='{.spec.clusterIP}')
sudo iptables-legacy -t nat -A PREROUTING -d "${EXTERNAL_IP}" -p tcp --dport 5240 -j DNAT --to-destination "${MAAS_REGION_SVC_IP}:83"
sudo iptables-legacy -t nat -A POSTROUTING -d "${MAAS_REGION_SVC_IP}" -p tcp --dport 83 -j MASQUERADE
curl -si "http://${EXTERNAL_IP}:5240/MAAS" | head -3

set +x

echo "╔══════════════════════════════════════════════════╗"
echo "║              MAAS UI ACCESS INFO                 ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  URL:      http://${EXTERNAL_IP}:5240/MAAS/      ║"
echo "║  Login:    admin                                 ║"
echo "║  Password: password123                           ║"
echo "╚══════════════════════════════════════════════════╝"


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

echo "Sleeping for 120 seconds .............."
sleep 120
