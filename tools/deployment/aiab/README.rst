..
    Copyright 2018 AT&T Intellectual Property.  All other rights reserved.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

Airship in a Bottle
-------------------

Use the airship-in-a-bottle.sh script to automatically deploy a demonstration
version of Airship. It will attempt to detect the required environment settings
and deploy an instance of Airship, including running a demo instance of
OpenStack (using OpenStack Helm), and creating a simple Virtual Machine.

To get started, run the following in a fresh Ubuntu 16.04 VM
(minimum 4vCPU/20GB RAM/32GB disk). This will deploy Airship and Openstack Helm
(OSH):

.. code-block:: bash

    sudo -i
    mkdir -p /root/deploy && cd "$_"
    git clone https://opendev.org/airship/treasuremap/
    cd /root/deploy/treasuremap/tools/deployment/aiab/
    ./airship-in-a-bottle.sh

This demonstration uses the images pinned in the versions file:
./global/software/config/versions.yaml

By default, files will be downloaded into and built in the /root/deploy
directory of the virtual machine being used to install this demo.

Note that this process will result in the contents of the VM to be modified
outside of that directory, and the VM should be intended to be discarded after
demo use.
