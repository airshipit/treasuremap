#!/bin/bash
set -ex

sudo chmod 700 patroni_endpoint_cleaner.sh
sudo cp patroni_endpoint_cleaner.sh /opt

cat > ./patroni_endpoint_cleaner.service << EOF
[Unit]
Description=Helper script for initial upgrade to HA Postgres

[Service]
ExecStart=/opt/patroni_endpoint_cleaner.sh

[Install]
WantedBy=multi-user.target
EOF

sudo mv patroni_endpoint_cleaner.service /lib/systemd/system/

sudo systemctl restart patroni_endpoint_cleaner
sudo systemctl enable patroni_endpoint_cleaner
sudo systemctl daemon-reload
