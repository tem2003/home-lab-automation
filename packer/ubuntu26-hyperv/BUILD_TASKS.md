# Ubuntu 26 Hyper-V Packer Build Tasks

Run these in order from PowerShell.

## 1) Go to project folder

```powershell
cd D:\automation\packer\ubuntu26-hyperv
```

## 2) Create SSH key pair (one-time)

```powershell
ssh-keygen -t ed25519 -C "packer-terraform" -f "$env:USERPROFILE\.ssh\id_ed25519"
```

## 3) Verify key files exist

```powershell
Get-Item "$env:USERPROFILE\.ssh\id_ed25519","$env:USERPROFILE\.ssh\id_ed25519.pub"
```

## 4) Ensure WSL has ISO tool (one-time)

```powershell
wsl -e bash -lc "sudo apt update && sudo apt install -y genisoimage"
```

## 5) Convert Ubuntu cloud image to fixed VHDX

```powershell
.\scripts\prepare-source-disk.ps1 -OutputSizeGb 40
```

## 6) Build NoCloud seed ISO (inject your public key)

```powershell
.\scripts\build-nocloud-seed.ps1 -SshPublicKey (Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" -Raw).Trim()
```

## 7) Confirm artifacts are valid (not zero bytes)

```powershell
Get-Item .\artifacts\ubuntu-26.04-server-cloudimg-amd64.vhdx, .\artifacts\nocloud-seed.iso | Select-Object Name,Length,LastWriteTime
```

`nocloud-seed.iso` must be greater than `0` bytes.

## 8) Create vars file from example (if not already)

```powershell
Copy-Item .\ubuntu26.auto.pkrvars.hcl.example .\ubuntu26.auto.pkrvars.hcl -Force
```

## 9) Edit vars file (must-check values)

```powershell
notepad .\ubuntu26.auto.pkrvars.hcl
```

Ensure these are correct:

- `cloud_image_url = "file:///D:/automation/packer/ubuntu26-hyperv/artifacts/ubuntu-26.04-server-cloudimg-amd64.vhdx"`
- `nocloud_iso_relpath = "artifacts/nocloud-seed.iso"`
- `ssh_private_key_path = "C:/Users/<YOU>/.ssh/id_ed25519"`
- `switch_name = "hyper-v-switch"`

## 10) Confirm Hyper-V switch exists

```powershell
Get-VMSwitch -Name "hyper-v-switch"
```

## 11) Initialize Packer plugins

```powershell
packer init .
```

## 12) Validate config

```powershell
packer validate .
```

## 13) Build image

```powershell
packer build -force .
```

## 14) Verify output artifacts

```powershell
Get-ChildItem .\output-ubuntu26-hyperv -Recurse
```

Important result:

- `.\output-ubuntu26-hyperv\Virtual Hard Disks\ubuntu26-hyperv-packer.vhdx`

## Troubleshooting

| Packer waits forever on SSH; console shows login | Hyper-V Packer needs **hv-kvp-daemon** to learn the guest IP. Login at console (`ubuntu` / `TempDebug123!`) and run: `sudo apt-get update && sudo apt-get install -y linux-cloud-tools-virtual linux-tools-virtual && sudo systemctl enable --now hv-kvp-daemon`. Then rebuild the NoCloud seed (updated `nocloud/user-data` installs these automatically). |
| `nocloud-seed.iso` corrupted/unreadable | Re-run: |

```powershell
.\scripts\build-nocloud-seed.ps1 -SshPublicKey (Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" -Raw).Trim()
Get-Item .\artifacts\nocloud-seed.iso | Select Length
```

### B) Output directory already exists

```powershell
packer build -force .
```

or remove folder:

```powershell
Remove-Item -Recurse -Force .\output-ubuntu26-hyperv
```

### C) Packer cannot find key file

Check:

```powershell
Test-Path "C:\Users\<YOU>\.ssh\id_ed25519"
```

Then update `ssh_private_key_path` in vars accordingly.

### D) Hyper-V permission errors

Run PowerShell as Administrator or ensure your user is in `Hyper-V Administrators`.
