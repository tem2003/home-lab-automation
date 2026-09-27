<#
.SYNOPSIS
  Power on or off all Hyper-V lab VMs for an environment (dev / stable).

.PARAMETER Env
  Environment name prefix used in VM names (default: dev).

.PARAMETER Action
  Off = Stop-VM (graceful, then force if needed)
  On  = Start-VM

.PARAMETER Force
  When stopping, use TurnOff instead of a graceful Shutdown.

.EXAMPLE
  .\scripts\set-lab-vms.ps1 -Env dev -Action Off
  .\scripts\set-lab-vms.ps1 -Env stable -Action On
  .\scripts\set-lab-vms.ps1 -Env dev -Action Off -Force
#>
param(
  [ValidateSet("dev", "stable")]
  [string]$Env = "dev",

  [Parameter(Mandatory = $true)]
  [ValidateSet("On", "Off")]
  [string]$Action,

  [switch]$Force
)

$ErrorActionPreference = "Stop"

Import-Module Hyper-V -ErrorAction Stop

$prefix = "$Env-"
$vms = @(Get-VM | Where-Object { $_.Name -like "$prefix*" } | Sort-Object Name)

if ($vms.Count -eq 0) {
  Write-Warning "No Hyper-V VMs found with name prefix '$prefix'."
  exit 0
}

Write-Host "Env=$Env  Action=$Action  VMs=$($vms.Count)" -ForegroundColor Cyan
$vms | ForEach-Object { Write-Host ("  {0,-32} {1}" -f $_.Name, $_.State) }

foreach ($vm in $vms) {
  $name = $vm.Name
  $state = $vm.State

  if ($Action -eq "Off") {
    if ($state -eq "Off") {
      Write-Host "Already off: $name" -ForegroundColor DarkGray
      continue
    }
    if ($Force) {
      Write-Host "Turning off (force): $name" -ForegroundColor Yellow
      Stop-VM -Name $name -TurnOff -Force
    } else {
      Write-Host "Shutting down: $name" -ForegroundColor Yellow
      try {
        Stop-VM -Name $name -Force -ErrorAction Stop
      } catch {
        Write-Warning "Graceful stop failed for $name; turning off. $_"
        Stop-VM -Name $name -TurnOff -Force
      }
    }
  } else {
    if ($state -eq "Running") {
      Write-Host "Already running: $name" -ForegroundColor DarkGray
      continue
    }
    Write-Host "Starting: $name" -ForegroundColor Green
    Start-VM -Name $name
  }
}

Write-Host ""
Write-Host "Result:" -ForegroundColor Cyan
Get-VM | Where-Object { $_.Name -like "$prefix*" } | Sort-Object Name |
  ForEach-Object { Write-Host ("  {0,-32} {1}" -f $_.Name, $_.State) }
