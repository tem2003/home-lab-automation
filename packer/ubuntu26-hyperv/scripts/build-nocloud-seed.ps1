<#
  Builds a NoCloud (cidata) ISO for first-boot cloud-config on the Ubuntu cloud image.
  Gen2 Hyper-V has no floppy; attach this as a secondary DVD (secondary_iso_images in Packer).

  Requires: WSL with genisoimage (in WSL: sudo apt update && sudo apt install -y genisoimage)

  Example:
  .\build-nocloud-seed.ps1 -SshPublicKey "ssh-ed25519 AAAA... comment@host"
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$SshPublicKey,

  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$staging = Join-Path $projectRoot "nocloud-staging"
$metaSrc = Join-Path $projectRoot "nocloud\meta-data"
$userSrc = Join-Path $projectRoot "nocloud\user-data"

if ($OutputPath -eq "") {
  $outAbs = Join-Path (Join-Path $projectRoot "artifacts") "nocloud-seed.iso"
}
elseif ([IO.Path]::IsPathRooted($OutputPath)) {
  $outAbs = $OutputPath
}
else {
  $outAbs = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputPath))
}

$outDir = [IO.Path]::GetDirectoryName($outAbs)
if (-not (Test-Path $outDir)) {
  New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

if (-not (Test-Path $metaSrc) -or -not (Test-Path $userSrc)) {
  throw "Missing nocloud\meta-data or nocloud\user-data under $projectRoot"
}

if (Test-Path $staging) {
  Remove-Item -Recurse -Force $staging
}
New-Item -ItemType Directory -Path $staging -Force | Out-Null

Copy-Item -Path $metaSrc -Destination (Join-Path $staging "meta-data")
$userText = [IO.File]::ReadAllText($userSrc)
if ($userText -notmatch "__SSH_PUBLIC_KEY__") {
  throw "nocloud\user-data must contain placeholder __SSH_PUBLIC_KEY__"
}
$userText = $userText.Replace("__SSH_PUBLIC_KEY__", $SshPublicKey.Trim())
[IO.File]::WriteAllText((Join-Path $staging "user-data"), $userText)

$wsl = Get-Command wsl -ErrorAction SilentlyContinue
if (-not $wsl) {
  throw "WSL (wsl.exe) is required. After installing WSL, in Ubuntu: sudo apt install -y genisoimage"
}

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

$stagingWsl = ConvertTo-WslPath $staging
$outWsl = ConvertTo-WslPath $outAbs

# Single-line bash avoids CRLF issues when piping multiline scripts into WSL.
# genisoimage (preferred) and mkisofs (cdrtools) are typically installed in WSL: sudo apt install -y genisoimage
$bashLine = "cd '$stagingWsl' && ( command -v genisoimage >/dev/null 2>&1 && genisoimage -o '$outWsl' -V cidata -J -R user-data meta-data ) || ( command -v mkisofs >/dev/null 2>&1 && mkisofs -o '$outWsl' -V cidata -J -R user-data meta-data ) || ( echo 'Missing genisoimage. In WSL: sudo apt update && sudo apt install -y genisoimage' >&2; exit 1 )"
& wsl.exe bash -lc $bashLine
if ($LASTEXITCODE -ne 0) {
  throw "genisoimage/mkisofs failed with exit $LASTEXITCODE"
}

Write-Host "Wrote $outAbs"
Write-Host "Use nocloud_iso_relpath = `"artifacts/nocloud-seed.iso`" in ubuntu26.auto.pkrvars.hcl (default)."
