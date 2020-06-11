..
      Licensed under the Apache License, Version 2.0 (the "License"); you may
      not use this file except in compliance with the License. You may obtain
      a copy of the License at

          http://www.apache.org/licenses/LICENSE-2.0

      Unless required by applicable law or agreed to in writing, software
      distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
      WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
      License for the specific language governing permissions and limitations
      under the License.

--------------------
Troubleshooting Ceph
--------------------

.. contents:: Table of Contents
    :depth: 3

Initial Troubleshooting
-----------------------

Many stateful services in Airship rely on Ceph to function correctly.
For more information on Ceph debugging follow the official
`Ceph debugging guide <http://docs.ceph.com/docs/mimic/rados/troubleshooting/log-and-debug/>`__.

Although Ceph tolerates failures of multiple OSDs, it is important
to make sure that your Ceph cluster is healthy.

::

    # Many commands require the name of the Ceph monitor pod, use the following
    # shell command to assign the pod name to an environment variable for ease
    # of use.
    CEPH_MON=$(sudo kubectl get --no-headers pods -n=ceph \
        l="application=ceph,component=mon" | awk '{ print $1; exit }')

    # Get the status of the Ceph cluster.
    sudo kubectl exec -it -n ceph ${CEPH_MON} -- ceph -s

    # Get the health of the Ceph cluster
    sudo kubectl -n ceph exec ${CEPH_MON} ceph health detail

The health indicators for Ceph are:

* `HEALTH_OK`: Indicates the cluster is healthy
* `HEALTH_WARN`: Indicates there may be an issue, but all the data stored in the
  cluster remains accessible. In some cases Ceph will return to `HEALTH_OK`
  automatically, i.e. when Ceph finishes the rebalancing process
* `HEALTH_ERR`: Indicates a more serious problem that requires immediate
  attention as a part or all of your data has become inaccessible

When the cluster is unhealthy, and some Placement Groups are reported to be in
degraded or down states, determine the problem by inspecting the logs of
Ceph OSD that is down using ``kubectl``.

There are a few other commands that may be useful during the debugging:

::

    # Make sure your CEPH_MON variable is set, mentioned above.
    echo ${CEPH_MON}

    # List a hierarchy of OSDs in the cluster to see what OSDs are down.
    sudo kubectl exec -it -n ceph ${CEPH_MON} -- ceph osd tree

    # Get a detailed information on the status of every Placement Group.
    sudo kubectl exec -it -n ceph ${CEPH_MON} -- ceph pg dump

    # List allocated block devices.
    sudo kubectl exec -it -n ceph ${CEPH_MON} -- rbd ls

    # See what client uses the device.
    # Note: The pvc name will be different in your cluster
    sudo kubectl exec -it -n ceph ${CEPH_MON} -- rbd status \
        kubernetes-dynamic-pvc-e71e65a9-3b99-11e9-bf31-e65b6238af01

    # List all Ceph block devices mounted on a specific host.
    mount | grep rbd

    # Exec into the Monitor pod
    sudo kubectl exec -it -n ceph ${CEPH_MON} -- ceph -s
