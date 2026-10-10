param(
  [Parameter(Mandatory = $true)]
  [string]$VmName,

  [Parameter(Mandatory = $true)]
  [string]$SwitchName,

  [Parameter(Mandatory = $true)]
  [string]$GoldenVhdxPath,

  [Parameter(Mandatory = $true)]
  [string]$VmRootPath,

  [string]$Role = "",
  [string]$Cluster = "",
  [string]$EnvName = "",
  [string]$SshPublicKeyPath = "",

  [int]$MemoryMb = 4096,
  [int]$CpuCount = 2,
  [int]$Generation = 2,
  [bool]$StartVm = $false
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $GoldenVhdxPath)) {
  throw "Golden VHDX not found: $GoldenVhdxPath"
}

$vmPath = Join-Path $VmRootPath $VmName
$vhdPath = Join-Path $vmPath "$VmName.vhdx"
$seedIsoPath = Join-Path $vmPath "$VmName-cidata.iso"
$memoryBytes = [Int64]$MemoryMb * 1MB
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$seedScript = Join-Path $scriptDir "build-vm-seed.ps1"

if (-not (Test-Path $VmRootPath)) {
  New-Item -ItemType Directory -Path $VmRootPath -Force | Out-Null
}
if (-not (Test-Path $vmPath)) {
  New-Item -ItemType Directory -Path $vmPath -Force | Out-Null
}

if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
  throw "Hyper-V switch '$SwitchName' was not found."
}

if (-not (Test-Path $vhdPath)) {
  Copy-Item -Path $GoldenVhdxPath -Destination $vhdPath -Force
}

# Build / refresh per-VM NoCloud seed when an SSH public key is provided.
if ($SshPublicKeyPath -and (Test-Path $SshPublicKeyPath)) {
  $pubKey = (Get-Content -Path $SshPublicKeyPath -Raw).Trim()
  & $seedScript `
    -Hostname $VmName `
    -SshPublicKey $pubKey `
    -OutputIsoPath $seedIsoPath `
    -Role $Role `
    -Cluster $Cluster `
    -EnvName $EnvName
}

$existingVm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if (-not $existingVm) {
  New-VM -Name $VmName -Generation $Generation -VHDPath $vhdPath -Path $vmPath -MemoryStartupBytes $memoryBytes -SwitchName $SwitchName | Out-Null
} else {
  Write-Host "VM '$VmName' already exists; updating CPU/memory settings."
}

Set-VM -Name $VmName `
  -MemoryStartupBytes $memoryBytes `
  -AutomaticStartAction StartIfRunning `
  -AutomaticStopAction ShutDown `
  -AutomaticCheckpointsEnabled $false |
  Out-Null
# Fixed RAM only — Dynamic Memory can balloon guests under host pressure and OOM cloud-init.
Set-VMMemory -VMName $VmName -DynamicMemoryEnabled:$false -StartupBytes $memoryBytes
Set-VMProcessor -VMName $VmName -Count $CpuCount | Out-Null

# Drop any auto-created checkpoints (Windows client Hyper-V often snapshots on first start).
Get-VMSnapshot -VMName $VmName -ErrorAction SilentlyContinue | Remove-VMSnapshot -IncludeAllChildSnapshots -ErrorAction SilentlyContinue

# Gen2 defaults to Windows Secure Boot template; Ubuntu needs Microsoft UEFI CA.
if ($Generation -eq 2) {
  Set-VMFirmware -VMName $VmName -EnableSecureBoot On -SecureBootTemplate "MicrosoftUEFICertificateAuthority"
}

# Enable guest services for IP reporting via KVP / network adapter.
try {
  Enable-VMIntegrationService -VMName $VmName -Name "Guest Service Interface" -ErrorAction SilentlyContinue
  Enable-VMIntegrationService -VMName $VmName -Name "Key-Value Pair Exchange" -ErrorAction SilentlyContinue
} catch {
  Write-Warning "Could not enable all integration services on $VmName : $_"
}

# Attach NoCloud cidata ISO as DVD (Gen2) for first-boot cloud-init.
if (Test-Path $seedIsoPath) {
  $dvd = Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $dvd) {
    Add-VMDvdDrive -VMName $VmName -Path $seedIsoPath | Out-Null
  } else {
    Set-VMDvdDrive -VMName $VmName -ControllerNumber $dvd.ControllerNumber -ControllerLocation $dvd.ControllerLocation -Path $seedIsoPath | Out-Null
  }
}

if ($StartVm) {
  $state = (Get-VM -Name $VmName).State
  if ($state -ne "Running") {
    Start-VM -Name $VmName | Out-Null
  }
}

Write-Host "VM ready: $VmName"
