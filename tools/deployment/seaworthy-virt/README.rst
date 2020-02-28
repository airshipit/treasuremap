..
      Copyright 2018 AT&T Intellectual Property.
      All Rights Reserved.

      Licensed under the Apache License, Version 2.0 (the "License"); you may
      not use this file except in compliance with the License. You may obtain
      a copy of the License at

          http://www.apache.org/licenses/LICENSE-2.0

      Unless required by applicable law or agreed to in writing, software
      distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
      WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
      License for the specific language governing permissions and limitations
      under the License.

.. _gates:

Gates
=====
Treasuremap contains scripts to aid developers and automation of Airship.
These tools are found in ./treasuremap/tools/deployment

Setup and Use
-------------

1. First time, and only needed once per node, ./setup_gate.sh will prepare the
   node for use by setting up the necessary users, virsh and some dependencies.
2. gate.sh is the starting point to run each of the named gates, found in
   ./airship_gate/manifests, e.g.::

     $ ./gate.sh multinode_deploy

   where the argument for the gate.sh script is the filename of the json file
   in ./airship_gate/manifests without the json extension.
   if you run the script without any arguments::

     $ ./gate.sh

   then it will by default stand up a four-node Airship cluster.

   If you'd like to bring your own manifest to drive the framework, you can
   set and export the GATE_MANIFEST env var prior to running gate.sh

Each of the defined manifests used for the gate defines a virtual machine
configuration, and the steps to run as part of that gate. Additional
information found in each file is a configuration that targets a particular
set of Airship site configurations, which in some of the provided manifests are
found in the deployment_files/site directory.

Other Utilities
---------------
Several useful utilities are found in ./airship_gate/bin to facilitate
interactions with the VMs created. These commands are effectively wrapped
scripts providing the functionality of the utility they wrap, but also
incorporating the necessary identifying information needed for a particular
run of a gate. E.g.::

  $ ./airship_gate/bin/ssh.sh n0

Writing Manifests
-----------------

Custom manifests can be used to drive this framework with testing outside
the default virtual site deployment scenario. Here is some information on
how to create a manifest to define custom network or VM configuration or
run a custom stage pipeline. Manifest files are written in JSON and the
documentation below will use dotted JSON paths when describing structure.
Unless the root is otherwise defined, assume it is from the document root.

Network Configuration
#####################

The ``.networking`` key defines the network topology of the site. Each
subkey is the name of a network. Under each network name is a semi-recursive
stanza defining the layer 2 and layer 3 attributes of the network:

.. code-block: json

  {
    "roles": ['string'],
    "layer2": {
      "mtu": integer,
      "address": 'mac_address'
    },
    "layer3": {
       "cidr": "CIDR",
       "address": "ip_address",
       "gateway": "ip_address",
       "routing": {
         "mode": "nat"
       }
     }
  }

or

.. code-block: json

  {
    "layer2": {
      "mtu": integer,
      "vlans": {
        "integer": {
          "layer2":...,
          "layer3":...
        },
        "integer": {
          "layer2":...,
          "layer3":...
        }
      }
    }
  }


  * roles - These strings are used to select the correct network for internal
    gate functions - supported: "ssh", "dns", "bgp"
  * layer2 - Define Layer 2 attributes
  * layer3 - Valid if the ``layer2`` attribute is NOT defining VLANs, then
    define Layer 3 attributes.

Disk Layouts
############

The ``.disk_layouts`` key defines the various disk layouts that can be assigned
to VMs being built. Each named layout key then defines one or more block
devices that will be created as file-backed volumes.

.. code-block: json

  {
    "simple": {
      "vda": {
        "size": 30,
        "io_profile": "fast",
        "bootstrap": true
      }
    },
    "multi": {
      "vda": {
        "size": 15,
        "io_profile": "fast",
        "bootstrap": true
      },
      "vdb": {
        "size": 15,
        "io_profile": "fast",
        "format": {"type": "ext4", "mountpoint": "/var"}
      }
    }
  }


  * size - Size of the volume in gigabytes
  * io_profile - One of the below I/O configurations
    * fast - In the case of a VM disruption, synchronous I/O may be lost.
      Better throughput.
    * safe - Synchronous I/O fully written to disk, slower throughput.
    * unsafe - Host are caching all disk IO, and sync requests from VM are
      ignored. Max performance.
  * bootstrap - For VMs that are bootstrapped by the framework, not Airship,
    use this disk
  * format - For VMs that are bootstrapped by the framework, describe how the
    disk should be formatted and mounted when desired.
    * type - Filesystem type (e.g. 'xfs' or 'ext4')
    * mountpoint - Path to mountpoint

VM Configuration
################

Under the ``.vm`` key is a mapping of all the VMs that will be created via
virt-install. This can be a mix of VMs that are bootstrapped via
virsh/cloud-init and those deployed via Airship. Each key is the name of a VM
and value is a JSON object:

.. code-block: json

    {
      "memory": integer,
      "vcpus": integer,
      "sockets": integer,
      "threads": integer,
      "disk_layout": "simple",
      "cpu_mode": "host-passthrough",
      "networking": {
        "ens3": {
          "mac": "52:54:00:00:be:31",
          "model": "e1000",
          "pci": {
            "slot": 3,
            "port": 0
          },
          "attachment": {
            "network": "pxe"
          }
        },
        "addresses": {
          "pxe": {
             "ip": "172.24.1.9"
          }
        }
      },
      "bootstrap": true,
      "cpu_cells": {
        "cell0": {
          "cpus": "0-11",
          "memory": "25165824"
        },
        "cell1": {
          "cpus": "12-23",
          "memory": "25165824"
        }
      },
      "userdata": "packages: [docker.io]"
    }

  * memory - VM RAM in megabytes
  * vcpus - Number of VM CPUs
  * sockets - Number of sockets. (Optional)
  * threads - Number of threads. (Optional)
  * disk_layout - A disk profile for the VM matching one defined under
    ``.disk_layouts``
  * bootstrap - True/False for whether the framework should bootstrap the
    VM's OS
  * cpu_cells - Parameter to setup NUMA nodes and allocate RAM memory.
    (Optional)
  * cpu_mode - CPU mode for the VM. (if not specified, default: host)
  * userdata - Cloud-init userdata to feed the VM when bootstrapped for
    further customization
  * networking - Network attachment and addressing configuration. Every key
    but ``addresses`` is assumed to be a desired NIC on the VM. For each NIC
    stanza, the following fields are respected:

      * mac - A MAC address for the NIC
      * model - A model for the NIC (if not specified, default: virtio)
      * pci - A JSON object specifying ``slot`` and ``port`` specifying the
        PCI address for the NIC
      * attachment - What network from ``.networking`` is attached to this NIC

    The ``addresses`` key specifies the IP address for each layer 3 network
    that the VM is attached to.

Stage Pipeline
##############

TODO

External Access
###############

TODO
