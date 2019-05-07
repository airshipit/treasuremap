#!/bin/bash
set -x

echo "Cleaning up the patroni_endpoint_cleaner"
sudo systemctl stop patroni_endpoint_cleaner
sudo systemctl disable patroni_endpoint_cleaner
sudo rm -f /opt/patroni_endpoint_cleaner.sh
sudo rm -f /lib/systemd/system/patroni_endpoint_cleaner.service
sudo rm -f /etc/systemd/system/multi-user.target.wants/patroni_endpoint_cleaner.service
sudo systemctl daemon-reload
sudo systemctl reset-failed
