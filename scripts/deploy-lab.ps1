<#
.SYNOPSIS
  End-to-end Hyper-V dual-cluster Kubernetes + multi-primary Istio lab bring-up.

.PARAMETER SkipPacker
  Skip Packer golden image build even if VHDX is missing (fail instead).

.PARAMETER SkipTerraform
  Skip terraform apply (use existing VMs / inventory).

.PARAMETER SkipAnsible
  Skip Ansible site playbook.

.PARAMETER PackerForce
  Pass -force to packer build.
#>
param(
  [switch]$SkipPacker,
  [switch]$SkipTerraform,
  [switch]$SkipAnsible,
  [switch]$PackerForce,
  [string]$TfEnv = "dev",
  [string]$SshPublicKeyPath = "$env:USERPROFILE\.ssh\id_ed25519.pub",
  [string]$SshPrivateKeyPath = "$env:USERPROFILE\.ssh\id_ed25519"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$packerDir = Join-Path $root "packer\ubuntu26-hyperv"
$tfDir = Join-Path $root "terraform\hyperv-k8s\envs\$TfEnv"
$ansibleDir = Join-Path $root "ansible"
$artifactsDir = Join-Path $root "artifacts"
$goldenVhdx = Join-Path $packerDir "output-ubuntu26-hyperv\Virtual Hard Disks\ubuntu26-hyperv-packer.vhdx"
$inventoryPath = Join-Path $ansibleDir "inventory\$TfEnv.yml"

function ConvertTo-WslPath {
  param([string]$WinPath)
  $full = [IO.Path]::GetFullPath($WinPath)
  if ($full -match '^([A-Za-z]):\\') {
    $d = $Matches[1].ToLower()
    $rest = $full.Substring(3) -replace '\\', '/'
    return "/mnt/$d/$rest"
  }
  throw "Cannot convert to WSL path: $WinPath"
}

Write-Host "=== Lab root: $root ===" -ForegroundColor Cyan

if (-not (Test-Path $artifactsDir)) {
  New-Item -ItemType Directory -Path $artifactsDir -Force | Out-Null
}

# --- Packer ---
if (-not $SkipPacker) {
  $switchAlias = "vEthernet (hyper-v-switch)"
  $veth = Get-NetAdapter -Name $switchAlias -ErrorAction SilentlyContinue
  $vethIp = Get-NetIPAddress -InterfaceAlias $switchAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "169.254.*" } |
    Select-Object -First 1
  if (-not $vethIp -or ($veth -and $veth.Status -ne "Up")) {
    Write-Host @"

Packer preflight FAILED: Hyper-V switch host adapter has no usable IP.
  Adapter: $switchAlias
  Status:  $(if ($veth) { $veth.Status } else { 'missing' })
  IP:      $(if ($vethIp) { $vethIp.IPAddress } else { 'none / APIPA only' })

Packer error looks like: "Error getting host adapter ip address: No ip address."

Fix (elevated PowerShell), then re-run deploy-lab.ps1:
  .\scripts\fix-hyperv-switch.ps1 -NetAdapterName "Ethernet 4"

"@ -ForegroundColor Red
    throw "Hyper-V switch 'hyper-v-switch' is not usable for Packer (no host IP)."
  }
  if ((Test-Path $goldenVhdx) -and -not $PackerForce) {
    Write-Host "Golden VHDX exists, skipping Packer: $goldenVhdx" -ForegroundColor Green
  } else {
    Write-Host "Building Packer golden image..." -ForegroundColor Yellow
    if (-not (Test-Path $SshPublicKeyPath)) {
      throw "SSH public key not found: $SshPublicKeyPath"
    }
    if (-not (Test-Path $SshPrivateKeyPath)) {
      throw "SSH private key not found: $SshPrivateKeyPath"
    }
    Push-Location $packerDir
    try {
      & .\scripts\write-packer-vars.ps1 -SshPrivateKeyPath $SshPrivateKeyPath
      if (-not (Test-Path (Join-Path $packerDir "artifacts\nocloud-seed.iso"))) {
        & .\scripts\prepare-source-disk.ps1
        & .\scripts\build-nocloud-seed.ps1 -SshPublicKey (Get-Content $SshPublicKeyPath -Raw).Trim()
      } elseif (-not (Test-Path (Join-Path $packerDir "artifacts\ubuntu-26.04-server-cloudimg-amd64.vhdx"))) {
        & .\scripts\prepare-source-disk.ps1
      }
      packer init .
      if ($PackerForce) {
        packer build -force .
      } else {
        packer build .
      }
    } finally {
      Pop-Location
    }
    if (-not (Test-Path $goldenVhdx)) {
      throw "Packer finished but golden VHDX not found: $goldenVhdx"
    }
  }
} elseif (-not (Test-Path $goldenVhdx)) {
  throw "Golden VHDX missing and -SkipPacker was set: $goldenVhdx"
}

# --- Terraform ---
if (-not $SkipTerraform) {
  if (-not (Test-Path $tfDir)) {
    throw "Terraform env directory not found: $tfDir (expected envs/$TfEnv)"
  }
  Write-Host "Applying Terraform env=$TfEnv ..." -ForegroundColor Yellow
  Push-Location $tfDir
  try {
    terraform init -input=false
    $vmRootPath = Join-Path $root "hyperv-k8s-vms\$TfEnv"
    $tfArgs = @(
      "apply", "-auto-approve", "-input=false",
      "-var=golden_vhdx_path=$($goldenVhdx -replace '\\','/')",
      "-var=vm_root_path=$($vmRootPath -replace '\\','/')",
      "-var=ssh_public_key_path=$($SshPublicKeyPath -replace '\\','/')",
      "-var=ssh_private_key_path=$($SshPrivateKeyPath -replace '\\','/')",
      "-var=start_vms=true",
      "-var=ansible_inventory_path=$($inventoryPath -replace '\\','/')"
    )
    & terraform @tfArgs
    if ($LASTEXITCODE -ne 0) { throw "terraform apply failed with exit $LASTEXITCODE" }
  } finally {
    Pop-Location
  }
}

if (-not (Test-Path $inventoryPath)) {
  throw "Ansible inventory not found: $inventoryPath. Ensure terraform start_vms=true completed inventory discovery."
}

# Rewrite private key for WSL: /mnt/c/... is world-writable and OpenSSH rejects it.
$invText = Get-Content $inventoryPath -Raw
$wslKeyInHome = '~/.ssh/id_ed25519_lab'
$invText = $invText -replace 'ansible_ssh_private_key_file:\s*.+', "ansible_ssh_private_key_file: $wslKeyInHome"
[IO.File]::WriteAllText($inventoryPath, $invText)

# --- Ansible (WSL) ---
if (-not $SkipAnsible) {
  Write-Host "Running Ansible site playbook via WSL..." -ForegroundColor Yellow
  $ansibleWsl = ConvertTo-WslPath $ansibleDir
  $winKeyWsl = ConvertTo-WslPath $SshPrivateKeyPath
  $invWslRel = "inventory/$TfEnv.yml"
  # Write a UTF-8 (no BOM) LF script. Piping from PowerShell can inject a BOM or UTF-16
  # and break bash ("﻿set: command not found") / leave cwd wrong so playbooks are missing.
  $bash = @(
    'set -euo pipefail'
    'mkdir -p "$HOME/.ssh"'
    "cp '$winKeyWsl' `"`$HOME/.ssh/id_ed25519_lab`""
    'chmod 700 "$HOME/.ssh"'
    'chmod 600 "$HOME/.ssh/id_ed25519_lab"'
    "cd '$ansibleWsl'"
    'if ! command -v ansible-playbook >/dev/null 2>&1; then'
    '  echo "ansible-playbook not found in WSL. Install: sudo apt update && sudo apt install -y ansible"'
    '  exit 1'
    'fi'
    "export ANSIBLE_CONFIG='$ansibleWsl/ansible.cfg'"
    'export ANSIBLE_HOST_KEY_CHECKING=False'
    "ansible-playbook -i $invWslRel playbooks/site.yml"
  ) -join "`n"
  $bashFile = Join-Path $env:TEMP "deploy-lab-ansible-$TfEnv.sh"
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($bashFile, $bash + "`n", $utf8NoBom)
  $bashWsl = ConvertTo-WslPath $bashFile
  try {
    & wsl.exe bash $bashWsl
    if ($LASTEXITCODE -ne 0) { throw "ansible-playbook failed with exit $LASTEXITCODE" }
  } finally {
    Remove-Item -LiteralPath $bashFile -Force -ErrorAction SilentlyContinue
  }
}

Write-Host ""
Write-Host "=== Lab deploy complete ===" -ForegroundColor Green
Write-Host "Kubeconfigs:"
Write-Host "  $(Join-Path $artifactsDir "kubeconfigs\${TfEnv}-cluster1.conf")"
Write-Host "  $(Join-Path $artifactsDir "kubeconfigs\${TfEnv}-cluster2.conf")"
Write-Host ""
Write-Host "Verify (from WSL):"
Write-Host "  export KUBECONFIG=$(ConvertTo-WslPath (Join-Path $artifactsDir "kubeconfigs\${TfEnv}-cluster1.conf"))"
Write-Host "  kubectl get nodes -o wide"
Write-Host "  kubectl --kubeconfig=$(ConvertTo-WslPath (Join-Path $artifactsDir "kubeconfigs\${TfEnv}-cluster2.conf")) get nodes -o wide"
Write-Host "  # Cross-cluster: kubectl -n sample exec deploy/sleep -- curl helloworld.sample:5000/hello"
Write-Host ""
Write-Host "See docs/multi-cluster-istio.md for full verification steps."
