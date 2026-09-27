<#
.SYNOPSIS
  Tear down Hyper-V lab VMs via Terraform destroy.
#>
param(
  [string]$TfEnv = "dev"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tfDir = Join-Path $root "terraform\hyperv-k8s\envs\$TfEnv"

if (-not (Test-Path $tfDir)) {
  throw "Terraform env directory not found: $tfDir"
}

Push-Location $tfDir
try {
  terraform destroy -auto-approve -input=false
  if ($LASTEXITCODE -ne 0) { throw "terraform destroy failed with exit $LASTEXITCODE" }
} finally {
  Pop-Location
}

Write-Host "Destroy complete. Golden Packer VHDX was left intact." -ForegroundColor Green
