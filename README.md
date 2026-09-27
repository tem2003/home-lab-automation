# Home lab automation (Windows + Hyper-V)

**Platform: Windows 10/11 or Windows Server with Hyper-V enabled.**  
This lab is built for a **Windows Hyper-V** host only — not VMware, VirtualBox, Proxmox, or cloud VMs.

It brings up a dual-cluster Kubernetes + multi-primary Istio environment on Hyper-V:

1. **Packer** — Ubuntu golden **VHDX** for Hyper-V Gen2 ([`packer/ubuntu26-hyperv`](packer/ubuntu26-hyperv))
2. **Terraform** — create Hyper-V VMs for `cluster1` + `cluster2`, NoCloud identity, Ansible inventory ([`terraform/hyperv-k8s`](terraform/hyperv-k8s))
3. **Ansible** — kubeadm, Flannel, Istio multi-primary, smoke apps ([`ansible`](ansible))

## Requirements

- Windows host with the **Hyper-V** role/feature enabled
- Elevated PowerShell (or membership in Hyper-V Administrators)
- An existing Hyper-V virtual switch (default name: `hyper-v-switch`)
- Packer, Terraform, WSL (for seed ISOs / Ansible), and an SSH key pair

## Quick start

```powershell
cd D:\automation
.\scripts\deploy-lab.ps1
```

Or Terraform only (dev env):

```powershell
cd D:\automation\terraform\hyperv-k8s\envs\dev
terraform init
terraform apply
```

Full docs: [`docs/multi-cluster-istio.md`](docs/multi-cluster-istio.md).
