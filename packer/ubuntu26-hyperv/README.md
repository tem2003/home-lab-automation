# Ubuntu 26 Hyper-V Image Build (Packer)

This scaffold builds a **Hyper-V Generation 2** Ubuntu 26 **template** from the Ubuntu **cloud** image: SSH access for Packer, cloud-init, NoCloud `ssh_authorized_keys`, and a final **generalize** step so you can **clone** nodes and wire them with **Terraform** later.

The cloud `.img` is **QCOW2**; convert to a fixed **VHDX** first. The NoCloud **cidata** ISO (built on Windows) injects your **public** SSH key for user `ubuntu`.

## One-time: SSH key pair on Windows

PowerShell (OpenSSH client, included on recent Windows; install optional features if needed):

```powershell
# Ed25519 (recommended)
ssh-keygen -t ed25519 -C "packer-terraform" -f "$env:USERPROFILE\.ssh\id_ed25519"

# View public key (paste this into build-nocloud-seed.ps1)
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
```

Keep the **private** key path (e.g. `C:\Users\YourName\.ssh\id_ed25519`) in `ssh_private_key_path` in `ubuntu26.auto.pkrvars.hcl` — the **same** key is used to let Packer connect and to log into nodes you create from the template. For production clusters, you often add **node-specific** or **per-environment** keys in Terraform instead of reusing this one.

## Prerequisites (Windows host)

- Hyper-V enabled; virtual switch (default in vars: `hyper-v-switch`).
- [Packer](https://developer.hashicorp.com/packer/downloads) 1.11+.
- `qemu-img` for `prepare-source-disk.ps1` (script uses direct fixed VHDX conversion; `Convert-VHD` is fallback).
- **WSL** with `genisoimage` (e.g. `sudo apt update && sudo apt install -y genisoimage` in the default distro) for `build-nocloud-seed.ps1`.

## Build order (from `packer/ubuntu26-hyperv`)

1. **Convert** cloud image to VHDX (fixed) and get a `file:///...vhdx` path:

   ```powershell
   .\scripts\prepare-source-disk.ps1
   ```

   Optional: re-download source image:

   ```powershell
   .\scripts\prepare-source-disk.ps1 -ForceDownload
   ```

   Optional: explicitly set output disk size (recommended 64GB+ for updates/tools):

   ```powershell
   .\scripts\prepare-source-disk.ps1 -OutputSizeGb 64
   ```

2. **NoCloud** ISO with your **public** key (must match the private key in vars). In WSL, install a CD tool first: `sudo apt update && sudo apt install -y genisoimage`. Then from PowerShell:

   ```powershell
   .\scripts\build-nocloud-seed.ps1 -SshPublicKey (Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" -Raw).Trim()
   ```

   This writes `artifacts/nocloud-seed.iso` (see `nocloud_iso_relpath`).

3. **Vars** — generate machine-local Packer vars (or let `deploy-lab.ps1` do this):

   ```powershell
   .\scripts\write-packer-vars.ps1
   # optional: -SshPrivateKeyPath "C:\Users\<YOU>\.ssh\id_ed25519"
   ```

   This writes gitignored `ubuntu26.auto.pkrvars.hcl` with `ssh_private_key_path` and a `file:///` URL for the prepared VHDX. The `.example` file remains only as a reference.

4. **Build**:

   ```powershell
   packer init .
   packer validate .
   packer build -force .
   ```

If `output_directory` already exists, use `-force` or remove that folder first.

## What gets baked in

- **`nocloud/user-data`**: SSH key for `ubuntu`, disk grow/resize, `openssh-server`, kernel-matched Hyper-V KVP tools (Packer IP discovery). No Kubernetes packages.
- **`scripts/finalize-template.sh`**: `cloud-init clean`, reset `machine-id`, remove host SSH keys so each clone gets a unique identity.

Kubernetes (`containerd`, `kubeadm`/`kubelet`/`kubectl`) is installed later by Ansible (`roles/common`), not in the golden image.

**Terraform note:** Packer produces a **VHDX** (and export metadata). In Terraform, copy or attach the VHDX for each node, set a **unique** `name`/`host_name`, and pass per-node **user_data** (or a second small NoCloud ISO / config) if you need per-node `kubeadm join`, tokens, or taints. The template is generalized so **first boot of each clone** can run cloud-init again; you still need a **datasource** (NoCloud, config drive, or `user_data` provider support) for each VM if you inject per-node data — design that in your root module. Use `tls_private_key` / `openssh` only for *new* keys if you do not want to share the Packer key.

## Layout

- `main.pkr.hcl` — Hyper-V + secondary NoCloud ISO + SSH + `finalize` provisioner.
- `variables.pkr.hcl` — `nocloud_iso_relpath`, `ssh_private_key_path`, etc.
- `nocloud/user-data` — template with `__SSH_PUBLIC_KEY__` (replaced by the seed script).
- `scripts/prepare-source-disk.ps1` — QCOW2 → dynamic VHDX (resized).
- `scripts/build-nocloud-seed.ps1` — `user-data` + `meta-data` → `cidata` ISO.
- `scripts/write-packer-vars.ps1` — generate `ubuntu26.auto.pkrvars.hcl` for this host.
- `scripts/finalize-template.sh` — generalize for cloning.
- `scripts/install-k8s-prereqs.sh` — optional/legacy; **not** used by Packer (Ansible installs K8s later).
- `artifacts/` — generated VHDX and `nocloud-seed.iso` (ISO gitignored; `.gitkeep` kept).

## Notes

- Ubuntu cloud `*.img` is not an installer ISO; this flow is **VHDX + NoCloud** + **Packer over SSH** to generalize the disk.
- `differencing_disk = false` avoids sparse-parent issues; keep `artifacts` on normal uncompressed NTFS.
- If shell scripts are edited on Windows, keep **LF** line endings for the guest (Git `eol=lf` for `*.sh` is ideal).
