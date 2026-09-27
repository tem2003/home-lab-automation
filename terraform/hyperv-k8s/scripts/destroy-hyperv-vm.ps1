param(
  [Parameter(Mandatory = $true)]
  [string]$VmName,

  [Parameter(Mandatory = $true)]
  [string]$VmRootPath
)

$ErrorActionPreference = "Stop"

$vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if ($vm) {
  if ($vm.State -eq "Running") {
    Stop-VM -Name $VmName -TurnOff -Force -Confirm:$false | Out-Null
  }
  Remove-VM -Name $VmName -Force -Confirm:$false | Out-Null
}

$vmPath = Join-Path $VmRootPath $VmName
if (Test-Path $vmPath) {
  Remove-Item -Path $vmPath -Recurse -Force
}

Write-Host "VM removed (if existed): $VmName"
