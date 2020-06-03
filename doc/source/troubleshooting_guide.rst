=====================
Troubleshooting Guide
=====================

This guide provides information on troubleshooting of an Airship
environment. Debugging of any software component starts with gathering
more information about the failure, so the intention of the document
is not to describe specific issues that one can encounter, but to provide
a generic set of instructions that a user can follow to find the
root cause of the problem.

For additional support you can contact the Airship team via
`IRC or mailing list <https://www.airshipit.org/community/>`__,
use `Airship bug tracker <https://storyboard.openstack.org/#!/
project_group/Airship>`__
to search and create issues.

.. contents:: Table of Contents
    :depth: 3

---------------------
Perform Health Checks
---------------------

The first step in troubleshooting an Airship deployment is to identify unhealthy
services by performing health checks.

Verify Peering is established
-----------------------------

::

    sudo /opt/cni/bin/calicoctl node status

    Calico process is running.
    IPv4 BGP status
    +--------------+-----------+-------+------------+-------------+
    | PEER ADDRESS | PEER TYPE | STATE | SINCE | INFO |
    +--------------+-----------+-------+------------+-------------+
    | 172.29.0.2 | global | up | 2018-05-22 | Established |
    | 172.29.0.3 | global | up | 2018-05-22 | Established |
    +--------------+-----------+-------+------------+-------------+
    IPv6 BGP status No IPv6 peers found.

Verify that **STATE** is ``up`` and **INFO** is ``Established``. However, if
**STATE** is ``start`` and **INFO** is ``Connect``, peering has failed.

For more information on Calico troubleshooting, visit the
`Calico Documentation <https://docs.projectcalico.org/introduction/>`__

Verify the Health of Kubernetes
-------------------------------

::

    # Verify that for all nodes, STATE is Ready.
    #
    # Note: After a reboot, it may take as long as 30 minutes for
    # a node to stabilize and reach a Ready condition.
    kubectl get nodes

    # Verify that liveness probes for all pods are working.
    # This command exposes pods whose liveness probe is failing.
    kubectl get pods --all-namespaces | grep Running | grep 0/

    # Verify that all pods are in the Running or Completed state.
    # This command exposes pods that are not running or completed.
    kubectl get pods --all-namespaces | grep -v Running | Completed

    # Look for crashed pods.
    kubectl get pods --all-namespaces -o wide | grep Crash

    # Check the health of core services.
    kubectl get pods --all-namespaces -o wide | grep core
    kubectl get services --all-namespaces | grep core

    # Check the health of proxy services.
    kubectl get pods --all-namespaces -o wide | grep proxy

    # Get all pod details.
    kubectl get pods --all-namespaces -o wide -w

    # Look for failed jobs.
    kubectl get jobs – --all-namespaces -o wide | grep -v "1    1"

Verify the Health of OpenStack
------------------------------

Check OpenStack's health by issuing the following commands at the terminal,
in order to do so you must have a set an OpenStack RC file, details
`here <https://docs.openstack.org/mitaka/cli-reference/common/cli_set_
environment_variables_using_openstack_rc.html#download-and-source-the-
openstack-rc-file>`__

::

    # Verify Keystone by requesting a token.
    openstack token issue

    # Verify networks.
    openstack network list

    # Verify subnets.
    openstack subnet list

    # Verify VMs.
    openstack server list

    # Verify compute hypervisors.
    openstack hypervisor list

    # Verify Images
    openstack image list

Check for kube-proxy iptables NAT Issues
----------------------------------------

::

    # Check the iptables and make sure the IP addresses are the same:
    % iptables -n -t nat -L | grep coredns
    % kubectl -n kube-system get -o wide pod | grep coredns

-----------------------
Configuring Airship CLI
-----------------------

Many commands from this guide use Airship CLI, this section describes
how to get it configured on your environment.

::

    git clone https://opendev.org/airship/treasuremap
    cd treasuremap/
    # List available tags.
    git tag --list
    # Switch to the version your site is using.
    git checkout {your-tag}
    # Go back to a previous directory.
    cd ..
    # Run it without arguments to get a help message.
    sudo ./treasuremap/tools/airship

---------------------
Manifests Preparation
---------------------

When you do any configuration changes to the manifests, there are a few
commands that you can use to validate the changes without uploading them
to the Airship environment.

Run ``lint`` command for your site; it helps to catch the errors related
to documents duplication, broken references, etc.

Example:

::

    sudo ./treasuremap/tools/airship pegleg site -r airship-treasuremap/ \
        lint {site-name}

If you create configuration overrides or do changes to substitutions,
it is recommended to run ``render`` command this command merges the layers
and renders all substitutions. This allows finding what parameters are
passed to Helm as overrides for Charts' defaults.

Example:

::

    # Saves the result into rendered.txt file.
    sudo ./treasuremap/tools/airship pegleg site -r treasuremap/ \
        render -o rendered.txt ${SITE}

------------------
Deployment Failure
------------------

During the deployment, it is important to identify a specific step
where it fails, there are two major deployment steps:

1. **Drydock build**: deploys Operating System.
2. **Armada build**: deploys Helm Charts.

After `Configuring Airship CLI`_, setup credentials for accessing
Shipyard; the password is stored in ``ucp_shipyard_keystone_password``
secret, you can find it in
``site/seaworthy/secrets/passphrases/ucp_shipyard_keystone_password.yaml``
configuration file of your site.

::

    export OS_USERNAME=shipyard
    export OS_PASSWORD={shipyard_password}

Now you can use the following commands to access Shipyard:

::

    # Get all actions that were executed on you environment.
    sudo ./treasuremap/tools/airship shipyard get actions
    # Show all the steps within the action.
    sudo ./treasuremap/tools/airship shipyard describe action/{action_id}
    # Get a bit more details on the step.
    sudo ./treasuremap/tools/airship shipyard describe step/{action_id}/armada_build
    # Print the logs from the step.
    sudo ./treasuremap/tools/airship shipyard logs step/{action_id}/armada_build


After the failed step is determined, you can access the logs of a specific
service (e.g., drydock-api/maas or armada-api) to get more information
on the failure, note that there may be multiple pods of a single service
running, you need to check all of them to find where the most recent
logs are available.

Example of accessing Armada API logs:

::

   # Get all pods running on the cluster and find a name of the pod you are
   # interested in.
   kubectl get pods -o wide --all-namespaces

   # See the logs of specific pod.
   kubectl logs -n ucp -f --tail 200 armada-api-d5f757d5-6z6nv

In some cases you want to restart your pod, there is no dedicated command for
that in Kubernetes. However, you can delete the pod, it will be restarted
by Kubernetes to satisfy replication factor.

::

    # Restart Armada API service.
    kubectl delete pod -n ucp armada-api-d5f757d5-6z6nv

----
Ceph
----

Many stateful services in Airship rely on Ceph to function correctly.
For more information on Ceph debugging follow an official
`Ceph debugging guide <http://docs.ceph.com/docs/mimic/rados/troubleshooting/log-and-debug/>`__.

Although Ceph tolerates failures of multiple OSDs, it is important
to make sure that your Ceph cluster is healthy.

::

    # Get a name of Ceph Monitor pod.
    CEPH_MON=$(sudo kubectl get pods --all-namespaces -o=name | \
        grep ceph-mon | sed -n 1p | sed 's|pod/||')
    # Get the status of the Ceph cluster.
    sudo kubectl exec -it -n ceph ${CEPH_MON} -- ceph -s

Cluster is in a helthy state when ``health`` parameter is set to ``HEALTH_OK``.

When the cluster is unhealthy, and some Placement Groups are reported to be in
degraded or down states, determine the problem by inspecting the logs of
Ceph OSD that is down using ``kubectl``.

::

    # Get a name of Ceph Monitor pod.
    CEPH_MON=$(sudo kubectl get pods --all-namespaces -o=name | \
        grep ceph-mon | sed -n 1p | sed 's|pod/||')
    # List a hierarchy of OSDs in the cluster to see what OSDs are down.
    sudo kubectl exec -it -n ceph ${CEPH_MON} -- ceph osd tree

There are a few other commands that may be useful during the debugging:

::

    # Get a name of Ceph Monitor pod.
    CEPH_MON=$(sudo kubectl get pods --all-namespaces -o=name | \
        grep ceph-mon | sed -n 1p | sed 's|pod/||')

    # Get a detailed information on the status of every Placement Group.
    sudo kubectl exec -it -n ceph ${CEPH_MON} -- ceph pg dump

    # List allocated block devices.
    sudo kubectl exec -it -n ceph ${CEPH_MON} -- rbd ls
    # See what client uses the device.
    sudo kubectl exec -it -n ceph ${CEPH_MON} -- rbd status \
        kubernetes-dynamic-pvc-e71e65a9-3b99-11e9-bf31-e65b6238af01

    # List all Ceph block devices mounted on a specific host.
    mount | grep rbd

    # Exec into the Monitor pod
    MON_POD=$(sudo kubectl get --no-headers pods -n=ceph \
        l="application=ceph,component=mon" | awk '{ print $1; exit }')
    echo $MON_POD
    sudo kubectl exec -n ceph ${MON_POD} -- ceph -s
