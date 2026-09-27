#!/usr/bin/env bash
# Run inside the guest (via Packer SSH) after cloud-init, before export.
# Prepares a cloneable template: cloud-init re-run on new nodes, unique machine id, new SSH host keys on first boot.
set -euxo pipefail

# Bounded wait — never hang Packer if cloud-init status stays "running".
max_secs=120
waited=0
while (( waited < max_secs )); do
  st="$(cloud-init status 2>/dev/null | awk '{print $2}' | tr -d ',' || true)"
  case "$st" in
    done|error|disabled) break ;;
  esac
  sleep 5
  waited=$((waited + 5))
done
cloud-init status || true

# Golden template: logs, seed, and machine-id so each clone can re-run cloud-init and get a new identity.
sudo cloud-init clean --logs --seed --machine-id
sudo rm -f /etc/ssh/ssh_host_*

# Optional: let clones pick up new DHCP, etc.
sudo rm -f /var/lib/NetworkManager/*.lease 2>/dev/null || true

# Packer issues shutdown via shutdown_command after this script.
