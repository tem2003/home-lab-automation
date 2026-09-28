# Home lab automation (Windows + Hyper-V, WSL, Packer, Terraform, Kubernetes, Istio, Flannel)

**Platform: Windows 10/11 or Windows Server with Hyper-V enabled.**  
This lab is built for a **Windows Hyper-V** host only — not VMware, VirtualBox, Proxmox, or cloud VMs.

It brings up a dual-cluster Kubernetes + multi-primary Istio environment on Hyper-V:

1. **Packer** — Ubuntu golden **VHDX** for Hyper-V Gen2 ([`packer/ubuntu26-hyperv`](packer/ubuntu26-hyperv))
2. **Terraform** — create Hyper-V VMs for `cluster1` + `cluster2`, NoCloud identity, Ansible inventory ([`terraform/hyperv-k8s`](terraform/hyperv-k8s))
3. **Ansible** — kubeadm, Flannel, Istio multi-primary, smoke apps ([`ansible`](ansible))

## Requirements (one-time host setup)

Run these on the Hyper-V host. Elevated PowerShell is required for Hyper-V and WSL install.

### 1. Enable Hyper-V

```powershell
# Windows 10/11 Pro/Enterprise (elevated)
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

# Or Windows Server
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools
```

Reboot if prompted. Confirm:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
Get-VMHost
```

Create (or reuse) an **External** virtual switch named `hyper-v-switch` bound to a working NIC. If Packer later fails with “No ip address”, fix with:

```powershell
cd D:\automation
.\scripts\fix-hyperv-switch.ps1 -NetAdapterName "Ethernet 4"   # use your real adapter name
```

### 2. Install WSL 2 + Ubuntu

```powershell
# Elevated PowerShell — installs WSL 2 and default Ubuntu
wsl --install
```

Reboot if asked, then finish Ubuntu first-boot (username/password). Confirm WSL 2:

```powershell
wsl --status
wsl -l -v
# VERSION column should be 2 for Ubuntu
```

If an old distro is still WSL 1:

```powershell
wsl --set-default-version 2
wsl --set-version Ubuntu 2
```

Optional: install Ubuntu explicitly:

```powershell
wsl --install -d Ubuntu
```

### 3. Install tools inside Ubuntu (WSL)

Open Ubuntu and run:

```bash
sudo apt update
sudo apt install -y ansible genisoimage openssh-client openssl curl

# Verify
ansible --version
ansible-playbook --version
genisoimage --version || mkisofs -version
```

**istioctl:** you do **not** need to install it manually. The Ansible Istio role downloads the pinned version (`1.29.2`) into `~/.local/bin/istioctl` on first run. Optional manual install is fine if you want the CLI for debugging.

**kubectl (optional on Windows or WSL):** handy for day-2 ops; not required for `deploy-lab.ps1`.

### 4. Install Packer and Terraform (Windows)

1. Download [Packer](https://developer.hashicorp.com/packer/install) and [Terraform](https://developer.hashicorp.com/terraform/install) Windows amd64 zips.
2. Extract somewhere permanent (e.g. `C:\Tools\packer`, `C:\Tools\terraform`).
3. Add those folders to your user **PATH**.
4. Open a **new** PowerShell and verify:

```powershell
packer version
terraform version
```

### 5. Install qemu-img (Windows)

Packer’s `prepare-source-disk.ps1` converts the Ubuntu cloud image (QCOW2) to a fixed VHDX and **requires `qemu-img` on PATH**. Without it, Packer fails with `qemu-img not found`.

1. Download the latest **64-bit** QEMU installer from [qemu.weilnetz.de/w64](https://qemu.weilnetz.de/w64/) (e.g. `qemu-w64-setup-….exe`).
2. Run the installer (default install path is usually `C:\Program Files\qemu`).
3. Add that folder to your user or system **PATH**.
4. Open a **new** PowerShell and verify:

```powershell
qemu-img --version
```

Alternative: install via [MSYS2](https://www.msys2.org/) (`pacman -S mingw-w64-x86_64-qemu`) and put the MSYS2 `mingw64\bin` directory on PATH — as long as `Get-Command qemu-img` succeeds in PowerShell.

You can skip this step only if you reuse an existing golden VHDX and run deploy with `-SkipPacker`.

### 6. SSH key pair

Generate once (Windows OpenSSH):

```powershell
# Skip if you already have id_ed25519
ssh-keygen -t ed25519 -C "home-lab" -f "$env:USERPROFILE\.ssh\id_ed25519"
```

Defaults used by this repo:

| Key | Default path |
|-----|----------------|
| Public | `%USERPROFILE%\.ssh\id_ed25519.pub` |
| Private | `%USERPROFILE%\.ssh\id_ed25519` |

**Where to update if your paths differ:**

| File | Variables |
|------|-----------|
| [`terraform/hyperv-k8s/envs/dev/terraform.tfvars`](terraform/hyperv-k8s/envs/dev/terraform.tfvars) | `ssh_public_key_path`, `ssh_private_key_path` |
| [`terraform/hyperv-k8s/envs/stable/terraform.tfvars`](terraform/hyperv-k8s/envs/stable/terraform.tfvars) | same |
| [`scripts/deploy-lab.ps1`](scripts/deploy-lab.ps1) | parameters `-SshPublicKeyPath` / `-SshPrivateKeyPath` (or edit defaults) |
| Packer vars | `ssh_private_key_path` in `packer/ubuntu26-hyperv/ubuntu26.auto.pkrvars.hcl` (copy from `.example`) |

`deploy-lab.ps1` copies the Windows private key into WSL as `~/.ssh/id_ed25519_lab` (mode `600`) for Ansible. You do not need to do that by hand when using the script.

### 7. What `deploy-lab.ps1` already handles

Once the above is installed, the script can:

- Build / reuse the Packer golden VHDX  
- `terraform apply` for the chosen env  
- Rewrite inventory + copy the SSH key into WSL  
- Run `ansible-playbook playbooks/site.yml` (which installs **istioctl** if missing)

It does **not** install Hyper-V, WSL, Ubuntu, Ansible, Packer, Terraform, or **qemu-img** for you.

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

Ansible only (VMs + inventory already exist):

```powershell
.\scripts\deploy-lab.ps1 -SkipPacker -SkipTerraform -TfEnv dev
```

Full docs: [`docs/multi-cluster-istio.md`](docs/multi-cluster-istio.md).
