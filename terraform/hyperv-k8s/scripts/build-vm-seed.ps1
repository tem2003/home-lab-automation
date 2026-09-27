<#
  Builds a per-VM NoCloud (cidata) ISO for first-boot identity on a cloned golden VHDX.
  Requires WSL with genisoimage (or mkisofs).
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$Hostname,

  [Parameter(Mandatory = $true)]
  [string]$SshPublicKey,

  [Parameter(Mandatory = $true)]
  [string]$OutputIsoPath,

  [string]$Role = "",
  [string]$Cluster = "",
  [string]$EnvName = ""
)

$ErrorActionPreference = "Stop"

$outDir = Split-Path -Parent $OutputIsoPath
if (-not (Test-Path $outDir)) {
  New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$staging = Join-Path $outDir ("seed-staging-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $staging -Force | Out-Null

try {
  $instanceId = "iid-$Hostname-$(Get-Date -Format 'yyyyMMddHHmmss')"
  $meta = @"
instance-id: $instanceId
local-hostname: $Hostname
"@
  [IO.File]::WriteAllText((Join-Path $staging "meta-data"), $meta)

  $roleLine = if ($Role) { "      role: $Role" } else { "" }
  $clusterLine = if ($Cluster) { "      cluster: $Cluster" } else { "" }
  $envLine = if ($EnvName) { "      env: $EnvName" } else { "" }

  $userData = @"
#cloud-config
hostname: $Hostname
fqdn: $Hostname.local
manage_etc_hosts: true

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [adm, sudo, systemd-journal]
    shell: /bin/bash
    ssh_authorized_keys:
      - $($SshPublicKey.Trim())

ssh_pwauth: false

growpart:
  mode: auto
  devices: ["/"]
  ignore_growroot_disabled: false

resize_rootfs: true

package_update: false
package_upgrade: false

write_files:
  - path: /etc/node-info
    permissions: "0644"
    content: |
$roleLine
$clusterLine
$envLine
      hostname: $Hostname

runcmd:
  - [ hostnamectl, set-hostname, $Hostname ]
  - [ systemctl, enable, --now, ssh ]
  # Ubuntu 26 cloud images ship chrony (not systemd-timesyncd).
  - [ systemctl, enable, --now, chrony ]
  # containerd/kubelet are installed and started later by Ansible - do not start here.

final_message: "cloud-init finished for $Hostname"
"@
  [IO.File]::WriteAllText((Join-Path $staging "user-data"), $userData)

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

  if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    throw "WSL (wsl.exe) is required to build NoCloud seed ISOs."
  }

  $stagingWsl = ConvertTo-WslPath $staging
  $outWsl = ConvertTo-WslPath $OutputIsoPath
  $bashLine = "cd '$stagingWsl' && ( command -v genisoimage >/dev/null 2>&1 && genisoimage -o '$outWsl' -V cidata -J -R user-data meta-data ) || ( command -v mkisofs >/dev/null 2>&1 && mkisofs -o '$outWsl' -V cidata -J -R user-data meta-data ) || ( echo 'Missing genisoimage. In WSL: sudo apt install -y genisoimage' >&2; exit 1 )"
  & wsl.exe bash -lc $bashLine
  if ($LASTEXITCODE -ne 0) {
    throw "genisoimage/mkisofs failed with exit $LASTEXITCODE"
  }

  Write-Host "Wrote seed ISO: $OutputIsoPath"
}
finally {
  if (Test-Path $staging) {
    Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
  }
}
