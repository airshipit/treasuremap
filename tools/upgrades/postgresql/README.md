# PostgreSQL Patroni Upgrade Scripts

Upgrading a live site from the old, unclustered PostgreSQL chart to the newer,
Patroni-managed version takes a small amount of out-of-band scripting to ensure
a smooth hands-free upgrade.

## Prior to upgrade

The ``patroni_endpoint_cleaner_unit.sh`` script should be run prior to upgrading
the postgresql chart.  It installs a systemd unit which in turn will run
the ``patroni_endpoint_cleaner.sh`` script.  During chart upgrade, the script
will delete the postgresql endpoints, allowing Patroni to recreate them with the
appropriate annotations for it to manage them ongoing.

This documentation project outlines a reference architecture for automated
cloud provisioning and management, leveraging a collection of interoperable
open-source tools.

## Post upgrade

After the chart upgrade is complete, the ``patroni_endpoint_cleaner_remove.sh``
script should be run.  This will simply clean up the systemd unit that was
created previously.

