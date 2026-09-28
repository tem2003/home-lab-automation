param(
  [string]$CloudImageUrl = "https://cloud-images.ubuntu.com/releases/resolute/release/ubuntu-26.04-server-cloudimg-amd64.img",
  [string]$WorkDir = "..\artifacts",
  [string]$OutputVhdxName = "ubuntu-26.04-server-cloudimg-amd64.vhdx",
  [string]$ConvertScratchDir = (Join-Path $env:TEMP "HyperVTemp"),
  # Virtual capacity after convert. Cloud images are ~3.5GiB; K8s packages need headroom.
  [int]$OutputSizeGb = 40,
  [switch]$ForceDownload,
  # Prefer dynamic VHDX (small on disk). Use -Fixed only if Hyper-V rejects dynamic.
  [switch]$Fixed
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$workDirAbs = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot $WorkDir))
if (-not (Test-Path $workDirAbs)) {
  New-Item -ItemType Directory -Path $workDirAbs | Out-Null
}

$qcow2Path = Join-Path $workDirAbs "source-cloudimg.qcow2"
$tempVhdxPath = Join-Path $ConvertScratchDir "source-cloudimg.dynamic.vhdx"
$vhdxPath = Join-Path $workDirAbs $OutputVhdxName
$targetBytes = [uint64]$OutputSizeGb * 1GB

if (-not (Test-Path $ConvertScratchDir)) {
  New-Item -ItemType Directory -Path $ConvertScratchDir -Force | Out-Null
}

Write-Host "Downloading cloud image to $qcow2Path"
if ($ForceDownload -or -not (Test-Path $qcow2Path)) {
  Invoke-WebRequest -Uri $CloudImageUrl -OutFile $qcow2Path
} else {
  Write-Host "Cloud image already exists, reusing: $qcow2Path"
}

$qemuImg = Get-Command qemu-img -ErrorAction SilentlyContinue
if (-not $qemuImg) {
  throw "qemu-img not found in PATH. Install qemu-img, then rerun this script."
}

# Resize QCOW2 first — qemu-img cannot resize VHDX on many Windows builds.
Write-Host "Resizing QCOW2 virtual size to ${OutputSizeGb} GiB (qemu-img supports qcow2 resize)..."
& $qemuImg.Source resize $qcow2Path "${OutputSizeGb}G"
if ($LASTEXITCODE -ne 0) {
  throw "qemu-img resize (qcow2) failed with exit code $LASTEXITCODE"
}

if (Test-Path $vhdxPath) {
  Remove-Item -Path $vhdxPath -Force
}

$subformat = if ($Fixed) { "fixed" } else { "dynamic" }
Write-Host "Converting QCOW2 to $subformat VHDX with qemu-img: $vhdxPath"
& $qemuImg.Source convert -f qcow2 -O vhdx -o "subformat=$subformat" $qcow2Path $vhdxPath
if ($LASTEXITCODE -ne 0) {
  Write-Warning "Direct conversion failed; trying Convert-VHD fallback."

  & $qemuImg.Source convert -f qcow2 -O vhdx $qcow2Path $tempVhdxPath
  if ($LASTEXITCODE -ne 0) {
    throw "qemu-img dynamic conversion failed with exit code $LASTEXITCODE."
  }

  $compact = Get-Command compact -ErrorAction SilentlyContinue
  if ($compact) {
    & $compact.Source /U /Q $tempVhdxPath | Out-Null
  }
  $cipher = Get-Command cipher -ErrorAction SilentlyContinue
  if ($cipher) {
    & $cipher.Source /D $tempVhdxPath | Out-Null
  }
  $fsutil = Get-Command fsutil -ErrorAction SilentlyContinue
  if ($fsutil) {
    & $fsutil.Source sparse setflag $tempVhdxPath 0 | Out-Null
  }

  $convertVhd = Get-Command Convert-VHD -ErrorAction SilentlyContinue
  if (-not $convertVhd) {
    throw "Convert-VHD not found. Enable Hyper-V PowerShell module, then rerun this script."
  }

  $vhdType = if ($Fixed) { "Fixed" } else { "Dynamic" }
  Write-Host "Converting to $vhdType VHDX (fallback): $vhdxPath"
  Convert-VHD -Path $tempVhdxPath -DestinationPath $vhdxPath -VHDType $vhdType

  if (Test-Path $tempVhdxPath) {
    Remove-Item -Path $tempVhdxPath -Force
  }
}

# Verify virtual size; if convert somehow kept a smaller size, grow with Hyper-V Resize-VHD.
$infoText = & $qemuImg.Source info $vhdxPath | Out-String
Write-Host $infoText
if ($infoText -notmatch "virtual size:.*?(\d+(?:\.\d+)?)\s*([GMK]i?B)") {
  Write-Warning "Could not parse virtual size from qemu-img info; attempting Resize-VHD to be safe."
  $needResize = $true
} else {
  $num = [double]$Matches[1]
  $unit = $Matches[2]
  $bytes = switch -Regex ($unit) {
    '^G' { [uint64]($num * 1GB) }
    '^M' { [uint64]($num * 1MB) }
    '^K' { [uint64]($num * 1KB) }
    default { [uint64]$num }
  }
  $needResize = $bytes -lt ($targetBytes - 1MB)
}

if ($needResize) {
  Write-Host "VHDX virtual size still small; growing with Resize-VHD to ${OutputSizeGb} GiB..."
  $resize = Get-Command Resize-VHD -ErrorAction SilentlyContinue
  if (-not $resize) {
    throw "Resize-VHD not available. Run in elevated PowerShell with Hyper-V module, or ensure qcow2 resize succeeded before convert."
  }
  Resize-VHD -Path $vhdxPath -SizeBytes $targetBytes
  & $qemuImg.Source info $vhdxPath
}

$vhdxUri = "file:///" + ($vhdxPath -replace "\\", "/")
Write-Host ""
Write-Host "Done. Set this in ubuntu26.auto.pkrvars.hcl:"
Write-Host "cloud_image_url = `"$vhdxUri`""
Write-Host "Virtual size target: ${OutputSizeGb} GiB ($subformat)."
