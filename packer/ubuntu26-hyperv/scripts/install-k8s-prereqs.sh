#!/usr/bin/env bash
# Bake Kubernetes node prerequisites into the golden image.
# Nodes are NOT joined to a cluster here — that happens via Ansible/kubeadm later.
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
K8S_VERSION="${K8S_VERSION:-1.31}"

# Do NOT use unbounded `cloud-init status --wait` — if cloud-init stays "running"
# (e.g. apt still in runcmd), Packer hangs forever. Bound the wait, then continue.
wait_cloud_init_bounded() {
  local max_secs="${1:-180}"
  local waited=0
  while (( waited < max_secs )); do
    local st
    st="$(cloud-init status 2>/dev/null | awk '{print $2}' | tr -d ',' || true)"
    case "$st" in
      done|error|disabled) echo "cloud-init status: $st"; return 0 ;;
    esac
    sleep 5
    waited=$((waited + 5))
  done
  echo "WARN: cloud-init still not done after ${max_secs}s; continuing anyway"
  cloud-init status || true
}

wait_apt_unlock() {
  local max_secs="${1:-300}"
  local waited=0
  while (( waited < max_secs )); do
    if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
      && ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  echo "WARN: apt locks still held after ${max_secs}s"
}

wait_cloud_init_bounded 180
wait_apt_unlock 300

# --- swap off (kubelet requirement) ---
sudo swapoff -a || true
if [ -f /etc/fstab ]; then
  sudo sed -i.bak -E 's|^([^#].*\s+swap\s+)|#\1|' /etc/fstab || true
fi

# --- kernel modules ---
cat <<'EOF' | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay || true
sudo modprobe br_netfilter || true

# --- sysctl ---
cat <<'EOF' | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system || true

# --- base packages ---
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# --- containerd ---
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
# Use systemd cgroup driver (kubeadm default recommendation)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl enable containerd
sudo systemctl restart containerd

# --- Kubernetes apt repo (pkgs.k8s.io) ---
sudo mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet

# Pre-pull is skipped in the golden image to keep size down and avoid stale layers.
# Ansible may run `kubeadm config images pull` on first control-plane bring-up.

sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
