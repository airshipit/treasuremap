#!/bin/bash

# This script should be run as a one-time fix DURING an upgrade of
# "vanilla" postgres to patroni (in either a single or HA multi-replica
# configuration).
#
# This addresses an issue where the previous version of the chart had a
# service-managed `endpoints` object, while patroni needs to manage its
# own kubernetes `endpoints`.  Patroni won't successfully manage
# (i.e. apply annotation to, etc) the postgresql endpoints until the
# service-managed endpoints are out of the way; however deletion of the
# postgresql endpoints must be done with care during an upgrade.
#
# This script watches for the right moment and deletes the endpoints.

export KUBECONFIG=${KUBECONFIG:-"/etc/kubernetes/admin.conf"}

while true; do
  echo "Checking to see if patroni is deployed..."
  # Wait for the patroni-based chart to get deployed
  if [ $(kubectl describe pod -n ucp postgresql-0 | grep -c "patroni") -gt 0 ]; then
    echo 'Detected that patroni is deployed'

    # The port name used by the single-node postgres chart is "db",
    # while the new port name is "postgres"
    FIRST_PORT_NAME=$(kubectl get -n ucp endpoints postgresql -o jsonpath='{.subsets[0].ports[0].name}')
    if [ "x${FIRST_PORT_NAME}" == "xdb" ]; then
      echo "matched the old endpoints: deleting old postgresql endpoints"
      kubectl delete endpoints -n ucp postgresql
      echo "done."
      exit 0
    fi
  fi

  sleep 5
done
