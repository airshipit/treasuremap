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
authoring guidance lives within ``airship-seaworthy`` reference site in the
form of YAML comments.

Terminology
-----------

**Cloud**: A platform that provides a standard set of interfaces for
`IaaS <https://en.wikipedia.org/wiki/Infrastructure_as_a_service>`__
consumers.

**OSH**: (`OpenStack
Helm <https://docs.openstack.org/openstack-helm/latest/>`__) is a
collection of Helm charts used to deploy OpenStack on kubernetes.

**Undercloud/Overcloud**: Terms used to distinguish which cloud is
deployed on top of the other. In Airship sites, OpenStack (overcloud)
is deployed on top of Kubernetes (underlcoud).

**Airship**: A specific implementation of OpenStack Helm charts onto
kubernetes, the deployment of which is the primary focus of this document.

**Control Plane**: From the point of view of the cloud service provider,
the control plane refers to the set of resources (hardware, network,
storage, etc) sourced to run cloud services.

**Data Plane**: From the point of view of the cloud service provider,
the data plane is the set of resources (hardware, network, storage,
etc.) sourced to run consumer workloads. When used in this document,
"data plane" refers to the data plane of the overcloud (OSH).

**Host Profile**: A host profile is a standard way of configuring a bare
metal host. Encompasses items such as the number of bonds, bond slaves,
physical storage mapping and partitioning, and kernel parameters.

Component Overview
~~~~~~~~~~~~~~~~~~

.. image:: diagrams/component_list.png

Node Overview
~~~~~~~~~~~~~

This document refers to several types of nodes, which vary in their
purpose, and to some degree in their orchestration / setup:

-  **Build node**: This refers to the environment where configuration
   documents are built for your environment (e.g., your laptop)
-  **Genesis node**: The "genesis" or "seed node" refers to a node used
   to get a new deployment off the ground, and is the first node built
   in a new deployment environment.
-  **Control / Controller nodes**: The nodes that make up the control
   plane. (Note that the Genesis node will be one of the controller
   nodes.)
-  **Compute nodes / Worker Nodes**: The nodes that make up the data
   plane

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
    -  `Airship Berth <https://storyboard.openstack.org/#!/project/1003>`__
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
    -  `Airship in a
       Bottle <https://storyboard.openstack.org/#!/project/1006>`__

    -  `Airship Treasuremap
       <https://storyboard.openstack.org/#!/project/openstack/airship-treasuremap>`__

Hardware Prep
-------------

Disk
~~~~

1. Control plane server disks:

   - Two-disk RAID-1 mirror for operating system
   - Two-disk RAID-1 mirror for ceph journals - preferentially SSDs
   - Remaining disks as JBOD for Ceph

2. Data plane server disks:

   - Two-disk RAID-1 mirror for operating system
   - Remaining disks need to be configured according to the host profile target
     for each given server (e.g., RAID-10).

BIOS and IPMI
~~~~~~~~~~~~~

1. Virtualization enabled in BIOS
2. IPMI enabled in server BIOS (e.g., IPMI over LAN option enabled)
3. IPMI IPs assigned, and routed to the environment you will deploy into
   Note: Firmware bugs related to IPMI are common. Ensure you are running the
   latest firmware version for your hardware. Otherwise, it is recommended to
   perform an iLo/iDrac reset, as IPMI bugs with long-running firmware are not
   uncommon.
4. Set PXE as first boot device and ensure the correct NIC is selected for PXE

Network
~~~~~~~

1. You have a network you can successfully PXE boot with your network topology
   and bonding settings (dedicated PXE interace on untagged/native VLAN in this
   example)
2. You have (VLAN) segmented, routed networks accessible by all nodes for:

   1. Management network(s) (k8s control channel)
   2. Calico network(s)
   3. Storage network(s)
   4. Overlay network(s)
   5. Public network(s)

HW Sizing and minimum requirements
----------------------------------

+----------+----------+----------+----------+
|  Node    |   disk   |  memory  |   cpu    |
+==========+==========+==========+==========+
|  Build   |   10 GB  |  4 GB    |   1      |
+----------+----------+----------+----------+
| Genesis  |   100 GB |  16 GB   |   8      |
+----------+----------+----------+----------+
| Control  |   10 TB  |  128 GB  |   24     |
+----------+----------+----------+----------+
| Compute  |   N/A*   |  N/A*    |   N/A*   |
+----------+----------+----------+----------+

* Workload driven (determined by host profile)


Establishing build node environment
-----------------------------------

1. On the machine you wish to use to generate deployment files, install required
   tooling::

    sudo apt -y install docker.io git

2. Clone and link the required git repos as follows::

    git clone https://git.openstack.org/openstack/airship-pegleg
    git clone https://git.openstack.org/openstack/airship-treasuremap


Building Site documents
-----------------------

This section goes over how to put together site documents according to
your specific environment, and generate the initial Promenade bundle
needed to start the site deployment.

Preparing deployment documents
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In its current form, pegleg provides an organized structure for YAML
elements, in order to separate common site elements (i.e., ``global``
folder) from unique site elements (i.e., ``site`` folder).

To gain a full understanding of the pegleg structure, it is highly
recommended to read pegleg documentation on this
`here <https://airship-pegleg.readthedocs.io/>`__.

The ``airship-seaworthy`` site may be used as reference site. It is the
principal pipeline for integration and continuous deployment testing of Airship.

Change directory to the ``airship-treasuremap/site`` folder and copy the
``airship-seaworthy`` site as follows:

::

    NEW_SITE=mySite # replace with the name of your site
    cd airship-treasuremap/site
    cp -r airship-seaworthy $NEW_SITE

Remove ``airship-seaworthy`` specific certificates.

::

    rm -rf airship-treasuremap/site/airship-seaworthy/secrets/certificates/certificates.yaml


You will then need to manually make changes to these files. These site
manifests are heavily commented to explain parameters, and importantly
identify all of the parameters that need to change when authoring a new
site.

These areas which must be updated for a new site are flagged with the
label ``NEWSITE-CHANGEME`` in YAML commentary. Search for all instances
of ``NEWSITE-CHANGEME`` in your new site definition, and follow the
instructions that accompany the tag in order to make all needed changes
to author your new Airship site.

Because some files depend on (or will repeat) information from others,
the order in which you should build your site files is as follows:

1. site/$NEW\_SITE/networks/physical/networks.yaml
2. site/$NEW\_SITE/baremetal/nodes.yaml
3. site/$NEW\_SITE/networks/common-addresses.yaml
4. site/$NEW\_SITE/pki/pki-catalog.yaml
5. All other site files

Control Plane Ceph Cluster Notes
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Environment Ceph parameters for the control plane are located in:

``site/$NEW_SITE/software/charts/ucp/ceph/ceph.yaml``

Setting highlights:

-  data/values/conf/storage/osd[\*]/data/location: The block device that
   will be formatted by the Ceph chart and used as a Ceph OSD disk
-  data/values/conf/storage/osd[\*]/journal/location: The directory
   backing the ceph journal used by this OSD. Refer to the journal
   paradigm below.
-  data/values/conf/pool/target/osd: Number of OSD disks on each node

Assumptions:

1. Ceph OSD disks are not configured for any type of RAID (i.e., they
   are configured as JBOD if connected through a RAID controller). (If
   RAID controller does not support JBOD, put each disk in its own
   RAID-0 and enable RAID cache and write-back cache if the RAID
   controller supports it.)
2. Ceph disk mapping, disk layout, journal and OSD setup is the same
   across Ceph nodes, with only their role differing. Out of the 4
   control plane nodes, we expect to have 3 actively participating in
   the Ceph quorom, and the remaining 1 node designated as a standby
   Ceph node which uses a different control plane profile
   (cp\_*-secondary) than the other three (cp\_*-primary).
3. If doing a fresh install, disk are unlabeled or not labeled from a
   previous Ceph install, so that Ceph chart will not fail disk
   initialization

This document covers two Ceph journal deployment paradigms:

1. Servers with SSD/HDD mix (disregarding operating system disks).
2. Servers with no SSDs (disregarding operating system disks). In other
   words, exclusively spinning disk HDDs available for Ceph.

If you have an operating system available on the target hardware, you
can determine HDD and SSD layout with:

::

    lsblk -d -o name,rota

where a ``rota`` (rotational) value of ``1`` indicates a spinning HDD,
and where a value of ``0`` indicates non-spinning disk (i.e. SSD). (Note
- Some SSDs still report a value of ``1``, so it is best to go by your
server specifications).

In case #1, the SSDs will be used for journals and the HDDs for OSDs.

For OSDs, pass in the whole block device (e.g., ``/dev/sdd``), and the
Ceph chart will take care of disk partitioning, formatting, mounting,
etc.

For journals, divide the number of journal disks as evenly as possible
between the OSD disks. We will also use the whole block device, however
we cannot pass that block device to the Ceph chart like we can for the
OSD disks.

Instead, the journal devices must be already partitioned, formatted, and
mounted prior to Ceph chart execution. This should be done by MaaS as
part of the Drydock host-profile being used for control plane nodes.

Consider the follow example where:

-  /dev/sda is an operating system RAID-1 device (SSDs for OS root)
-  /dev/sdb is an operating system RAID-1 device (SSDs for ceph journal)
-  /dev/sd[cdef] are HDDs

Then, the data section of this file would look like:

::

    data:
      values:
        conf:
          storage:
            osd:
              - data:
                  type: block-logical
                  location: /dev/sdd
                journal:
                  type: directory
                  location: /var/lib/openstack-helm/ceph/journal/journal-sdd
              - data:
                  type: block-logical
                  location: /dev/sde
                journal:
                  type: directory
                  location: /var/lib/openstack-helm/ceph/journal/journal-sde
              - data:
                  type: block-logical
                  location: /dev/sdf
                journal:
                  type: directory
                  location: /var/lib/openstack-helm/ceph/journal/journal-sdf
              - data:
                  type: block-logical
                  location: /dev/sdg
                journal:
                  type: directory
                  location: /var/lib/openstack-helm/ceph/journal/journal-sdg
          pool:
            target:
              osd: 4

where the following mount is setup by MaaS via Drydock host profile for
the control-plane nodes:

::

    /dev/sdb is mounted to /var/lib/openstack-helm/ceph/journal

In case #2, Ceph best practice is to allocate journal space on all OSD
disks. The Ceph chart assumes this partitioning has been done
beforehand. Ensure that your control plane host profile is partitioning
each disk between the Ceph OSD and Ceph journal, and that it is mounting
the journal partitions. (Drydock will drive these disk layouts via MaaS
provisioning). Note the mountpoints for the journals and the partition
mappings. Consider the following example where:

-  /dev/sda is the operating system RAID-1 device
-  /dev/sd[bcde] are HDDs

Then, the data section of this file will look similar to the following:

::

    data:
      values:
        conf:
          storage:
            osd:
              - data:
                  type: block-logical
                  location: /dev/sdb2
                journal:
                  type: directory
                  location: /var/lib/openstack-helm/ceph/journal0/journal-sdb
              - data:
                  type: block-logical
                  location: /dev/sdc2
                journal:
                  type: directory
                  location: /var/lib/openstack-helm/ceph/journal1/journal-sdc
              - data:
                  type: block-logical
                  location: /dev/sdd2
                journal:
                  type: directory
                  location: /var/lib/openstack-helm/ceph/journal2/journal-sdd
              - data:
                  type: block-logical
                  location: /dev/sde2
                journal:
                  type: directory
                  location: /var/lib/openstack-helm/ceph/journal3/journal-sde
          pool:
            target:
              osd: 4

where the following mounts are setup by MaaS via Drydock host profile
for the control-plane nodes:

::

    /dev/sdb1 is mounted to /var/lib/openstack-helm/ceph/journal0
    /dev/sdc1 is mounted to /var/lib/openstack-helm/ceph/journal1
    /dev/sdd1 is mounted to /var/lib/openstack-helm/ceph/journal2
    /dev/sde1 is mounted to /var/lib/openstack-helm/ceph/journal3

Update Passphrases
~~~~~~~~~~~~~~~~~~~~

Replace passphrases under ``site/airship-seaworthy/secrets/passphrases/``
with random generated ones (e.g. ``openssl rand -hex 10``).

Manifest linting and combining layers
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

After constituent YAML configurations are finalized, use Pegleg to lint
your manifests, and resolve any issues that result from linting before
proceeding:

::

    sudo airship-pegleg/tools/pegleg.sh repo \
      -r airship-treasuremap \
      lint

Note: ``P001`` and ``P003`` linting errors are expected for missing
certificates, as they are not generated until the next section. You may
suppress these warnings by appending ``-x P001 -x P003`` to the lint
command.

Next, use pegleg to perform the merge that will yield the combined
global + site type + site YAML:

::

    sudo sh airship-pegleg/tools/pegleg.sh site \
      -r airship-treasuremap \
      collect $NEW_SITE

Perform a visual inspection of the output. If any errors are discovered,
you may fix your manifests and re-run the ``lint`` and ``collect``
commands.

After you have an error-free output, save the resulting YAML as follows:

::

    mkdir -p ~/${NEW_SITE}_collected
    sudo airship-pegleg/tools/pegleg.sh site \
      -r airship-treasuremap \
      collect $NEW_SITE -s ${NEW_SITE}_collected

It is this output which will be used in subsequent steps.

Lastly, you should also perform a ``render`` on the documents. The
resulting render from Pegleg will not be used as input in subsequent
steps, but is useful for understanding what the document will look like
once Deckhand has performed all substitutions, replacements, etc. This
is also useful for troubleshooting, and addressing any Deckhand errors
prior to submitting via Shipyard:

::

    sudo airship-pegleg/tools/pegleg.sh site \
      -r airship-treasuremap \
      render $NEW_SITE

Inspect the rendered document for any errors. If there are errors,
address them in your manifests and re-run this section of the document.

Building the Promenade bundle
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Clone the Promenade repo, if not already cloned:

::

    git clone https://github.com/openstack/airship-promenade

Refer to the ``data/charts/ucp/promenade/reference`` field in
``airship-treasuremap/global/v4.0/software/config/versions.yaml``. If
this is a pinned reference (i.e., any reference that's not ``master``),
then you should checkout the same version of the Promenade repository.
For example, if the Promenade reference was ``86c3c11...`` in the
versions file, checkout the same version of the Promenade repo which was
cloned previously:

::

    (cd airship-promenade && git checkout 86c3c11)

Likewise, before running the ``simple-deployment.sh`` script, you should
refer to the ``data/images/ucp/promenade/promenade`` field in
``~/airship-treasuremap/global/v4.0/software/config/versions.yaml``. If
there is a pinned reference (i.e., any image reference that's not
``latest``), then this reference should be used to set the
``IMAGE_PROMENADE`` environment variable. For example, if the Promenade
image was pinned to ``quay.io/airshipit/promenade:d30397f...`` in
the versions file, then export the previously mentioned environment
variable like so:

::

    export IMAGE_PROMENADE=quay.io/airshipit/promenade:d30397f...

Now, create an output directory for Promenade bundles and run the
``simple-deployment.sh`` script:

::

    mkdir ${NEW_SITE}_bundle
    sudo airship-promenade/tools/simple-deployment.sh ${NEW_SITE}_collected ${NEW_SITE}_bundle

Estimated runtime: About **1 minute**

After the bundle has been successfully created, copy the generated
certificates into the security folder. Ex:

::

    mkdir -p airship-treasuremap/site/${NEW_SITE}/secrets/certificates
    sudo cp ${NEW_SITE}_bundle/certificates.yaml \
      airship-treasuremap/site/${NEW_SITE}/secrets/certificates/certificates.yaml

Genesis node
------------

Initial setup
~~~~~~~~~~~~~

Before starting, ensure that the BIOS and IPMI settings match those
stated previously in this document. Also ensure that the hardware RAID
is setup for this node per the control plane disk configuration stated
previously in this document.

Then, start with a manual install of Ubuntu 16.04 on the node you wish
to use to seed the rest of your environment standard `Ubuntu
ISO <http://releases.ubuntu.com/16.04>`__.
Ensure to select the following:

-  UTC timezone
-  Hostname that matches the Genesis hostname given in
   ``/data/genesis/hostname`` in
   ``airship-treasuremap/site/$NEW_SITE/networks/common-addresses.yaml``.
-  At the ``Partition Disks`` screen, select ``Manual`` so that you can
   setup the same disk partitioning scheme used on the other control
   plane nodes that will be deployed by MaaS. Select the first logical
   device that corresponds to one of the RAID-1 arrays already setup in
   the hardware controller. On this device, setup partitions matching
   those defined for the ``bootdisk`` in your control plane host profile
   found in ``airship-treasuremap/site/$NEW_SITE/profiles/host``.
   (e.g., 30G for /, 1G for /boot, 100G for /var/log, and all remaining
   storage for /var). Note that the volume size syntax looking like
   ``>300g`` in Drydock means that all remaining disk space is allocated
   to this volume, and that volume needs to be at least 300G in
   size.
-  Ensure that OpenSSH and Docker (Docker is needed because of
   miniMirror) are included as installed packages
-  When you get to the prompt, "How do you want to manage upgrades on
   this system?", choose "No automatic updates" so that packages are
   only updated at the time of our choosing (e.g. maintenance windows).
-  Ensure the grub bootloader is also installed to the same logical
   device as in the previous step (this should be default behavior).

After installation, ensure the host has outbound internet access and can
resolve public DNS entries (e.g., ``nslookup google.com``,
``curl https://www.google.com``).

Ensure that the deployed Genesis hostname matches the hostname in
``data/genesis/hostname`` in
``airship-treasuremap/site/$NEW_SITE/networks/common-addresses.yaml``.
If it does not match, then either change the hostname of the node to
match the configuration documents, or re-generate the configuration with
the correct hostname. In order to change the hostname of the deployed
node, you may run the following:

::

    sudo hostname $NEW_HOSTNAME
    sudo sh -c "echo $NEW_HOSTNAME > /etc/hostname"
    sudo vi /etc/hosts # Anywhere the old hostname appears in the file, replace
                       # with the new hostname

Or to regenerate manifests, re-run the previous two sections with the
after updating the genesis hostname in the site definition.

Installing matching kernel version
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Install the same kernel version on the Genesis host that MaaS will use
to deploy new baremetal nodes.

In order to do this, first you must determine the kernel version that
will be deployed to those nodes. Start by looking at the host profile
definition used to deploy other control plane nodes by searching for
``control-plane: enabled``. Most likely this will be a file under
``global/v4.0/profiles/host``. In this file, find the kernel info -
e.g.:

::

    platform:
        image: 'xenial'
        kernel: 'hwe-16.04'

In this case, it is the hardware enablement kernel for 16.04. To find
the exact kernel version that will be deployed, we must look into the
simple-stream image cache that will be used by MaaS to deploy nodes
with. Locate the ``data/images/ucp/maas/maas_cache`` key in within
``airship-treasuremap/global/v4.0/software/config/versions.yaml``. This
is the image that you will need to fetch, using a node with docker
installed that has access and can reach the site/location hosting the
image. For example, from the **build node**, the command would take the
form:

::

    sudo docker pull YOUR_SSTREAM_IMAGE

Then, create a container from that image:

::

    cd ~
    sudo sh -c "$(docker images | grep sstream-cache | head -1 | awk '{print $1}' > image_name)"
    sudo docker create --name sstream $(cat image_name)

Then use the container ID returned from the last command as follows:

::

    sudo docker start sstream
    sudo docker exec -it sstream /bin/bash

In the container, ``cd`` to the following location (substituting for the
platform image and platform kernel identified in the host profile
previously, and choosing the folder corresponding to the most current
date if more than one are available) and run the ``file`` command on the
``boot-kernel`` file:

::

    cd /var/www/html/maas/images/ephemeral-v3/daily/PLATFORM_IMAGE/amd64/LATEST_DATE/PLATFORM_KERNEL/generic
    file boot-kernel

This will produce the complete kernel version. E.g.:

::

    Linux kernel x86 boot executable bzImage, version 4.13.0-43-generic (buildd@lcy01-amd64-029) #48~16.04.1-Ubuntu S, RO-rootFS, swap_dev 0x7, Normal VGA

In this example, the kernel version is ``4.13.0-43-generic``. Define any proxy
environment variables needed for your environment to reach public ubuntu
package repos, and install the matching kernel on the Genesis host (make sure
to run on Genesis host, not on the build host):

::

    sudo apt -y install 4.13.0-43-generic

Check the installed packages on the genesis host with ``dpkg --list``.
If there are any later kernel versions installed, remove them with
``sudo apt remove``, so that the newly install kernel is the latest
available.

Lastly if you wish to cleanup your build node, you may run the
following:

::

    exit # (to quit the container)
    cd ~
    sudo docker stop sstream
    sudo docker rm sstream
    sudo docker image rm $(cat image_name)
    sudo rm image_name

Install ntpdate/ntp
~~~~~~~~~~~~~~~~~~~

Install and run ntpdate, to ensure a reasonably sane time on genesis
host before proceeding:

::

    sudo apt -y install ntpdate
    sudo ntpdate ntp.ubuntu.com

If your network policy does not allow time sync with external time
sources, specify a local NTP server instead of using ``ntp.ubuntu.com``.

Then, install the NTP client:

::

    sudo apt -y install ntp

Add the list of NTP servers specified in ``data/ntp/servers_joined`` in
file
``airship-treasuremap/site/$NEW_SITE/networks/common-address.yaml``
to ``/etc/ntp.conf`` as follows:

::

    pool NTP_SERVER1 iburst
    pool NTP_SERVER2 iburst
    (repeat for each NTP server with correct NTP IP or FQDN)

Then, restart the NTP service:

::

    sudo service ntp restart

If you cannot get good time to your selected time servers,
consider using alternate time sources for your deployment.

Disable the apparmor profile for ntpd:

::

    sudo ln -s /etc/apparmor.d/usr.sbin.ntpd /etc/apparmor.d/disable/
    sudo apparmor_parser -R /etc/apparmor.d/usr.sbin.ntpd

This prevents an issue with the MaaS containers, which otherwise get
permission denied errors from apparmor when the MaaS container tries to
leverage libc6 for /bin/sh when MaaS container ntpd is forcefully
disabled.

Setup Ceph Journals
~~~~~~~~~~~~~~~~~~~

Until genesis node reprovisioning is implemented, it is necessary to
manually perform host-level disk partitioning and mounting on the
genesis node, for activites that would otherwise have been addressed by
a bare metal node provision via Drydock host profile data by MaaS.

Assuming your genesis HW matches the HW used in your control plane host
profile, you should manually apply to the genesis node the same Ceph
partitioning (OSDs & journals) and formatting + mounting (journals only)
as defined in the control plane host profile. See
``airship-treasuremap/global/v4.0/profiles/host/base_control_plane.yaml``.

For example, if we have a journal SSDs ``/dev/sdb`` on the genesis node,
then use the ``cfdisk`` tool to format it:

::

    sudo cfdisk /dev/sdb

Then:

1. Select ``gpt`` label for the disk
2. Select ``New`` to create a new partition
3. If scenario #1 applies in
   site/$NEW\_SITE/software/charts/ucp/ceph/ceph.yaml\_, then accept
   default partition size (entire disk). If scenario #2 applies, then
   only allocate as much space as defined in the journal disk partitions
   mounted in the control plane host profile.
4. Select ``Write`` option to commit changes, then ``Quit``
5. If scenario #2 applies, create a second partition that takes up all
   of the remaining disk space. This will be used as the OSD partition
   (``/dev/sdb2``).

Install package to format disks with XFS:

::

    sudo apt -y install xfsprogs

Then, construct an XFS filesystem on the journal partition with XFS:

::

    sudo mkfs.xfs /dev/sdb1

Create a directory as mount point for ``/dev/sdb1`` to match those
defined in the same host profile ceph journals:

::

    sudo mkdir -p /var/lib/ceph/cp

Use the ``blkid`` command to get the UUID for ``/dev/sdb1``, then
populate ``/etc/fstab`` accordingly. Ex:

::

    sudo sh -c 'echo "UUID=01234567-ffff-aaaa-bbbb-abcdef012345 /var/lib/ceph/cp xfs defaults 0 0" >> /etc/fstab'

Repeat all preceeding steps in this section for each journal device in
the Ceph cluster. After this is completed for all journals, mount the
partitions:

::

    sudo mount -a

Promenade bootstrap
~~~~~~~~~~~~~~~~~~~

Copy the ``${NEW_SITE}_bundle`` and ``${NEW_SITE}_collected``
directories from the build node to the genesis node, into the home
directory of the user there (e.g., ``/home/ubuntu``). Then, run the
following script as sudo on the genesis node:

::

    cd ${NEW_SITE}_bundle
    sudo ./genesis.sh

Estimated runtime: **40m**

Following completion, run the ``validate-genesis.sh`` script to ensure
correct provisioning of the genesis node:

::

    cd ${NEW_SITE}_bundle
    sudo ./validate-genesis.sh

Estimated runtime: **2m**

Deploy Site with Shipyard
-------------------------

Start by cloning the shipyard repository to the Genesis node:

::

    git clone https://github.com/openstack/airship-shipyard

Refer to the ``data/charts/ucp/shipyard/reference`` field in
``airship-treasuremap/global/v4.0/software/config/versions.yaml``. If
this is a pinned reference (i.e., any reference that's not ``master``),
then you should checkout the same version of the Shipyard repository.
For example, if the Shipyard reference was ``7046ad3...`` in the
versions file, checkout the same version of the Shipyard repo which was
cloned previously:

::

    (cd airship-shipyard && git checkout 7046ad3)

Likewise, before running the ``deckhand_load_yaml.sh`` script, you
should refer to the ``data/images/ucp/shipyard/shipyard`` field in
``airship-treasuremap/global/v4.0/software/config/versions.yaml``. If
there is a pinned reference (i.e., any image reference that's not
``latest``), then this reference should be used to set the
``SHIPYARD_IMAGE`` environment variable. For example, if the Shipyard
image was pinned to ``quay.io/airshipit/shipyard@sha256:dfc25e1...`` in
the versions file, then export the previously mentioned environment
variable:

::

    export SHIPYARD_IMAGE=quay.io/airshipit/shipyard@sha256:dfc25e1...

Export valid login credentials for one of the Airship Keystone users defined
for the site. Currently there is no authorization checks in place, so
the credentials for any of the site-defined users will work. For
example, we can use the ``shipyard`` user, with the password that was
defined in
``airship-treasuremap/site/$NEW_SITE/secrets/passphrases/ucp_shipyard_keystone_password.yaml``.
Ex:

::

    export OS_USERNAME=shipyard
    export OS_PASSWORD=46a75e4...

(Note: Default auth variables are defined
`here <https://github.com/openstack/airship-shipyard/blob/master/tools/shipyard_docker_base_command.sh>`__,
and should otherwise be correct, barring any customizations of these
site parameters).

Next, run the deckhand\_load\_yaml.sh script as follows:

::

    sudo airship-shipyard/tools/deckhand_load_yaml.sh ${NEW_SITE} ${NEW_SITE}_collected

Estimated runtime: **3m**

Now deploy the site with shipyard:

::

    sudo airship-shipyard/tools/deploy_site.sh

Estimated runtime: **1h30m**

The message ``Site Successfully Deployed`` is the expected output at the
end of a successful deployment. In this example, this means that Airship and
OSH should be fully deployed.

Disable password-based login on Genesis
---------------------------------------

Before proceeding, verify that your SSH access to the Genesis node is
working with your SSH key (i.e., not using password-based
authentication).

Then, disable password-based SSH authentication on Genesis in
``/etc/ssh/sshd_config`` by uncommenting the ``PasswordAuthentication``
and setting its value to ``no``. Ex:

::

    PasswordAuthentication no

Then, restart the ssh service:

::

    sudo systemctl restart ssh

