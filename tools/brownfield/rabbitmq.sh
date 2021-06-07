#!/bin/bash
set -eu

RMQ_START_TIMEOUT=${RMQ_START_TIMEOUT:-"900s"}
RMQ_INIT_JOB_TIMEOUT=${RMQ_INIT_JOB_TIMEOUT:-"250s"}
RMQ_TERMINATE_TIMEOUT=${RMQ_TERMINATE_TIMEOUT:-"200s"}

# Set RMQ_NS environment variable to `ucp`, to reset UCP RabbitMQ cluster.
RMQ_NS=${RMQ_NS:-"ucp"}
RMQ_SS=${RMQ_SS:-"clcp-${RMQ_NS}-rabbitmq-rabbitmq"}
RMQ_RELEASE_GROUP=${RMQ_RELEASE_GROUP:-"clcp-${RMQ_NS}-rabbitmq"}
RMQ_WAIT_JOB=${RMQ_WAIT_JOB:-"clcp-${RMQ_NS}-rabbitmq-cluster-wait"}
RMQ_SERVER_LABELS=${RMQ_SERVER_LABELS:-"application=rabbitmq,component=server"}

function job_recreate {
  local ns=$1
  local job=$2
  local job_orig_path=$(mktemp --suffix=.orig.json)
  local job_new_path=$(mktemp --suffix=.new.json)
  kubectl get -n "${ns}" jobs "${job}" -o=json > "${job_orig_path}"

  cat "${job_orig_path}" | python -c "
import sys, json
d = json.load(sys.stdin)
def rm(d, path):
    path = path.split('.')
    last = path[-1]
    for p in path[:-1]:
        d = d.get(p, {})
    d.pop(last, None)
rm(d, 'status')
rm(d, 'spec.selector')
rm(d, 'spec.template.metadata.creationTimestamp')
rm(d, 'spec.template.metadata.labels.controller-uid')
rm(d, 'metadata.creationTimestamp')
rm(d, 'metadata.labels.controller-uid')
rm(d, 'metadata.resourceVersion')
rm(d, 'metadata.selfLink')
rm(d, 'metadata.uid')
print(json.dumps(d))
" > "${job_new_path}"

  cat "${job_orig_path}" | kubectl delete -f -
  cat "${job_new_path}" | kubectl create -f -
  kubectl wait -n "${ns}" job "${job}" --for=condition=complete --timeout="${RMQ_INIT_JOB_TIMEOUT}"
}

function force_unmap_rbd {
  local pvc_name=$1
  local rbd_host=$2
  # NOTE: for a single PVC there may be multiple PVs, try checking all of them.
  local rbd_names=$(kubectl get pv \
      -o jsonpath="{.items[?(@.spec.claimRef.name=='${pvc_name}')].spec.rbd.image}")
  local ceph_mon_pod=$(kubectl get pods -n ceph \
      -l application=ceph,component=mon \
      --field-selector status.phase=Running \
      -o jsonpath='{.items[0].metadata.name}')
  for rbd_name in ${rbd_names}; do
    if kubectl exec -n ceph $ceph_mon_pod -- rbd status $rbd_name | grep -i "Watchers: none"; then
      echo "No clients connected to '${rbd_name}' - OK"
    else
      echo "RBD client is still connected to '${rbd_name}', starting force unmap"
      local exec_pod=$(kubectl get pod -l application=divingbell,component=exec -n ucp \
          -o jsonpath="{.items[?(.spec.nodeName=='${rbd_host}')].metadata.name}")
      echo "Using '${exec_pod}' pod to unmap the volume"
      if kubectl exec -it $exec_pod -n ucp -- nsenter -t 1 -m -u -n -i rbd \
                showmapped | grep -i $rbd_name; then
         kubectl exec -it $exec_pod -n ucp -- nsenter -t 1 -m -u -n -i \
             rbd unmap -o force $rbd_name
      fi
    fi
  done
}

# Get a list of hosts where RabbitMQ servers are present.
rmq_hosts=$(kubectl get po -n "${RMQ_NS}" \
    -l "${RMQ_SERVER_LABELS}" \
    -o jsonpath="{.items[*].spec.nodeName}" | tr ' ' "\n" | sort -u)

echo "Scaling down RabbitMQ"
kubectl scale -n "${RMQ_NS}" --replicas=0 statefulset/"${RMQ_SS}"

echo "Waiting for pods to terminate"
kubectl wait -n "${RMQ_NS}" --for=delete -l "${RMQ_SERVER_LABELS}" \
    --timeout="${RMQ_TERMINATE_TIMEOUT}" pod 2>&1 | \
    grep -Eq 'no matching resources found|condition met'

echo "Check for any stale RBDs before deleting PVCs"
for host in $rmq_hosts; do
  echo "Check host '${host}'"
  pvcs=$(kubectl get pvc -n "${RMQ_NS}" -l release_group=${RMQ_RELEASE_GROUP} \
      -o jsonpath="{.items[*].metadata.name}")
  for pvc in $pvcs; do
    force_unmap_rbd $pvc $host
  done
done

echo "Deleting RabbitMQ volumes"
kubectl delete -n "${RMQ_NS}" pvc -l release_group="${RMQ_RELEASE_GROUP}"

echo "Scaling up RabbitMQ"
kubectl scale -n "${RMQ_NS}" --replicas=2 statefulset/"${RMQ_SS}"
kubectl rollout status -n "${RMQ_NS}" statefulset/"${RMQ_SS}" \
    --timeout="${RMQ_START_TIMEOUT}"

echo "Waiting for RabbitMQ cluster to become ready"
job_recreate "${RMQ_NS}" "${RMQ_WAIT_JOB}"

echo "Restarting RabbitMQ init jobs"
for job in $(kubectl get -n "${RMQ_NS}" jobs -l component=rabbit-init \
      --no-headers -o name | awk -F '/' '{ print $NF }'); do
  job_recreate "${RMQ_NS}" "${job}"
done

# Handle bouncing RO separately if openstack namespace
if [ "${RMQ_NS}" == "openstack" ]; then
  kubectl delete pod -n "${RMQ_NS}" -l application="ro",component="api"
fi

echo "DONE"
