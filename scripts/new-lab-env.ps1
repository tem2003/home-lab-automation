<#
.SYNOPSIS
  Add an environment to lab-environments.json with the next free network ranges.

.DESCRIPTION
  Copies default VM memory from the catalog and allocates the next two free
  pod /16s (from 10.244.0.0/16) and service /16s (from 10.96.0.0/16).
  Istio networks are named network-<env>-1 and network-<env>-2.

  Cluster topology stays cluster1 + cluster2. Edit the new entry afterward
  to change memory. Then deploy with deploy-lab.ps1 -TfEnv <name>.

.EXAMPLE
  .\scripts\new-lab-env.ps1 -Name staging
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$Name
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\LabCatalog.ps1")

$entry = Add-LabEnvironment -Name $Name
Write-Host "Added environment '$Name' to $(Get-LabCatalogPath)" -ForegroundColor Green
Write-Host ("  memory: master={0} MB  worker={1} MB" -f $entry.master_memory_mb, $entry.worker_memory_mb)
Write-Host ("  pod:     {0}  {1}" -f $entry.pod_cidrs.cluster1, $entry.pod_cidrs.cluster2)
Write-Host ("  service: {0}  {1}" -f $entry.service_cidrs.cluster1, $entry.service_cidrs.cluster2)
Write-Host ("  istio:   {0}  {1}" -f $entry.istio_networks.cluster1, $entry.istio_networks.cluster2)
Write-Host ""
Write-Host "Deploy: .\scripts\deploy-lab.ps1 -TfEnv $Name"
