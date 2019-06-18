Seaworthy: Production-grade Airship
===================================

Airship Seaworthy is a multi-node site deployment reference
and continuous integration pipeline.

The site manifests are available at
`site/seaworthy <https://opendev.org/airship/treasuremap/src/branch/master/site/seaworthy>`__.


Pipeline
--------

Airship Seaworthy pipeline automates deployment flow documented in
`Site Authoring and Deployment Guide <https://airship-treasuremap.readthedocs.io/en/latest/authoring_and_deployment.html>`__.

The pipeline is implemented as Jenkins Pipeline (Groovy), see code for the pipeline at
`Jenkinsfile <https://opendev.org/airship/treasuremap/src/branch/master/tools/gate/seaworthy/Jenkinsfile>`__.

Versions
--------

The manifest overrides (`versions.yaml <https://opendev.org/airship/treasuremap/src/branch/master/global/software/config/versions.yaml>`__)
are setup to deploy OpenStack Ocata.

The versions are kept up to date via `updater.py <https://opendev.org/airship/treasuremap/src/branch/master/tools/updater.py>`__,
a utility that updates versions.yaml latest charts and (selected) images.

Due to the limited capacity of a test environment, only Ubuntu-based images are used at the moment.

The pipeline attempts to uplift and deploy latest versions on daily bases.


Hardware
--------

While HW configuration is flexible, Airship Seaworthy reference manifests
reflect full HA deployment, similar to what might be expected in production.

Reducing number of control/compute nodes will require site overrides
to align parts of the system such as Ceph replication, etcd, etc.

Airship Seaworthy site has 6 DELL R720xd bare-metal servers:
3 control, and 3 compute nodes.
See host profiles for the servers `here <https://opendev.org/airship/treasuremap/src/branch/master/site/seaworthy/profiles/host>`__.

Control (masters)
 - cab23-r720-11
 - cab23-r720-12
 - cab23-r720-13

Compute (workers)
 - cab23-r720-14
 - cab23-r720-17
 - cab23-r720-19


Network
-------

Physical (underlay) networks are described in Drydock site configuration
`here <https://opendev.org/airship/treasuremap/src/branch/master/site/seaworthy/networks/physical/networks.yaml>`__.
It defines OOB (iLO/IPMI), untagged PXE, and multiple tagged general use networks.

Calico overlay for k8s POD networking uses IPIP mesh.

BGP peering is supported but not enabled in this setup, see
`Calico chart <https://github.com/openstack/openstack-helm-infra/blob/master/calico>`__.

