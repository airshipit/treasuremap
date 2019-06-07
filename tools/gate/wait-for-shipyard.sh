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

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/../../ >/dev/null 2>&1 && pwd )"
: "${SHIPYARD:=${REPO_DIR}/tools/airship shipyard}"

ACTION=$(${SHIPYARD} get actions | grep -i "Processing" | awk '{ print $2 }')

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
