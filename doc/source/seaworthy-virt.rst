Multi-node development environment
==================================

Airship-in-a-bottle multi-node is a simulated
`Treasure map <https://opendev.org/airship/treasuremap>`__ deployment
using only virtual machines that run within a single hypervisor. This gives
great control over things like network topology, 'hardware'
configuration and the like. It also introduces some limitations. Overall
the framework should allow most developers to test with a high degree of
certainty that a proposed change will be successful.

Mechanics
---------

The automation framework is contained in the
`airship-in-a-bottle <https://opendev.org/airship/in-a-bottle>`__
repository. This framework is based on original work by Mark Burnett in
the `Airship/Promenade <https://opendev.org/airship/promenade>`__ project.
There are several parallel pieces of automation in this repository, we will
focus on the tooling under ``tools/multi_nodes_gate``.

Currently the framework is hard-coded to source the deployment
definition from the ``deployment_files`` directory within the repository.
Specifically the framework attempts to deploy the site
``deployment_files/site/gate-multinode``. Below we will describe how we
can merge this framework with our
`Treasure map <https://opendev.org/Airship/Treasuremap>`__ definitions.

Here is a brief overview of the components within ``tools/multinode_gate``:

-  ``./setup_gate.sh`` - Must be run once on the host machine to install
   necessary packages/tools and set them up appropriately
-  ``./gate.sh`` - entrypoint to running the framework, run with an
   argument of the scenario you'd like to simulate. Default scenario is
   ``multinode_deploy``.
-  ``./airship_gate/manifests`` - JSON files that drive the various
   "scenarios" that can be executed by the gate.
-  ``./airship_gate/stages`` - The scripts that are called based on the
   stages section of a scenario manifest. These should be loose wrappers
   around calling library scripts from lib.
-  ``./airship_gate/lib`` - All of the framework script libraries
-  ``./airship_gate/bin`` - Utility binaries that can be used during
   testing/troubleshooting


Host Setup (Required once)
--------------------------

Recommended minimum requirements:
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-  64GB RAM
-  24 vCPUs
-  300 GB disk


Configure /etc/profile
~~~~~~~~~~~~~~~~~~~~~~

Add the following lines to ``/etc/profile`` or create a seperate env
file that you can ``source`` separately. These environment variables are used
at various stages throughout the pipeline,

*NOTE: /etc/environment does not work well with (") or with nested env
variables*

.. code-block:: bash

    export TEMP_DIR="$HOME/airship-in-a-bottle/tools/multi_nodes_gate/temp"
    export IMAGE_PROMENADE_CLI="quay.io/airshipit/promenade:b417f422e9cd2a921646ee0af4a05fc4e211beab"
    export IMAGE_PEGLEG_CLI="quay.io/airshipit/pegleg:50ce7a02e08a0a5277c2fbda96ece6eb5782407a"
    export IMAGE_SHIPYARD_CLI="quay.io/airshipit/shipyard:f4f57a1bbf3cc9ca6c868a11cc8923326c81b6dc"
    export IMAGE_COREDNS="docker.io/coredns/coredns:1.1.3"
    export IMAGE_QUAGGA="cumulusnetworks/quagga:CL3.3.2"
    export IMAGE_DRYDOCK_CLI="quay.io/airshipit/drydock@:54ea0e1374ddd18a5195edc418b5c0b042666f45"
    export BASE_IMAGE_URL="https://cloud-images.ubuntu.com/releases/16.04/release/ubuntu-16.04-server-cloudimg-amd64-disk1.img"
    export UPSTREAM_DNS="8.8.8.8 8.8.4.4"
    export AIRSHIP_KEYSTONE_URL="http://keystone.gate.local:80/v3"
    export SHIPYARD_OS_PASSWORD=password123
    export VIRSH_CPU_OPTS="Westmere"
    export USE_EXISTING_SECRETS="true"
    export GATE_SSH_KEY="$HOME/.ssh/id_rsa_airship"
    # export NTP_POOLS=""

Don't forget to ``source`` in the new set of env variables

.. code-block:: bash

    source /etc/profile

.. code-block:: bash

    source < your own env file >


Create libvirtd group and add user virtmgr
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

    sudo groupadd libvirtd
    sudo useradd virtmgr
    sudo usermod -a -G libvirtd virtmgr

**If you are using Ubuntu 18.04, add this step:**

.. code-block:: bash

    sudo groupadd libvirt
    sudo usermod -a -G libvirt virtmgr

Clone the Repositories
~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

    git clone https://opendev.org/airship/in-a-bottle.git ~/airship-in-a-bottle
    git clone https://opendev.org/airship/treasuremap.git ~/airship-in-a-bottle/treasuremap

Set up SSH Keys
~~~~~~~~~~~~~~~

.. code-block::

    cat ~/airship-in-a-bottle/treasuremap/site/seaworthy-virt/secrets/passphrases/airship_drydock_kvm_ssh_key.yaml
        => Copy the block from '-----BEGIN RSA PRIVATE KEY-----' till '-----END RSA PRIVATE KEY-----' and create ${HOME}/.ssh/id_rsa_airship
    cat ~/airship-in-a-bottle/treasuremap/site/seaworthy-virt/secrets/passphrases/airship_ubuntu_ssh_public_key.yaml
        => Copy only the ssh-rsa string and create ${HOME}/.ssh/id_rsa_airship.pub

Replace multinode_deploy.json with virtual seaworthy stages
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
``~/airship-in-a-bottle/tools/multi_nodes_gate/airship_gate/manifests/multinode_deploy.json``

.. literalinclude:: ./seaworthy-virt/multinode_deploy.json
    :language: json

Create a temp directory for generated files
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

    mkdir ~/airship-in-a-bottle/tools/multi_nodes_gate/temp/

Run the setup script
~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

    cd ~/airship-in-a-bottle/tools/multi_nodes_gate/
    ./setup_gate.sh

A reboot is recommended after this

Deploy the Site
---------------

Repeat this process as many times as required.

If you want to test specific patch sets, pull them to the treasure map
repository before running the gate.

Remove the generated files and run
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

    cd ~/airship-in-a-bottle/tools/multi_nodes_gate/
    rm -rf temp/*
    ./gate.sh

Update the Site
---------------

Replace the contents of update_site.json
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
``~/airship-in-a-bottle/tools/multi_nodes_gate/airship_gate/manifests/update_site.json``

.. literalinclude:: ./seaworthy-virt/update_site.json
    :language: json


Run update site
~~~~~~~~~~~~~~~

Once you have made the changes on your manifests, Run the update site action

.. code-block:: bash

    cd ~/airship-in-a-bottle/tools/multi_nodes_gate
    ./gate.sh update_site
