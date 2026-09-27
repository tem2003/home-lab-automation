#!/usr/bin/env bash
set -euxo pipefail

# Keep image generic and compact for templating.
sudo cloud-init clean --logs || true
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
