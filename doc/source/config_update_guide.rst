Configuration Update Guide
==========================

The guide contains the instructions for updating the configuration of
a deployed Airship environment. Please refer to
`Site Authoring and Deployment Guide <https://airship-treasuremap.readthedocs.io/en/latest/authoring_and_deployment.html>`__
if you do not have an Airship environment already deployed.

Update of an Airship environment consists of the following stages:

1. **Prepare the configuration**: before deploying any changes, a user
   should prepare and validate the manifests on a build node using
   `Airship Pegleg <https://airship-pegleg.readthedocs.io/en/latest/>`__.
2. **Deploy the changes**: during this stage, a user uploads the
   configuration to the Airship environment and starts the deployment using
   `Airship Shipyard <https://airship-shipyard.readthedocs.io/en/latest/>`__.

.. note::

    This guide assumes you have
    `Airship Pegleg <https://airship-pegleg.readthedocs.io/en/latest/>`__ and
    `Airship Shipyard <https://airship-shipyard.readthedocs.io/en/latest/>`__
    tools installed and configured; please refer to
    `Site Authoring and Deployment Guide <https://airship-treasuremap.readthedocs.io/en/latest/authoring_and_deployment.html>`__
    for the details.

Configuring Airship CLI
-----------------------

Clone the Airship Treasuremap repository and switch to correct version.

::

    git clone https://opendev.org/airship/treasuremap
    cd treasuremap/
    # List available tags.
    git tag --list
    # Switch to the version your site is using.
    git checkout {your-tag}
    # Go back to a previous directory.
    cd ..

Configure environment variables with the name of your site, and specify a path
to the directory where site configuration is stored; for this example, we use
`Airship Seaworthy <https://airship-treasuremap.readthedocs.io/en/latest/seaworthy.html>`__
site:

::

    export SITE=seaworthy
    export SITE_PATH=treasuremap/site/seaworthy

Updating the manifests
----------------------

Changing the configuration consists of the following steps:

1. Change site manifests.
2. Lint the manifests.
3. Collect the manifests.
4. Copy the manifests to the Airship environment.

Linting and collecting the manifests is done using
`Airship Pegleg <https://airship-pegleg.readthedocs.io/en/latest/>`__.

For this example, we are going to update a debug level for keystone logs
in a site layer.

.. note::

    It is also possible to update the configuration in a global layer;
    for more details on Airship layering mechanism see
    `Pegleg Definition Artifact Layout <https://airship-pegleg.readthedocs.io/en/latest/artifacts.html>`__
    documentation.

Create an override file
``${SITE_PATH}/software/charts/osh/openstack-keystone/keystone.yaml``
with the following content:

::

    ---
    schema: armada/Chart/v1
    metadata:
      schema: metadata/Document/v1
      name: keystone
      replacement: true
      layeringDefinition:
        abstract: false
        layer: site
        parentSelector:
          name: keystone-global
        actions:
          - method: merge
            path: .
      storagePolicy: cleartext
    data:
      values:
        conf:
          logging:
            logger_keystone:
              level: DEBUG
    ...

Check that the configuration is valid:

::

    sudo ./treasuremap/tools/airship pegleg site -r treasuremap/ \
      lint ${SITE}

Collect the configuration:

::

    sudo ./treasuremap/tools/airship pegleg site \
      -r treasuremap/ collect $SITE -s ${SITE}_collected

Copy the configuration to a node that has the access to the site's
Shipyard API, if the current node does not; this node can be one
of your controllers:

::

    scp -r ${SITE}_collected {genesis-ip}:/home/{user-name}/${SITE}_collected


Deploying the changes
---------------------

After you copied the manifests, there are just a few steps needed to start
the deployment:

1. Upload the changes to
   `Airship Deckhand <https://airship-deckhand.readthedocs.io/en/latest/>`__.
2. Start the deployment using
   `Airship Shipyard <https://airship-shipyard.readthedocs.io/en/latest/>`__.

Install Airship CLI as described in `Configuring Airship CLI`_ section.

Set the name of your site:

::
    export SITE=seaworthy

Configure credentials for accessing Shipyard; the password is stored
in ``ucp_shipyard_keystone_password`` secret, you can find it in
``site/seaworthy/secrets/passphrases/ucp_shipyard_keystone_password.yaml``
configuration file of your site.

::

    export OS_USERNAME=shipyard
    export OS_PASSWORD={shipyard_password}

Upload the changes to `Airship Deckhand <https://airship-deckhand.readthedocs.io/en/latest/>`__:

::

    # Upload the configuration.
    sudo -E ./treasuremap/tools/airship shipyard \
        create configdocs ${SITE} --replace --directory=${SITE}_collected

    # Commit the configuration.
    sudo -E ./treasuremap/tools/airship shipyard commit configdocs

Run the deployment:

::

    sudo -E ./treasuremap/tools/airship shipyard create action update_site

You can also run ``update_software`` instead of ``update_site`` which skips
hardware configuration and only applies the changes to services that are running
on top of Kubernetes.

Now you can track the deployment progress using the following commands:

::

    # Get all actions that were executed on you environment.
    sudo -E ./treasuremap/tools/airship shipyard get actions

    # Show all the steps within the action.
    sudo -E ./treasuremap/tools/airship shipyard describe action/{action_id}

All steps will have status ``success`` when the update finishes.
