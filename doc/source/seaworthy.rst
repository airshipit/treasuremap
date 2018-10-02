Airship Seaworthy
=================

Airship Seaworthy is a multi-node site deployment reference
and continuous integration pipeline.

The site manifests are available at
`site/airship-seaworthy <https://github.com/openstack/airship-treasuremap/tree/master/site/airship-seaworthy>`__.


Pipeline
--------

Airship Seaworthy pipeline automates deployment flow documented in
`Site Authoring and Deployment Guide <https://airship-treasuremap.readthedocs.io/en/latest/authoring_and_deployment.html>`__.

The pipeline is implemented as Jenkins Pipeline (Groovy), see code for the pipeline at
`Jenkinsfile <https://github.com/openstack/airship-treasuremap/blob/master/tools/gate/Jenkinsfile>`__.

Versions
--------

The manifest overrides (`versions.yaml <https://github.com/openstack/airship-treasuremap/blob/master/global/software/config/versions.yaml>`__)
are setup to deploy OpenStack Ocata.

The versions are kept up to date via `updater.py <https://github.com/openstack/airship-treasuremap/blob/master/tools/updater.py>`__,
a utility that updates versions.yaml latest charts and (selected) images.

The pipeline attempts to uplift and deploy latest versions on daily bases.


Hardware
--------

The site has 6 DELL R720xd bare-metal servers, 4 control and 2 compute nodes.
See host profiles for the servers `here <https://github.com/openstack/airship-treasuremap/tree/master/site/airship-seaworthy/profiles/host>`__.

Control (masters)
 - cab23-r720-11
 - cab23-r720-12
 - cab23-r720-13
 - cab23-r720-14

Compute (workers)
 - cab23-r720-17
 - cab23-r720-19


Network
-------

Physical (underlay) networks are described in Drydock site configuration
`here <https://github.com/openstack/airship-treasuremap/blob/master/site/airship-seaworthy/networks/physical/networks.yaml>`__.
It defines OOB (iLO/IPMI), untagged PXE, and multiple tagged general use networks.

Calico overlay for k8s POD networking uses IPIP mesh.

BGP peering is supported but not enabled in this setup, see
`Calico chart <https://github.com/openstack/openstack-helm-infra/blob/master/calico>`__.

