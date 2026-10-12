<#
.SYNOPSIS
  Tear down Hyper-V lab VMs via Terraform destroy.
#>
param(
  [string]$TfEnv = "dev"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\LabCatalog.ps1")

$catalog = Read-LabCatalog
Assert-LabEnv -Name $TfEnv -Catalog $catalog

$tfDir = Join-Path (Get-LabRepoRoot) "terraform\hyperv-k8s"
if (-not (Test-Path $tfDir)) {
  throw "Terraform directory not found: $tfDir"
}

Push-Location $tfDir
try {
  terraform init -input=false
  if ($LASTEXITCODE -ne 0) { throw "terraform init failed with exit $LASTEXITCODE" }
  Select-LabTerraformWorkspace -Name $TfEnv
  terraform destroy -auto-approve -input=false "-var=env_name=$TfEnv"
  if ($LASTEXITCODE -ne 0) { throw "terraform destroy failed with exit $LASTEXITCODE" }
} finally {
  Pop-Location
}

Write-Host "Destroy complete. Golden Packer VHDX was left intact." -ForegroundColor Green
