<#
.SYNOPSIS
  Repair Hyper-V switch used by Packer/Terraform so the host has a real IP.

Packer fails with "Error getting host adapter ip address: No ip address" when
vEthernet (hyper-v-switch) is Disconnected or only has a 169.254.x.x APIPA address.

This script rebinds the External switch to a working physical NIC (default: Ethernet 4).

Run from an elevated PowerShell (Administrator).
#>
param(
  [string]$SwitchName = "hyper-v-switch",
  [string]$NetAdapterName = "Ethernet 4"
)

$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
  IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  throw "Run this script as Administrator (elevated PowerShell)."
}

$nic = Get-NetAdapter -Name $NetAdapterName -ErrorAction SilentlyContinue
if (-not $nic) {
  Write-Host "Available adapters:" -ForegroundColor Yellow
  Get-NetAdapter | Format-Table Name, Status, InterfaceDescription -AutoSize
  throw "NetAdapter '$NetAdapterName' not found. Pass -NetAdapterName with an Up adapter that has a real IPv4."
}
if ($nic.Status -ne "Up") {
  throw "NetAdapter '$NetAdapterName' status is '$($nic.Status)'. Choose an Up adapter."
}

$ip = Get-NetIPAddress -InterfaceAlias $NetAdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -notlike "169.254.*" } |
  Select-Object -First 1
if (-not $ip) {
  throw "NetAdapter '$NetAdapterName' has no usable IPv4 (non-APIPA). Fix host networking first."
}

$sw = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $sw) {
  Write-Host "Creating External switch '$SwitchName' on '$NetAdapterName'..." -ForegroundColor Yellow
  New-VMSwitch -Name $SwitchName -NetAdapterName $NetAdapterName -AllowManagementOS $true | Out-Null
} else {
  Write-Host "Rebinding switch '$SwitchName' to '$NetAdapterName' (host IP $($ip.IPAddress))..." -ForegroundColor Yellow
  # External switches: set the physical NIC. If currently Internal/Private, recreate as External.
  if ($sw.SwitchType -ne "External") {
    Write-Host "Switch is $($sw.SwitchType); recreating as External..." -ForegroundColor Yellow
    Remove-VMSwitch -Name $SwitchName -Force
    New-VMSwitch -Name $SwitchName -NetAdapterName $NetAdapterName -AllowManagementOS $true | Out-Null
  } else {
    Set-VMSwitch -Name $SwitchName -NetAdapterName $NetAdapterName -AllowManagementOS $true
  }
}

Start-Sleep -Seconds 3

Write-Host "`nSwitch:" -ForegroundColor Cyan
Get-VMSwitch -Name $SwitchName | Format-Table Name, SwitchType, NetAdapterInterfaceDescription -AutoSize

Write-Host "Host vEthernet IP:" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.InterfaceAlias -like "vEthernet ($SwitchName)*" -or $_.InterfaceAlias -eq $NetAdapterName } |
  Format-Table InterfaceAlias, IPAddress, PrefixLength -AutoSize

$veth = Get-NetAdapter -Name "vEthernet ($SwitchName)" -ErrorAction SilentlyContinue
if ($veth -and $veth.Status -eq "Up") {
  Write-Host "OK: vEthernet ($SwitchName) is Up. Re-run: .\deploy-lab.ps1" -ForegroundColor Green
} else {
  # On External + AllowManagementOS, host may share the physical NIC IP (no separate vEthernet in some setups)
  Write-Host "OK: External switch bound to $NetAdapterName ($($ip.IPAddress)). Re-run: .\deploy-lab.ps1" -ForegroundColor Green
}
