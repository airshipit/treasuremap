#!/bin/bash
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

# The full site is deployed by the Armada of the site when the rest of the
# nodes have joined the cluster (see
# tools/gate/playbooks/airliner-multinode-deploy.yaml): the nodes are
# labeled for the site components (as a node deployment does) and the
# kubeadm-full-site manifest is applied with the Armada API (the documents
# are uploaded to Deckhand). The cluster configuration (kubeadm-scaled) is
# applied to the nodes by the anchor, the genesis Ceph is scaled out to the
# control plane nodes.

set -ex

: "${CEPH_TIMEOUT:="2400"}"

# shellcheck source=tools/deployment/airliner/common.sh
source ./tools/deployment/airliner/common.sh

# Ceph and the Airship components run on the control plane nodes
CEPH_NODES=$(awk '$3 == "control-plane" { print $1 }' <<< "${NODES}")
CEPH_NODE_COUNT=$(wc -w <<< "${CEPH_NODES}")
for node in ${CEPH_NODES}; do
  kubectl label node "${node}" --overwrite ceph-mon=enabled ceph-osd=enabled \
    ucp-control-plane=enabled
done

ceph_json() {
  kubectl -n ceph exec deployment/rook-ceph-tools -- ceph "$@" -f json 2> /dev/null
}

# The genesis Ceph gets the OSDs of the labeled nodes (all nodes are used):
# they must be up before the pools are scaled out to 3 replicas, otherwise
# the placement groups have less replicas than required and the volumes of
# the Airship components hang. Rook prepares the OSDs of new nodes when it
# reconciles the cluster, node labels don't trigger it: the operator is
# restarted, it reconciles the cluster when it starts.
kubectl -n rook-ceph rollout restart deployment/rook-ceph-operator
kubectl -n rook-ceph rollout status deployment/rook-ceph-operator --timeout=600s
END=$(($(date +%s) + CEPH_TIMEOUT))
until ceph_json osd stat | python3 -c '
import json, sys
stat = json.load(sys.stdin)
count = int(sys.argv[1])
sys.exit(not (stat["num_osds"] == count and stat["num_up_osds"] == count
              and stat["num_in_osds"] == count))
' "${CEPH_NODE_COUNT}"; do
  if [[ $(date +%s) -ge ${END} ]]; then
    echo "The OSDs of ${CEPH_NODES//$'\n'/ } are not up in ${CEPH_TIMEOUT}s" >&2
    kubectl -n ceph get pods -o wide || true
    kubectl -n ceph exec deployment/rook-ceph-tools -- ceph status || true
    exit 1
  fi
  sleep 15
done
kubectl -n ceph exec deployment/rook-ceph-tools -- ceph osd tree

./tools/deployment/airliner/050-armada-apply.sh

# Rook scales Ceph out after the chart is deployed: wait until the mons are
# in quorum and the OSDs are up and in on all the nodes, the pools keep a
# replica per node.
ceph_scaled() {
  local count status pools
  count=$(wc -w <<< "${CEPH_NODES}")
  status=$(kubectl -n ceph exec deployment/rook-ceph-tools -- ceph status -f json 2> /dev/null) || return 1
  pools=$(kubectl -n ceph exec deployment/rook-ceph-tools -- ceph osd pool ls detail -f json 2> /dev/null) || return 1
  python3 -c '
import json, sys
count, status, pools = int(sys.argv[1]), json.loads(sys.argv[2]), json.loads(sys.argv[3])
osdmap = status["osdmap"]
sys.exit(not (status["monmap"]["num_mons"] == count
              and len(status["quorum_names"]) == count
              and osdmap["num_osds"] == count
              and osdmap["num_up_osds"] == count
              and osdmap["num_in_osds"] == count
              and pools and all(p["size"] == count for p in pools)))
' "${count}" "${status}" "${pools}"
}
END=$(($(date +%s) + CEPH_TIMEOUT))
until ceph_scaled; do
  if [[ $(date +%s) -ge ${END} ]]; then
    echo "Ceph is not scaled out to ${CEPH_NODES//$'\n'/ } in ${CEPH_TIMEOUT}s" >&2
    kubectl -n ceph get cephcluster,cephblockpool,pods -o wide || true
    kubectl -n ceph exec deployment/rook-ceph-tools -- ceph status || true
    exit 1
  fi
  sleep 15
done
kubectl -n ceph get cephcluster ceph -o wide
kubectl -n ceph exec deployment/rook-ceph-tools -- ceph status
kubectl -n ceph exec deployment/rook-ceph-tools -- ceph osd tree
kubectl -n ceph exec deployment/rook-ceph-tools -- ceph osd pool ls detail

# A volume of the default StorageClass is provisioned by the scaled Ceph
kubectl apply -f - << EOT
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-check
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOT
kubectl -n default wait pvc/storage-check --for=jsonpath='{.status.phase}'=Bound --timeout=300s
kubectl -n default delete pvc storage-check --wait
kubectl get armadacharts -A -o wide
