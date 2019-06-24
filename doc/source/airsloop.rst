Airsloop: Simple Bare-Metal Airship
===================================

Airsloop is a two bare-metal server site deployment reference.

The goal of this site is to be used as a reference for simplified Airship
deployments with one control and one or more compute nodes.

It is recommended to get familiar with the `Site Authoring and Deployment Guide`_
documentation before deploying Airsloop in the lab. Most steps and concepts
including setting up the Genesis node are the same.

.. _Site Authoring and Deployment Guide: https://airship-treasuremap.readthedocs.io/en/latest/authoring_and_deployment.html


.. image:: diagrams/airsloop-architecture.png


Various resiliency and security features are tuned down via configuration.

 * Two bare-metal server setup with 1 control, and 1 compute.
   Most components are scaled to a single replica and doesn't carry
   any HA as there is only a single control plane host.
 * No requirements for DNS/certificates.
   HTTP and internal cluster DNS is used.
 * Ceph set to use the single disk.
   This generally provides minimalistic no-touch Ceph deployment.
   No replication of Ceph data (single copy).
 * Simplified networking (no bonding).
   Two network interfaces are used by default (flat PXE, and DATA network
   with VLANs for OAM, Calico, Storage, and OpenStack Overlay).
 * Generic hostnames used (airsloop-control-1, airsloop-compute-1) that
   simplifies generation of k8s certificates.
 * Usage of standard Ubuntu 16.04 GA kernel (as oppose to HWE).


Airsloop site manifests are available at
`site/airsloop <https://opendev.org/airship/treasuremap/src/branch/master/site/airsloop>`__.


Hardware
--------

While HW configuration is flexible, Airsloop reference manifests
reflect a single control and a single compute node. The aim of
this is to create a minimalistic lab/demo reference environment.

Increasing the number of compute nodes will require site overrides
to align parts of the system such as Ceph OSDs, etcd, etc.

See host profiles for the servers
`here <https://opendev.org/airship/treasuremap/src/branch/master/site/airsloop/profiles/host>`__.

+------------+-------------------------+
| Node       | Hostnames               |
+============+=========================+
| control    | airsloop-control-1      |
+------------+-------------------------+
| compute    | airsloop-compute-1      |
+------------+-------------------------+


Network
-------

Physical (underlay) networks are described in Drydock site configuration
`here <https://opendev.org/airship/treasuremap/src/branch/master/site/airsloop/networks/physical/networks.yaml>`__.

It defines OOB (iLO/IPMI), untagged PXE, and multiple tagged general use networks.
Also no bonded interfaces are used in Airsloop deployment.

The networking reference is simplified compared to Airship Seaworthy
site. There are only two NICs required (excluding oob), one for PXE
and another one for the rest of the networks separated using VLAN segmentation.

Below is the reference network configuration:

+------------+------------+-----------+---------------+
| NICs       | VLANs      | Names     |     CIDRs     |
+============+============+===========+===============+
| oob        | N/A        | oob       |10.22.104.0/24 |
+------------+------------+-----------+---------------+
| pxe        | N/A        | pxe       |10.22.70.0/24  |
+------------+------------+-----------+---------------+
|            | 71         | oam       |10.22.71.0/24  |
|            +------------+-----------+---------------+
|            | 72         | calico    |10.22.72.0/24  |
| data       +------------+-----------+---------------+
|            | 73         | storage   |10.22.73.0/24  |
|            +------------+-----------+---------------+
|            | 74         | overlay   |10.22.74.0/24  |
+------------+------------+-----------+---------------+

Calico overlay for k8s POD networking uses IPIP mesh.

Storage
-------

Because Airsloop is a minimalistic deployment the required number of disks is just
one per node. That disk is not only used by the OS but also by Ceph Journals and OSDs.
The way that this is achieved is by using directories and not extra
disks for Ceph storage. Ceph OSD configuration can be changed in a `Ceph chart override <https://opendev.org/airship/treasuremap/src/branch/master/type/sloop/charts/ucp/ceph/ceph-osd.yaml>`__.

The following Ceph chart configuration is used:

.. code-block:: yaml

    osd:
      - data:
          type: directory
          location: /var/lib/openstack-helm/ceph/osd/osd-one
        journal:
          type: directory
          location: /var/lib/openstack-helm/ceph/osd/journal-one


Host Profiles
-------------

Host profiles in Airship are tightly coupled with the hardware profiles.
That means every disk or interface which is described in host profiles
should have a corresponding reference to the hardware profile which is
being used.

Airship always identifies every NIC or disk by its PCI or
SCSI address and that means that the interfaces and the disks that are
defined in host and hardware profiles should have the correct PCI and
SCSI addresses objectively.

Let's give an example by following the host profile of Airsloop site.

In this `Host Profile <https://opendev.org/airship/treasuremap/src/branch/master/site/airsloop/profiles/host/compute.yaml>`__
is defined that the slave interface that will be used for the pxe
boot will be the pxe_nic01. That means a corresponding entry should
exist in this `Hardware Profile <https://opendev.org/airship/treasuremap/src/branch/master/site/airsloop/profiles/hardware/dell_r720xd.yaml>`__
which it does. So when drydock and maas try to deploy the node it will
identify the interface by the PCI address that is written in the
Hardware profile.

A simple way to find out which PCI or SCSI address corresponds to which
NIC or Disk is to use the lshw command. More information about that
command can be found `Here <https://linux.die.net/man/1/lshw>`__.

Extend Cluster
--------------

This section describes what changes need to be made to the existing
manifests of Airsloop for the addition of an extra compute node to the
cluster.

First and foremost the user should go to the `nodes.yaml <https://opendev.org/airship/treasuremap/src/branch/master/site/airsloop/baremetal/nodes.yaml>`__
file and add an extra section for the new compute node.

The next step is to add a similar section as the existing
airsloop-compute-1 section to the `pki-catalog.yaml <https://opendev.org/airship/treasuremap/src/branch/master/site/airsloop/pki/pki-catalog.yaml>`__.
This is essential for the correct generation of certificates and the
correct communication between the nodes in the cluster.

Also every time the user adds an extra compute node to the cluster then the
number of OSDs that are managed by this manifest `Ceph-client <https://opendev.org/airship/treasuremap/src/branch/master/site/airsloop/software/charts/osh/ceph/ceph-client.yaml>`__
should be increased by one.

Last step is to regenerate the certificates which correspond to this
`certificates.yaml <https://opendev.org/airship/treasuremap/src/branch/master/site/airsloop/secrets/certificates/certificates.yaml>`__
file so the changes in the pki-catalog.yaml file takes place.
This can be done through the promenade CLI.

Getting Started
---------------

**Update Site Manifests.**

Carefully review site manifests (site/airsloop) and update the configuration
to match the hardware, networking setup and other specifics of the lab.

See more details at `Site Authoring and Deployment Guide`_.

.. note:: Many manifest files (YAMLs) contain documentation in comments
          that instruct what changes are required for specific sections.

1. Build Site Documents

.. code-block:: bash

    tools/airship pegleg site -r /target collect airsloop -s collect

    mkdir certs
    tools/airship promenade generate-certs -o /target/certs /target/collect/*.yaml

    mkdir bundle
    tools/airship promenade build-all -o /target/bundle /target/collect/*.yaml /target/certs/*.yaml

See more details at `Building Site documents`_, use site ``airsloop``.

.. _Building Site documents: https://airship-treasuremap.readthedocs.io/en/latest/authoring_and_deployment.html#building-site-documents


2. Deploy Genesis

Deploy the Genesis node, see more details at `Genesis node`_.

.. _Genesis node: https://airship-treasuremap.readthedocs.io/en/latest/authoring_and_deployment.html#genesis-node

Genesis is the first node in the cluster and serves as a control node.
In Airsloop configuration Genesis is the only control node (airsloop-control-1).

Airsloop is using non-bonded network interfaces:

.. code-block:: bash

    auto lo
    iface lo inet loopback

    auto eno1
    iface eno1 inet static
      address 10.22.70.21/24

    auto enp67s0f0
    iface enp67s0f0 inet manual

    auto enp67s0f0.71
    iface enp67s0f0.71 inet static
      address 10.22.71.21/24
      gateway 10.22.71.1
      dns-nameservers 8.8.8.8 8.8.4.4
      vlan-raw-device enp67s0f0
      vlan_id 71

    auto enp67s0f0.72
    iface enp67s0f0.72 inet static
      address 10.22.72.21/24
      vlan-raw-device enp67s0f0
      vlan_id 72

    auto enp67s0f0.73
    iface enp67s0f0.73 inet static
      address 10.22.73.21/24
      vlan-raw-device enp67s0f0
      vlan_id 73

    auto enp67s0f0.74
    iface enp67s0f0.74 inet static
      address 10.22.74.21/24
      vlan-raw-device enp67s0f0
      vlan_id 74

Execute Genesis bootstrap script on the Genesis server.

.. code-block:: bash

     sudo ./genesis.sh


3. Deploy Site

.. code-block:: bash

    tools/airship shipyard create configdocs design --directory=/target/collect
    tools/airship shipyard commit configdocs

    tools/airship shipyard create action deploy_site

    tools/shipyard get actions

See more details at `Deploy Site with Shipyard`_.

.. _Deploy Site with Shipyard: https://airship-treasuremap.readthedocs.io/en/latest/authoring_and_deployment.html#deploy-site-with-shipyard


Deploying Behind a Proxy
------------------------

The following documents show the main differences you need to make in order to have
airsloop run behind a proxy.

.. note::

    The "-" sign refers to a line that needs to be omitted (replaced), and the "+" sign refers to a
    line replacing the omitted line, or simply a line that needs to be added to your yaml.

Under site/airsloop/software/charts/osh/openstack-glance/ create a glance.yaml file as follows:

.. code-block:: yaml

    ---
    schema: armada/Chart/v1
    metadata:
      schema: metadata/Document/v1
      replacement: true
      name: glance
      layeringDefinition:
        abstract: false
        layer: site
        parentSelector:
          name: glance-type
        actions:
          - method: merge
            path: .
      storagePolicy: cleartext
    data:
      test:
        enabled: false
    ...

Under site/airsloop/software/config/ create a versions.yaml file in the following format:

.. code-block:: yaml

    ---
    data:
      charts:
        kubernetes:
          apiserver:
            proxy_server: proxy.example.com:8080
          apiserver-htk:
            proxy_server: proxy.example.com:8080
          calico:
            calico:
              proxy_server: proxy.example.com:8080
            calico-htk:
              proxy_server: proxy.example.com:8080
            etcd:
              proxy_server: proxy.example.com:8080
            etcd-htk:
              proxy_server: proxy.example.com:8080
          controller-manager:
            proxy_server: proxy.example.com:8080
          controller-manager-htk:
            proxy_server: proxy.example.com:8080
          coredns:
            proxy_server: proxy.example.com:8080
          coredns-htk:
            proxy_server: proxy.example.com:8080
          etcd:
            proxy_server: proxy.example.com:8080
          etcd-htk:
            proxy_server: proxy.example.com:8080
          haproxy:
            proxy_server: proxy.example.com:8080
          haproxy-htk:
            proxy_server: proxy.example.com:8080
          ingress:
            proxy_server: proxy.example.com:8080
          ingress-htk:
            proxy_server: proxy.example.com:8080
          proxy:
            proxy_server: proxy.example.com:8080
          proxy-htk:
            proxy_server: proxy.example.com:8080
          scheduler:
            proxy_server: proxy.example.com:8080
          scheduler-htk:
            proxy_server: proxy.example.com:8080
        osh:
          barbican:
            proxy_server: proxy.example.com:8080
          cinder:
            proxy_server: proxy.example.com:8080
          cinder-htk:
            proxy_server: proxy.example.com:8080
          glance:
            proxy_server: proxy.example.com:8080
          glance-htk:
            proxy_server: proxy.example.com:8080
          heat:
            proxy_server: proxy.example.com:8080
          heat-htk:
            proxy_server: proxy.example.com:8080
          helm_toolkit:
            proxy_server: proxy.example.com:8080
          horizon:
            proxy_server: proxy.example.com:8080
          horizon-htk:
            proxy_server: proxy.example.com:8080
          ingress:
            proxy_server: proxy.example.com:8080
          ingress-htk:
            proxy_server: proxy.example.com:8080
          keystone:
            proxy_server: proxy.example.com:8080
          keystone-htk:
            proxy_server: proxy.example.com:8080
          libvirt:
            proxy_server: proxy.example.com:8080
          libvirt-htk:
            proxy_server: proxy.example.com:8080
          mariadb:
            proxy_server: proxy.example.com:8080
          mariadb-htk:
            proxy_server: proxy.example.com:8080
          memcached:
            proxy_server: proxy.example.com:8080
          memcached-htk:
            proxy_server: proxy.example.com:8080
          neutron:
            proxy_server: proxy.example.com:8080
          neutron-htk:
            proxy_server: proxy.example.com:8080
          nova:
            proxy_server: proxy.example.com:8080
          nova-htk:
            proxy_server: proxy.example.com:8080
          openvswitch:
            proxy_server: proxy.example.com:8080
          openvswitch-htk:
            proxy_server: proxy.example.com:8080
          rabbitmq:
            proxy_server: proxy.example.com:8080
          rabbitmq-htk:
            proxy_server: proxy.example.com:8080
          tempest:
            proxy_server: proxy.example.com:8080
          tempest-htk:
            proxy_server: proxy.example.com:8080
        osh_infra:
          elasticsearch:
            proxy_server: proxy.example.com:8080
          fluentbit:
            proxy_server: proxy.example.com:8080
          fluentd:
            proxy_server: proxy.example.com:8080
          grafana:
            proxy_server: proxy.example.com:8080
          helm_toolkit:
            proxy_server: proxy.example.com:8080
          kibana:
            proxy_server: proxy.example.com:8080
          nagios:
            proxy_server: proxy.example.com:8080
          nfs_provisioner:
            proxy_server: proxy.example.com:8080
          podsecuritypolicy:
            proxy_server: proxy.example.com:8080
          prometheus:
            proxy_server: proxy.example.com:8080
          prometheus_alertmanager:
            proxy_server: proxy.example.com:8080
          prometheus_kube_state_metrics:
            proxy_server: proxy.example.com:8080
          prometheus_node_exporter:
            proxy_server: proxy.example.com:8080
          prometheus_openstack_exporter:
            proxy_server: proxy.example.com:8080
          prometheus_process_exporter:
            proxy_server: proxy.example.com:8080
        ucp:
          armada:
            proxy_server: proxy.example.com:8080
          armada-htk:
            proxy_server: proxy.example.com:8080
          barbican:
            proxy_server: proxy.example.com:8080
          barbican-htk:
            proxy_server: proxy.example.com:8080
          ceph-client:
            proxy_server: proxy.example.com:8080
          ceph-htk:
            proxy_server: proxy.example.com:8080
          ceph-mon:
            proxy_server: proxy.example.com:8080
          ceph-osd:
            proxy_server: proxy.example.com:8080
          ceph-provisioners:
            proxy_server: proxy.example.com:8080
          ceph-rgw:
            proxy_server: proxy.example.com:8080
          deckhand:
            proxy_server: proxy.example.com:8080
          deckhand-htk:
            proxy_server: proxy.example.com:8080
          divingbell:
            proxy_server: proxy.example.com:8080
          divingbell-htk:
            proxy_server: proxy.example.com:8080
          drydock:
            proxy_server: proxy.example.com:8080
          drydock-htk:
            proxy_server: proxy.example.com:8080
          ingress:
            proxy_server: proxy.example.com:8080
          ingress-htk:
            proxy_server: proxy.example.com:8080
          keystone:
            proxy_server: proxy.example.com:8080
          keystone-htk:
            proxy_server: proxy.example.com:8080
          maas:
            proxy_server: proxy.example.com:8080
          maas-htk:
            proxy_server: proxy.example.com:8080
          mariadb:
            proxy_server: proxy.example.com:8080
          mariadb-htk:
            proxy_server: proxy.example.com:8080
          memcached:
            proxy_server: proxy.example.com:8080
          memcached-htk:
            proxy_server: proxy.example.com:8080
          postgresql:
            proxy_server: proxy.example.com:8080
          postgresql-htk:
            proxy_server: proxy.example.com:8080
          promenade:
            proxy_server: proxy.example.com:8080
          promenade-htk:
            proxy_server: proxy.example.com:8080
          rabbitmq:
            proxy_server: proxy.example.com:8080
          rabbitmq-htk:
            proxy_server: proxy.example.com:8080
          shipyard:
            proxy_server: proxy.example.com:8080
          shipyard-htk:
            proxy_server: proxy.example.com:8080
          tenant-ceph-client:
            proxy_server: proxy.example.com:8080
          tenant-ceph-htk:
            proxy_server: proxy.example.com:8080
          tenant-ceph-mon:
            proxy_server: proxy.example.com:8080
          tenant-ceph-osd:
            proxy_server: proxy.example.com:8080
          tenant-ceph-provisioners:
            proxy_server: proxy.example.com:8080
          tenant-ceph-rgw:
            proxy_server: proxy.example.com:8080
          tiller:
            proxy_server: proxy.example.com:8080
          tiller-htk:
            proxy_server: proxy.example.com:8080
    metadata:
      name: software-versions
      replacement: true
      layeringDefinition:
        abstract: false
        layer: site
        parentSelector:
          name: software-versions-global
        actions:
          - method: merge
            path: .
      storagePolicy: cleartext
      schema: metadata/Document/v1
    schema: pegleg/SoftwareVersions/v1
    ...

Update site/airsloop/networks/common-addresses.yaml to add the proxy information as follows:

.. code-block:: diff

       # settings are correct and reachable in your environment; otherwise update
       # them with the correct values for your environment.
       proxy:
    -    http: ""
    -    https: ""
    -    no_proxy: []
    +    http: "proxy.example.com:8080"
    +    https: "proxy.example.com:8080"
    +    no_proxy:
    +      - 127.0.0.1

Under site/airsloop/software/charts/ucp/ create the file maas.yaml with the following format:

.. code-block:: yaml

    ---
    # This file defines site-specific deviations for MaaS.
    schema: armada/Chart/v1
    metadata:
      schema: metadata/Document/v1
      replacement: true
      name: ucp-maas
      layeringDefinition:
        abstract: false
        layer: site
        parentSelector:
          name: ucp-maas-type
        actions:
          - method: merge
            path: .
      storagePolicy: cleartext
    data:
        values:
          conf:
            maas:
              proxy:
                proxy_enabled: true
                peer_proxy_enabled: true
                proxy_server: 'http://proxy.example.com:8080'
    ...

Under site/airsloop/software/charts/ucp/ create a promenade.yaml file in the following format:

.. code-block:: yaml

    ---
    # This file defines site-specific deviations for Promenade.
    schema: armada/Chart/v1
    metadata:
      schema: metadata/Document/v1
      replacement: true
      name: ucp-promenade
      layeringDefinition:
        abstract: false
        layer: site
        parentSelector:
          name: ucp-promenade-type
        actions:
          - method: merge
            path: .
      storagePolicy: cleartext
    data:
      values:
        pod:
          env:
            promenade_api:
              - name: http_proxy
                value: http://proxy.example.com:8080
              - name: https_proxy
                value: http://proxy.example.com:8080
              - name: no_proxy
                value: "127.0.0.1,localhost,kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster.local,.cluster.local"
              - name: HTTP_PROXY
                value: http://proxy.example.com:8080
              - name: HTTP_PROXY
                value: http://proxy.example.com:8080
              - name: HTTPS_PROXY
                value: http://proxy.example.com:8080
              - name: NO_PROXY
                value: "127.0.0.1,localhost,kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster.local,.cluster.local"
    ...

