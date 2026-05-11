#!/bin/bash

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
#    under the License

set -e
set -o pipefail

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

until curl -so /dev/null "http://localhost:${AIRFLOW_UI_EXTERNAL_PORT}/"; do
  sleep 2
done

curl -siv "http://localhost:${AIRFLOW_UI_EXTERNAL_PORT}/" | head -10



REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/../../ >/dev/null 2>&1 && pwd )"
: "${SHIPYARD:=${REPO_DIR}/tools/airship shipyard}"

ACTION=$(${SHIPYARD} get actions | grep -i "Processing" | awk '{ print $2 }')

# Exit earlier if there is nothing to wait for.
if [ -z "${ACTION}" ]; then
        echo "No actions in Processing state, exiting..."
        exit 0
fi

echo -e "\nWaiting for $ACTION..."
while true; do
        # Print the status of tasks
        ${SHIPYARD} describe "${ACTION}"

        status=$(${SHIPYARD} describe "$ACTION" | grep -i "Lifecycle" | \
                awk '{print $2}')

        steps=$(${SHIPYARD} describe "$ACTION" | grep -i "step/" | \
                awk '{print $3}')

        # Verify lifecycle status
        if [ "${status}" == "Failed" ]; then
                echo -e "\n$ACTION FAILED\n"
                ${SHIPYARD} describe "${ACTION}"
                exit 1
        fi

        if [ "${status}" == "Complete" ]; then
                # Verify status of each action step
                for step in $steps; do
                  if [ "${step}" == "failed" ]; then
                    echo -e "\n$ACTION FAILED\n"
                    ${SHIPYARD} describe "${ACTION}"
                    exit 1
                  fi
                done

                echo -e "\n$ACTION completed SUCCESSFULLY\n"
                ${SHIPYARD} describe "${ACTION}"
                exit 0
        fi

        sleep 10
done
