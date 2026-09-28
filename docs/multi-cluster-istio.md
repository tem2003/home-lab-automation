# Dual-cluster Kubernetes + multi-primary Istio on Hyper-V

Lab topology: **two kubeadm clusters** (`cluster1`, `cluster2`) on Hyper-V Ubuntu nodes, joined into an **Istio multi-primary / multi-network** mesh for cross-cluster experimentation.

## Pipeline

```text
Packer golden VHDX (containerd + kubeadm pkgs)
  → Terraform (copy VHDX, NoCloud hostname, start VMs, Ansible inventory)
    → Ansible (kubeadm ×2, Flannel, Istio multi-primary, smoke apps)
```

One-shot from an elevated PowerShell on the Hyper-V host:

```powershell
cd <repo-root>
.\scripts\deploy-lab.ps1
```

Destroy VMs (keeps golden image):

```powershell
.\scripts\destroy-lab.ps1
```

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| Hyper-V + switch `hyper-v-switch` | Prefer **External** on a working NIC (e.g. Ethernet). Packer needs a real host IP on that switch — not Disconnected / 169.254 APIPA. Fix: `.\scripts\fix-hyperv-switch.ps1` |
| Packer ≥ 1.11, Terraform ≥ 1.5 | |
| WSL Ubuntu | `genisoimage`, `ansible`, `openssl`; `kubectl`/`istioctl` optional (Ansible can install istioctl) |
| SSH key | Default `~\.ssh\id_ed25519` (pub+priv) |
| RAM | ~24 GiB+ free for 6 × 4 GiB nodes |

Firewall: allow Packer HTTP ports if rebuilding via ISO flows; cloud-image Packer uses SSH after NoCloud.

### Packer: "No ip address" on Hyper-V

If build fails with `Error getting host adapter ip address: No ip address`, the switch’s host vNIC is down or APIPA-only. Rebind to your LAN NIC (Admin PowerShell):

```powershell
cd <repo-root>
.\scripts\fix-hyperv-switch.ps1 -NetAdapterName "Ethernet 4"
.\scripts\deploy-lab.ps1
```

## Network plan

Node IPs stay on the home LAN (`192.168.50.0/24`). Pod/service CIDRs are unique
per env+cluster so all four clusters can run together without overlay clashes.

| Env | Cluster | Pod CIDR | Service CIDR | Istio network |
|-----|---------|----------|--------------|---------------|
| dev | cluster1 | `10.244.0.0/16` | `10.96.0.0/16` | `network-dev-1` |
| dev | cluster2 | `10.245.0.0/16` | `10.97.0.0/16` | `network-dev-2` |
| stable | cluster1 | `10.246.0.0/16` | `10.98.0.0/16` | `network-stable-1` |
| stable | cluster2 | `10.247.0.0/16` | `10.99.0.0/16` | `network-stable-2` |

Inventory sets `lab_env` (`dev` / `stable`); Ansible resolves CIDRs from `group_vars/all.yml`.

East-west gateways use **NodePort** (no MetalLB). Nodes on the same Hyper-V switch must reach each other.

## Manual phase commands

### Packer

```powershell
cd <repo-root>\packer\ubuntu26-hyperv
.\scripts\prepare-source-disk.ps1
.\scripts\write-packer-vars.ps1
.\scripts\build-nocloud-seed.ps1 -SshPublicKey (Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub -Raw).Trim()
packer init .
packer build -force .
```

Image includes: containerd (systemd cgroup), kubelet/kubeadm/kubectl (held), sysctl/modules, swap off. Nodes are **not** joined until Ansible.

### Terraform

```powershell
cd <repo-root>\terraform\hyperv-k8s\envs\dev
terraform init
terraform apply
```

Writes `ansible\inventory\dev.yml` when `start_vms = true`. Paths resolve from the repo root by default.

### Ansible (WSL)

```bash
cd /mnt/<drive>/<path-to-repo>/ansible
export ANSIBLE_CONFIG="$PWD/ansible.cfg"
ansible-playbook -i inventory/dev.yml playbooks/site.yml
# or stepwise:
ansible-playbook -i inventory/dev.yml playbooks/01-site-prep.yml
ansible-playbook -i inventory/dev.yml playbooks/02-kubeadm-cluster1.yml
ansible-playbook -i inventory/dev.yml playbooks/03-kubeadm-cluster2.yml
ansible-playbook -i inventory/dev.yml playbooks/04-cni.yml
ansible-playbook -i inventory/dev.yml playbooks/05-istio-multicluster.yml
ansible-playbook -i inventory/dev.yml playbooks/06-smoke-apps.yml
```

## Verification

```bash
export KUBECONFIG=/mnt/<drive>/<path-to-repo>/artifacts/kubeconfigs/dev-cluster1.conf
kubectl get nodes -o wide
kubectl -n istio-system get pods,svc
kubectl -n sample get pods -o wide

export KUBECONFIG=/mnt/<drive>/<path-to-repo>/artifacts/kubeconfigs/dev-cluster2.conf
kubectl get nodes -o wide

# From cluster1 sleep → helloworld (may hit v1 local and/or v2 remote after discovery)
export KUBECONFIG=/mnt/<drive>/<path-to-repo>/artifacts/kubeconfigs/dev-cluster1.conf
SLEEP=$(kubectl -n sample get pod -l app=sleep -o jsonpath='{.items[0].metadata.name}')
kubectl -n sample exec "$SLEEP" -- curl -sS helloworld.sample:5000/hello
```

Expect responses from **Hello version: v1** and eventually **v2** once endpoint discovery is healthy.

Other checks:

```bash
istioctl --kubeconfig /mnt/<drive>/<path-to-repo>/artifacts/kubeconfigs/dev-cluster1.conf proxy-status
kubectl --kubeconfig .../dev-cluster1.conf get secrets -n istio-system | grep -i remote
```

## Artifacts

| Path | Purpose |
|------|---------|
| `artifacts/kubeconfigs/{env}-cluster{1,2}.conf` | Admin kubeconfigs |
| `artifacts/certs/` | Shared root + per-cluster intermediate CAs |
| `ansible/inventory/dev.yml` | Generated inventory |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Inventory wait timeout | Confirm VMs Running; guest IP via Hyper-V NIC; hv-kvp / cloud-init finished |
| kubeadm join fails | Re-run control-plane play; check time sync; containerd running |
| Flannel not Ready | Confirm pod CIDR patch; `kubectl -n kube-flannel get pods -o wide` |
| No cross-cluster helloworld | Remote secrets present; east-west gateway Ready; node IPs reachable; wait for EDS |
| Ansible SSH auth | Inventory private key path must be WSL (`/mnt/c/...`); `deploy-lab.ps1` rewrites it |

## Non-goals (v1)

HA control planes, MetalLB, staging env, full observability (Kiali/Prometheus) — add later as needed.
