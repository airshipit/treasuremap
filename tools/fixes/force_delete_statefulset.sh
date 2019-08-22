#!/bin/bash
set -e

# This script should be run manually to forcefully evict statefulset
# pods from a failed control node. Statefulset pods in kubernetes are not
# evicted automatically if a node goes down. Those pods would go to
# an 'unknown' status.

INITIAL_WAIT=${INITIAL_WAIT:-300}
LOOP_WAIT=${LOOP_WAIT:-10}

if [[ -z "${1}" ]]; then
    echo "ERROR: Failed control plane node name is not provided"
    echo "Please provide an argument with the name of the failed control plane node"
    exit 1
fi

failed_cp_node=$1

node_present=$(kubectl get nodes -l control-plane=enabled | grep "${failed_cp_node}" || true)

if [[ -z "${node_present}" ]]; then
    echo "The node name provided is incorrect."
    echo "Please provide the name of failed control plane node."
    exit 1
fi

# The idea here is to find out the names of the statefulset pod that is running on the provided
# failed control plane node and invoke a force delete action.

for ns in $(kubectl get ns | awk '{print $1}');do
  for ss in $(kubectl get statefulset -n "${ns}" --ignore-not-found --no-headers | \
    awk '{print $1}');do
      label=$(kubectl -n "${ns}" get statefulset "${ss}" --show-labels --no-headers | \
        awk '{print $5}')
      pod_name=$(kubectl -n "${ns}" get pod -l "${label}" -o wide --no-headers | \
        grep "${failed_cp_node}" | awk '{print $1}')
      if [[ -z "${pod_name}" ]]; then
          continue
      else
          kubectl -n "${ns}" delete pod "${pod_name}" --grace-period=0 --force --ignore-not-found
      fi
  done
done

# The Logic below is to wait for StatefulSet pods to be ready.
# During testing it took approx 20 mins for all the evicted
# statefulset pods to be ready. This time could be either less or
# more. We will wait for 5 mins before we start checking on
# pods to be ready.
echo "waiting for ${INITIAL_WAIT} seconds before starting to check on pod readiness."
echo "This is the initial wait time."
sleep ${INITIAL_WAIT}

for attempt in {1..180};do
  echo "waiting for pods to be Ready"
  echo "Trying attempt $attempt"

  # Statefulset pods are sequentially numbered. For example: 'mariadb-server-0', 'mariadb-server-1'.
  # We do not have more than 3 replicas for a statefulset pod.
  ss_not_ready_count=$(kubectl get --all-namespaces pods -o wide --no-headers | \
    grep '\-0 \|\-1 \|\-2 ' | egrep "0/1|0/2|0/3|1/2|1/3|2/3" | wc -l)

  # We would want the count of this variable to be '0' to determine that all the
  #  statefulset pods are ready.
  if [ "$ss_not_ready_count" == 0 ]; then
      echo "All the statefulset are now ready"
      exit 0
  else
      sleep "${LOOP_WAIT}"
  fi
done
echo "Statefulset pods are not ready in the specified time limit"
echo "Manual intervention is needed to recover the statefulset pods"
exit 1
