Site Authoring and Deployment Guide
===================================

The document contains the instructions for standing up a greenfield
Airship site. This can be broken down into two high-level pieces:

1. **Site authoring guide(s)**: Describes how to craft site manifests
   and configs required to perform a deployment. The primary site
   authoring guide is for deploying Airship sites, where OpenStack
   is the target platform deployed on top of Airship.
2. **Deployment guide(s)**: Describes how to apply site manifests for a
   given site.

This document is an "all in one" site authoring guide + deployment guide
for a standard Airship deployment. For the most part, the site
authoring guidance lives within ``seaworthy`` reference site in the
form of YAML comments.

Support
-------

Bugs may be viewed and reported at the following locations, depending on
the component:

-  OpenStack Helm: `OpenStack Storyboard group
   <https://storyboard.openstack.org/#!/project_group/64>`__

-  Airship: Bugs may be filed using OpenStack Storyboard for specific
   projects in `Airship
   group <https://storyboard.openstack.org/#!/project_group/85>`__:

    -  `Airship Armada <https://storyboard.openstack.org/#!/project/1002>`__
    -  `Airship
       Deckhand <https://storyboard.openstack.org/#!/project/1004>`__
    -  `Airship
       Divingbell <https://storyboard.openstack.org/#!/project/1001>`__
    -  `Airship
       Drydock <https://storyboard.openstack.org/#!/project/1005>`__
    -  `Airship MaaS <https://storyboard.openstack.org/#!/project/1007>`__
    -  `Airship Pegleg <https://storyboard.openstack.org/#!/project/1008>`__
    -  `Airship
       Promenade <https://storyboard.openstack.org/#!/project/1009>`__
    -  `Airship
       Shipyard <https://storyboard.openstack.org/#!/project/1010>`__
    -  `Airship Treasuremap
       <https://storyboard.openstack.org/#!/project/airship/treasuremap>`__

Terminology
-----------

**Cloud**: A platform that provides a standard set of interfaces for
`IaaS <https://en.wikipedia.org/wiki/Infrastructure_as_a_service>`__
consumers.

**OSH**: (`OpenStack Helm <https://docs.openstack.org/openstack-helm/latest/>`__) is a
collection of Helm charts used to deploy OpenStack on Kubernetes.

**Helm**: (`Helm <https://helm.sh/>`__) is a package manager for Kubernetes.
Helm Charts help you define, install, and upgrade Kubernetes applications.

**Undercloud/Overcloud**: Terms used to distinguish which cloud is
deployed on top of the other. In Airship sites, OpenStack (overcloud)
is deployed on top of Kubernetes (undercloud).

**Airship**: A specific implementation of OpenStack Helm charts that deploy
Kubernetes. This deployment is the primary focus of this document.

**Control Plane**: From the point of view of the cloud service provider,
the control plane refers to the set of resources (hardware, network,
storage, etc.) configured to provide cloud services for customers.

**Data Plane**: From the point of view of the cloud service provider,
the data plane is the set of resources (hardware, network, storage,
etc.) configured to run consumer workloads. When used in this document,
"data plane" refers to the data plane of the overcloud (OSH).

**Host Profile**: A host profile is a standard way of configuring a bare
metal host. It encompasses items such as the number of bonds, bond slaves,
physical storage mapping and partitioning, and kernel parameters.

Versioning
----------

Airship reference manifests are delivered monthly as release tags in the
`Treasuremap <https://github.com/airshipit/treasuremap/releases>`__.

The releases are verified by `Seaworthy
<https://airship-treasuremap.readthedocs.io/en/latest/seaworthy.html>`__,
`Airsloop
<https://airship-treasuremap.readthedocs.io/en/latest/airsloop.html>`__,
and `Airship-in-a-Bottle
<https://github.com/airshipit/treasuremap/blob/master/tools/deployment/aiab/README.rst>`__
pipelines before delivery and are recommended for deployments instead of using
the master branch directly.


Component Overview
------------------

.. image:: diagrams/component_list.png


Node Overview
-------------

This document refers to several types of nodes, which vary in their
purpose, and to some degree in their orchestration / setup:

-  **Build node**: This refers to the environment where configuration
   documents are built for your environment (e.g., your laptop)
-  **Genesis node**: The "genesis" or "seed node" refers to a node used
   to get a new deployment off the ground, and is the first node built
   in a new deployment environment
-  **Control / Master nodes**: The nodes that make up the control
   plane. (Note that the genesis node will be one of the controller
   nodes)
-  **Compute / Worker Nodes**: The nodes that make up the data
   plane

Hardware Preparation
--------------------

The Seaworthy site reference shows a production-worthy deployment that includes
multiple disks, as well as redundant/bonded network configuration.

Airship hardware requirements are flexible, and the system can be deployed
with very minimal requirements if needed (e.g., single disk, single network).

For simplified non-bonded, and single disk examples, see
`Airsloop <https://airship-treasuremap.readthedocs.io/en/latest/airsloop.html>`__.

BIOS and IPMI
~~~~~~~~~~~~~

1. Virtualization enabled in BIOS
2. IPMI enabled in server BIOS (e.g., IPMI over LAN option enabled)
3. IPMI IPs assigned, and routed to the environment you will deploy into
   Note: Firmware bugs related to IPMI are common. Ensure you are running the
   latest firmware version for your hardware. Otherwise, it is recommended to
   perform an iLo/iDrac reset, as IPMI bugs with long-running firmware are not
   uncommon.
4. Set PXE as first boot device and ensure the correct NIC is selected for PXE.

Disk
~~~~

1. For servers that are in the control plane (including genesis):

   - Two-disk RAID-1: Operating System
   - Two disks JBOD: Ceph Journal/Meta for control plane
   - Remaining disks JBOD: Ceph OSD for control plane

2. For servers that are in the tenant data plane (compute nodes):

   - Two-disk RAID-1: Operating System
   - Two disks JBOD: Ceph Journal/Meta for tenant-ceph
   - Two disks JBOD: Ceph OSD for tenant-ceph
   - Remaining disks configured according to the host profile target
     for each given server (e.g., RAID-10 for OpenStack ephemeral).

Network
~~~~~~~

1. You have a dedicated PXE interface on untagged/native VLAN,
   1x1G interface (eno1)
2. You have VLAN segmented networks,
   2x10G bonded interfaces (enp67s0f0 and enp68s0f1)

    - Management network (routed/OAM)
    - Calico network (Kubernetes control channel)
    - Storage network
    - Overlay network
    - Public network

See detailed network configuration in the
``site/${NEW_SITE}/networks/physical/networks.yaml`` configuration file.

Hardware sizing and minimum requirements
----------------------------------------

+-----------------+----------+----------+----------+
|  Node           |   Disk   |  Memory  |   CPU    |
+=================+==========+==========+==========+
| Build (laptop)  |   10 GB  |  4 GB    |   1      |
+-----------------+----------+----------+----------+
| Genesis/Control |   500 GB |  64 GB   |   24     |
+-----------------+----------+----------+----------+
| Compute         |   N/A*   |  N/A*    |   N/A*   |
+-----------------+----------+----------+----------+

* Workload driven (determined by host profile)

See detailed hardware configuration in the
``site/${NEW_SITE}/networks/profiles`` folder.

Establishing build node environment
-----------------------------------

1. On the machine you wish to use to generate deployment files, install required
   tooling

.. code-block:: bash

    sudo apt -y install docker.io git

2. Clone the ``treasuremap`` git repo as follows

.. code-block:: bash

    git clone https://opendev.org/airship/treasuremap.git
    cd treasuremap && git checkout <release-tag>

Building site documents
-----------------------

This section goes over how to put together site documents according to
your specific environment and generate the initial Promenade bundle
needed to start the site deployment.

Preparing deployment documents
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In its current form, Pegleg provides an organized structure for YAML
elements that separates common site elements (i.e., ``global``
folder) from unique site elements (i.e., ``site`` folder).

To gain a full understanding of the Pegleg structure, it is highly
recommended to read the Pegleg documentation on this topic
`here <https://airship-pegleg.readthedocs.io/>`__.

The ``seaworthy`` site may be used as reference site. It is the
principal pipeline for integration and continuous deployment testing of Airship.

Change directory to the ``site`` folder and copy the
``seaworthy`` site as follows:

.. code-block:: bash

    NEW_SITE=mySite # replace with the name of your site
    cd treasuremap/site
    cp -r seaworthy $NEW_SITE

Remove ``seaworthy`` specific certificates.

.. code-block:: bash

    rm -f site/${NEW_SITE}/secrets/certificates/certificates.yaml


You will then need to manually make changes to these files. These site
manifests are heavily commented to explain parameters, and more importantly
identify all of the parameters that need to change when authoring a new
site.

These areas which must be updated for a new site are flagged with the
label ``NEWSITE-CHANGEME`` in YAML comments. Search for all instances
of ``NEWSITE-CHANGEME`` in your new site definition. Then follow the
instructions that accompany the tag in order to make all needed changes
to author your new Airship site.

Because some files depend on (or will repeat) information from others,
the order in which you should build your site files is as follows:

1. site/$NEW\_SITE/networks/physical/networks.yaml
2. site/$NEW\_SITE/baremetal/nodes.yaml
3. site/$NEW\_SITE/networks/common-addresses.yaml
4. site/$NEW\_SITE/pki/pki-catalog.yaml
5. All other site files

Register DNS names
~~~~~~~~~~~~~~~~~~

Airship has two virtual IPs.

See ``data.vip`` in section of
``site/${NEW_SITE}/networks/common-addresses.yaml`` configuration file.
Both are implemented via Kubernetes ingress controller and require FQDNs/DNS.

Register the following list of DNS names:

::

    +---+---------------------------+-------------+
    | A |             iam-sw.DOMAIN | ingress-vip |
    | A |        shipyard-sw.DOMAIN | ingress-vip |
    +---+---------------------------+-------------+
    | A |  cloudformation-sw.DOMAIN | ingress-vip |
    | A |         compute-sw.DOMAIN | ingress-vip |
    | A |       dashboard-sw.DOMAIN | ingress-vip |
    | A |         grafana-sw.DOMAIN | ingress-vip |
    +---+---------------------------+-------------+
    | A |        identity-sw.DOMAIN | ingress-vip |
    | A |           image-sw.DOMAIN | ingress-vip |
    | A |          kibana-sw.DOMAIN | ingress-vip |
    | A |          nagios-sw.DOMAIN | ingress-vip |
    | A |         network-sw.DOMAIN | ingress-vip |
    | A | nova-novncproxy-sw.DOMAIN | ingress-vip |
    | A |    object-store-sw.DOMAIN | ingress-vip |
    | A |   orchestration-sw.DOMAIN | ingress-vip |
    | A |       placement-sw.DOMAIN | ingress-vip |
    | A |          volume-sw.DOMAIN | ingress-vip |
    +---+---------------------------+-------------+
    | A |            maas-sw.DOMAIN | maas-vip    |
    | A |         drydock-sw.DOMAIN | maas-vip    |
    +---+---------------------------+-------------+

Here ``DOMAIN`` is a name of ingress domain, you can find it in the
``data.dns.ingress_domain`` section of
``site/${NEW_SITE}/secrets/certificates/ingress.yaml`` configuration file.

Run the following command to get an up-to-date list of required DNS names:

.. code-block:: bash

    grep -E 'host: .+DOMAIN' site/${NEW_SITE}/software/config/endpoints.yaml | \
        sort -u | awk '{print $2}'

Update Secrets
~~~~~~~~~~~~~~

Replace public SSH key under
``site/${NEW_SITE}/secrets/publickey/airship_ssh_public_key.yaml``
with a lab specific SSH public key. This key is used for MAAS initial
deployment as well as the default user for Divingbell
``site/${NEW_SITE}/software/charts/ucp/divingbell/divingbell.yaml``.

Add additional keys and Divingbell substitutions for any other users
that require SSH access to the deployed servers. See more details at
`<https://airship-divingbell.readthedocs.io/en/latest/>`__.

Replace passphrases under ``site/${NEW_SITE}/secrets/passphrases/``
with random generated ones:

- Passphrases generation ``openssl rand -hex 10``
- UUID generation ``uuidgen`` (e.g., for Ceph filesystem ID)
- Update ``secrets/passphrases/ipmi_admin_password.yaml`` with IPMI password
- Update ``secrets/passphrases/ubuntu_crypt_password.yaml`` with password hash:

.. code-block:: python

    python3 -c "from crypt import *; print(crypt('<YOUR_PASSWORD>', METHOD_SHA512))"

Configure certificates in ``site/${NEW_SITE}/secrets/certificates/ingress.yaml``,
they need to be issued for the domains configured in the ``Register DNS names`` section.

.. caution::

    It is required to configure valid certificates. Self-signed certificates
    are not supported.

Control Plane & Tenant Ceph Cluster Notes
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Configuration variables for ceph control plane are located in:

- ``site/${NEW_SITE}/software/charts/ucp/ceph/ceph-osd.yaml``
- ``site/${NEW_SITE}/software/charts/ucp/ceph/ceph-client.yaml``

Configuration variables for tenant ceph are located in:

- ``site/${NEW_SITE}/software/charts/osh/openstack-tenant-ceph/ceph-osd.yaml``
- ``site/${NEW_SITE}/software/charts/osh/openstack-tenant-ceph/ceph-client.yaml``

Configuration summary:

-  data/values/conf/storage/osd[\*]/data/location: The block device that
   will be formatted by the Ceph chart and used as a Ceph OSD disk
-  data/values/conf/storage/osd[\*]/journal/location: The block device
   backing the ceph journal used by this OSD. Refer to the journal
   paradigm below.
-  data/values/conf/pool/target/osd: Number of OSD disks on each node

Assumptions:

1. Ceph OSD disks are not configured for any type of RAID. Instead, they
   are configured as JBOD when connected through a RAID controller.
   If the RAID controller does not support JBOD, put each disk in its
   own RAID-0 and enable RAID cache and write-back cache if the
   RAID controller supports it.
2. Ceph disk mapping, disk layout, journal and OSD setup is the same
   across Ceph nodes, with only their role differing. Out of the 4
   control plane nodes, we expect to have 3 actively participating in
   the Ceph quorum, and the remaining 1 node designated as a standby
   Ceph node which uses a different control plane profile
   (cp\_*-secondary) than the other three (cp\_*-primary).
3. If performing a fresh install, disks are unlabeled or not labeled from a
   previous Ceph install, so that Ceph chart will not fail disk
   initialization.

.. important::

    It is highly recommended to use SSD devices for Ceph Journal partitions.

If you have an operating system available on the target hardware, you
can determine HDD and SSD devices with:


.. code-block:: bash

    lsblk -d -o name,rota

where a ``rota`` (rotational) value of ``1`` indicates a spinning HDD,
and where a value of ``0`` indicates non-spinning disk (i.e., SSD). (Note:
Some SSDs still report a value of ``1``, so it is best to go by your
server specifications).

For OSDs, pass in the whole block device (e.g., ``/dev/sdd``), and the
Ceph chart will take care of disk partitioning, formatting, mounting,
etc.

For Ceph Journals, you can pass in a specific partition (e.g., ``/dev/sdb1``).
Note that it's not required to pre-create these partitions. The Ceph chart
will create journal partitions automatically if they don't exist.
By default the size of every journal partition is 10G. Make sure
there is enough space available to allocate all journal partitions.

Consider the following example where:

-  /dev/sda is an operating system RAID-1 device (SSDs for OS root)
-  /dev/sd[bc] are SSDs for ceph journals
-  /dev/sd[efgh] are HDDs for OSDs

The data section of this file would look like:

.. code-block:: yaml

    data:
      values:
        conf:
          storage:
            osd:
              - data:
                  type: block-logical
                  location: /dev/sde
                journal:
                  type: block-logical
                  location: /dev/sdb1
              - data:
                  type: block-logical
                  location: /dev/sdf
                journal:
                  type: block-logical
                  location: /dev/sdb2
              - data:
                  type: block-logical
                  location: /dev/sdg
                journal:
                  type: block-logical
                  location: /dev/sdc1
              - data:
                  type: block-logical
                  location: /dev/sdh
                journal:
                  type: block-logical
                  location: /dev/sdc2

Manifest linting and combining layers
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

After constituent YAML configurations are finalized, use Pegleg to lint
your manifests. Resolve any issues that result from linting before
proceeding:

.. code-block:: bash

    sudo tools/airship pegleg site -r /target lint $NEW_SITE

Note: ``P001`` and ``P005`` linting errors are expected for missing
certificates, as they are not generated until the next section. You may
suppress these warnings by appending ``-x P001 -x P005`` to the lint
command.

Next, use Pegleg to perform the merge that will yield the combined
global + site type + site YAML:

.. code-block:: bash

    sudo tools/airship pegleg site -r /target collect $NEW_SITE

Perform a visual inspection of the output. If any errors are discovered,
you may fix your manifests and re-run the ``lint`` and ``collect``
commands.

Once you have error-free output, save the resulting YAML as follows:

.. code-block:: bash

    sudo tools/airship pegleg site -r /target collect $NEW_SITE \
        -s ${NEW_SITE}_collected

This output is required for subsequent steps.

Lastly, you should also perform a ``render`` on the documents. The
resulting render from Pegleg will not be used as input in subsequent
steps, but is useful for understanding what the document will look like
once Deckhand has performed all substitutions, replacements, etc. This
is also useful for troubleshooting and addressing any Deckhand errors
prior to submitting via Shipyard:

.. code-block:: bash

    sudo tools/airship pegleg site -r /target render $NEW_SITE

Inspect the rendered document for any errors. If there are errors,
address them in your manifests and re-run this section of the document.

Building the Promenade bundle
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Create an output directory for Promenade certs and run

.. code-block:: bash

    mkdir ${NEW_SITE}_certs
    sudo tools/airship promenade generate-certs \
      -o /target/${NEW_SITE}_certs /target/${NEW_SITE}_collected/*.yaml

Estimated runtime: About **1 minute**

After the certificates has been successfully created, copy the generated
certificates into the security folder. Example:

.. code-block:: bash

    mkdir -p site/${NEW_SITE}/secrets/certificates
    sudo cp ${NEW_SITE}_certs/certificates.yaml \
      site/${NEW_SITE}/secrets/certificates/certificates.yaml

Regenerate collected YAML files to include copied certificates:

.. code-block:: bash

    sudo rm -rf ${NEW_SITE}_collected ${NEW_SITE}_certs
    sudo tools/airship pegleg site -r /target collect $NEW_SITE \
        -s ${NEW_SITE}_collected

Finally, create the Promenade bundle:

.. code-block:: bash

   mkdir ${NEW_SITE}_bundle
   sudo tools/airship promenade build-all --validators \
     -o /target/${NEW_SITE}_bundle /target/${NEW_SITE}_collected/*.yaml


Genesis node
------------

Initial setup
~~~~~~~~~~~~~

Before starting, ensure that the BIOS and IPMI settings match those
stated previously in this document. Also ensure that the hardware RAID
is setup for this node per the control plane disk configuration stated
previously in this document.

Then, start with a manual install of Ubuntu 16.04 on the genesis node, the node
you will use to seed the rest of your environment. Use standard `Ubuntu
ISO <http://releases.ubuntu.com/16.04>`__.
Ensure to select the following:

-  UTC timezone
-  Hostname that matches the genesis hostname given in
   ``data.genesis.hostname`` in
   ``site/${NEW_SITE}/networks/common-addresses.yaml``.
-  At the ``Partition Disks`` screen, select ``Manual`` so that you can
   setup the same disk partitioning scheme used on the other control
   plane nodes that will be deployed by MaaS. Select the first logical
   device that corresponds to one of the RAID-1 arrays already setup in
   the hardware controller. On this device, setup partitions matching
   those defined for the ``bootdisk`` in your control plane host profile
   found in ``site/${NEW_SITE}/profiles/host``.
   (e.g., 30G for /, 1G for /boot, 100G for /var/log, and all remaining
   storage for /var). Note that the volume size syntax looking like
   ``>300g`` in Drydock means that all remaining disk space is allocated
   to this volume, and that volume needs to be at least 300G in
   size.
-  When you get to the prompt, "How do you want to manage upgrades on
   this system?", choose "No automatic updates" so that packages are
   only updated at the time of our choosing (e.g., maintenance windows).
-  Ensure the grub bootloader is also installed to the same logical
   device as in the previous step (this should be default behavior).

After installation, ensure the host has outbound internet access and can
resolve public DNS entries (e.g., ``nslookup google.com``,
``curl https://www.google.com``).

Ensure that the deployed genesis hostname matches the hostname in
``data.genesis.hostname`` in
``site/${NEW_SITE}/networks/common-addresses.yaml``.
If it does not match, then either change the hostname of the node to
match the configuration documents, or re-generate the configuration with
the correct hostname.

To change the hostname of the deployed node, you may run the following:

.. code-block:: bash

    sudo hostname $NEW_HOSTNAME
    sudo sh -c "echo $NEW_HOSTNAME > /etc/hostname"
    sudo vi /etc/hosts # Anywhere the old hostname appears in the file, replace
                       # with the new hostname

Or, as an alternative, update the genesis hostname
in the site definition and then repeat the steps in the previous two sections,
"Manifest linting and combining layers" and "Building the Promenade bundle".

Installing matching kernel version
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Install the same kernel version on the genesis host that MaaS will use
to deploy new baremetal nodes.

To do this, first you must determine the kernel version that
will be deployed to those nodes. Start by looking at the host profile
definition used to deploy other control plane nodes by searching for
``control-plane: enabled``. Most likely this will be a file under
``global/profiles/host``. In this file, find the kernel info. Example:

.. code-block:: bash

  platform:
    image: 'xenial'
    kernel: 'hwe-16.04'
    kernel_params:
      kernel_package: 'linux-image-4.15.0-46-generic'

It is recommended to install matching (and previously tested) kernel

.. code-block:: bash

    sudo apt-get install linux-image-4.15.0-46-generic

Check the installed packages on the genesis host with ``dpkg --list``.
If there are any later kernel versions installed, remove them with
``sudo apt remove``, so that the newly installed kernel is the latest
available. Boot the genesis node using the installed kernel.

Install ntpdate/ntp
~~~~~~~~~~~~~~~~~~~

Install and run ntpdate, to ensure a reasonably sane time on genesis
host before proceeding:

.. code-block:: bash

    sudo apt -y install ntpdate
    sudo ntpdate ntp.ubuntu.com

If your network policy does not allow time sync with external time
sources, specify a local NTP server instead of using ``ntp.ubuntu.com``.

Then, install the NTP client:

.. code-block:: bash

    sudo apt -y install ntp

Add the list of NTP servers specified in ``data.ntp.servers_joined`` in
file
``site/${NEW_SITE}/networks/common-addresses.yaml``
to ``/etc/ntp.conf`` as follows:

::

    pool NTP_SERVER1 iburst
    pool NTP_SERVER2 iburst
    (repeat for each NTP server with correct NTP IP or FQDN)

Then, restart the NTP service:

.. code-block:: bash

    sudo service ntp restart

If you cannot get good time to your selected time servers,
consider using alternate time sources for your deployment.

Disable the apparmor profile for ntpd:

.. code-block:: bash

    sudo ln -s /etc/apparmor.d/usr.sbin.ntpd /etc/apparmor.d/disable/
    sudo apparmor_parser -R /etc/apparmor.d/usr.sbin.ntpd

This prevents an issue with the MaaS containers, which otherwise get
permission denied errors from apparmor when the MaaS container tries to
leverage libc6 for /bin/sh when MaaS container ntpd is forcefully
disabled.

Promenade bootstrap
~~~~~~~~~~~~~~~~~~~

Copy the ``${NEW_SITE}_bundle`` directory from the build node to the genesis
node, into the home directory of the user there (e.g., ``/home/ubuntu``).
Then, run the following script as sudo on the genesis node:

.. code-block:: bash

    cd ${NEW_SITE}_bundle
    sudo ./genesis.sh

Estimated runtime: **1h**

Following completion, run the ``validate-genesis.sh`` script to ensure
correct provisioning of the genesis node:

.. code-block:: bash

    cd ${NEW_SITE}_bundle
    sudo ./validate-genesis.sh

Estimated runtime: **2m**

Deploy Site with Shipyard
-------------------------

Export valid login credentials for one of the Airship Keystone users defined
for the site. Currently there are no authorization checks in place, so
the credentials for any of the site-defined users will work. For
example, we can use the ``shipyard`` user, with the password that was
defined in
``site/${NEW_SITE}/secrets/passphrases/ucp_shipyard_keystone_password.yaml``.
Example:

.. code-block:: bash

    export OS_AUTH_URL="https://iam-sw.DOMAIN:443/v3"

    export OS_USERNAME=shipyard
    export OS_PASSWORD=password123

Next, load collected site manifests to Shipyard

.. code-block:: bash

    sudo -E tools/airship shipyard create configdocs ${NEW_SITE} \
      --directory=/target/${NEW_SITE}_collected

    sudo tools/airship shipyard commit configdocs

Estimated runtime: **3m**

Now deploy the site with shipyard:

.. code-block:: bash

    tools/airship shipyard create action deploy_site

Estimated runtime: **3h**

Check periodically for successful deployment:

.. code-block:: bash

    tools/airship shipyard get actions
    tools/airship shipyard describe action/<ACTION>

Disable password-based login on genesis
---------------------------------------

Before proceeding, verify that your SSH access to the genesis node is
working with your SSH key (i.e., not using password-based
authentication).

Then, disable password-based SSH authentication on genesis in
``/etc/ssh/sshd_config`` by uncommenting the ``PasswordAuthentication``
and setting its value to ``no``. Example:

::

    PasswordAuthentication no

Then, restart the ssh service:

::

    sudo systemctl restart ssh


