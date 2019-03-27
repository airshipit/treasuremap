=================
Development Guide
=================

Welcome
-------

Thank you for your interest in Airship. Our community is eager to help you
contribute to the success of our project and welcome you as a member of our
community!

We invite you to reach out to us at any time via the `Airship mailing list`_ or
`#airshipit IRC channel`_ on freenode.

Welcome aboard!

.. _Airship mailing list: http://lists.airshipit.org

.. _#airshipit IRC channel: irc://chat.freenode.net:6667

Getting Started
---------------

Airship is a collection of open source tools for automating cloud provisioning
and management. Airship provides a declarative framework for defining and
managing the life cycle of open infrastructure tools and the underlying
hardware. These tools include OpenStack for virtual machines, Kubernetes for
container orchestration, and MaaS for bare metal, with planned support for
OpenStack Ironic.

We recommend that new contributors begin by reading the high-level architecture
overview included in our `treasuremap`_ documentation. The architectural
overview introduces each Airship component, their core responsibilities, and
their integration points.

.. _treasuremap: https://airship-treasuremap.readthedocs.io/en/latest

Deep Dive
---------

Each Airship component is accompanied by its own documentation that provides an
extensive overview of the component. With so many components, it can be
challenging to find a starting point.

We recommend the following:

Try an Airship environment
~~~~~~~~~~~~~~~~~~~~~~~~~~

Airship provides two single-node environments for demo and development purpose.

`Airship-in-a-Bottle`_ is a set of reference documents and shell scripts that
stand up a full Airship environment with the execution of a script.

`Airskiff`_ is a light-weight development environment bundled with a set of
deployment scripts that provides a single-node Airship environment. Airskiff
uses minikube to bootstrap Kubernetes, so it does not include Drydock, MaaS, or
Promenade.

Additionally, we provide a reference architecture for easily deploying a
smaller, demo site.

`Airsloop`_ is a fully-authored Airship site that can be quickly deployed as a
baremetal, demo lab.

.. _Airship-in-a-Bottle: https://opendev.org/airship/in-a-bottle

.. _Airskiff: https://airship-treasuremap.readthedocs.io/en/latest/airskiff.html

.. _Airsloop: https://airship-treasuremap.readthedocs.io/en/latest/airsloop.html

Focus on a component
~~~~~~~~~~~~~~~~~~~~

When starting out, focusing on one Airship component allows you to become
intricately familiar with the responsibilities of that component and understand
its function in the Airship integration. Because the components are modeled
after each other, you will also become familiar with the same patterns and
conventions that all Airship components use.

Airship source code lives in the `OpenDev Airship namespace`_. To clone an
Airship project, execute the following, replacing `<component>` with the name
of the Airship component you want to clone.

.. code-block bash::

  git clone https://opendev.org/airship/<component>.git

Refer to the component's documentation to get started. A list of each
component's documentation is listed below for reference:

    * `Armada`_
    * `Deckhand`_
    * `Divingbell`_
    * `Drydock`_
    * `Pegleg`_
    * `Promenade`_
    * `Shipyard`_

.. _OpenDev Airship namespace: https://opendev.org/airship

.. _Armada: https://airship-armada.readthedocs.io

.. _Deckhand: https://airship-deckhand.readthedocs.io

.. _Divingbell: https://airship-divingbell.readthedocs.io

.. _Drydock: https://airship-drydock.readthedocs.io

.. _Pegleg: https://airship-pegleg.readthedocs.io

.. _Promenade: https://airship-promenade.readthedocs.io

.. _Shipyard: https://airship-shipyard.readthedocs.io

Find a Storyboard task or story
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Airship work items are tracked using Storyboard. A board of items can be found
`here`_.

Once you find an item to work on, simply assign the item to yourself or leave a
comment that you plan to provide implementation for the item.

.. _here: https://storyboard.openstack.org/#!/project_group/85

Testing Changes
---------------

Testing of Airship changes can be accomplished several ways:

    #. Standalone, single component testing
    #. Integration testing
    #. Linting, unit, and functional tests/linting

.. note:: Testing changes to charts in Airship repositories is best
    accomplished using the integration method describe below.

Standalone Testing
~~~~~~~~~~~~~~~~~~

Standalone testing of Airship components, i.e. using an Airship component as a
Python project, provides the quickest feedback loop of the three methods and
allows developers to make changes on the fly. We recommend testing initial code
changes using this method to see results in real-time.

Each Airship component written in Python has pre-requisites and guides for
running the project in a standalone capacity. Refer to the documentation listed
below.

    * `Armada`_
    * `Deckhand`_
    * `Drydock`_
    * `Pegleg`_
    * `Promenade`_
    * `Shipyard`_

Integration Testing
~~~~~~~~~~~~~~~~~~~

While each Airship component supports individual usage, Airship components
have several integration points that should be exercised after modifying
functionality.

We maintain several environments that encompass these integration points:

    #. `Airskiff`_: Integration of Armada, Deckhand, Shipyard, and Pegleg
    #. `Airship-in-a-Bottle Multinode`: Full Airship integration

For changes that merely impact software delivery components, exercising a full
Airskiff deployment is often sufficient. Otherwise, we recommend using the
Airship-in-a-Bottle Multinode environment.

Each environment's documentation covers the process required to build and test
component images.

.. _Airskiff: https://airship-treasuremap.readthedocs.io/en/latest/
    airskiff.html

.. _Airship-in-a-Bottle Multinode: http://git.openstack.org/cgit/openstack/
    airship-in-a-bottle/tree/tools/multi_nodes_gate/README.rst

Final Checks
~~~~~~~~~~~~

Airship projects provide Makefiles to run unit, integration, and functional
tests as well as lint Python code for PEP8 compliance and Helm charts for
successful template rendering. All checks are gated by Zuul before a change can
be merged. For more information on executing these checks, refer to
project-specific documentation.

Third party CI tools, such as Jenkins, report results on Airship-in-a-Bottle
patches. These can be exposed using the "Toggle CI" button in the bottom
left-hand page of any gerrit change.

Pushing code
------------

Airship uses the `OpenDev gerrit`_ for code review. Refer to the `OpenStack
Contributing Guide`_ for a tutorial on submitting changes to Gerrit code
review.

.. _OpenDev gerrit: https://review.opendev.org

.. _OpenStack Contributing Guide: https://docs.openstack.org/horizon/latest/contributor/contributing.html

Next steps
----------

Upon pushing a change to gerrit, Zuul continuous integration will post job
results on your patch. Refer to the job output by clicking on the job itself to
determine if further action is required. If it's not clear why a job failed,
please reach out to a team member in IRC. We are happy to assist!

Assuming all continuous integration jobs succeed, Airship community members and
core developers will review your patch and provide feedback. Many patches are
submitted to Airship projects each day. If your patch does not receive feedback
for several days, please reach out using IRC or the Airship mailing list.

Merging code
------------

Like most OpenDev projects, Airship patches require two +2 code review votes
from core members to merge. Once you have addressed all outstanding feedback,
your change will be merged.

Beyond
------

Congratulations! After your first change merges, please keep up-to-date with
the team. We hold two weekly meetings for project and design discussion:

Our weekly #airshipit IRC meeting provides an opportunity to discuss project
operations.

Our weekly design call provides an opportunity for in-depth discussion of new
and existing Airship features.

For more information on the times of each meeting, refer to the `Airship
wiki`_.

.. _Airship wiki: https://wiki.openstack.org/wiki/Airship
