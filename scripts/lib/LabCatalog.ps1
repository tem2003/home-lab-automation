# Shared loader for lab-environments.json.
# Dot-source this file; it does not execute on load.

$script:LabEnvNamePattern = '^[a-z][a-z0-9-]{0,20}$'
$script:LabClusterNames = @('cluster1', 'cluster2')
$script:LabCidrPattern = '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$'

function Select-LabTerraformWorkspace {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [switch]$Create
  )

  $listing = & terraform workspace list
  if ($LASTEXITCODE -ne 0) {
    throw "terraform workspace list failed with exit $LASTEXITCODE"
  }
  $names = @($listing | ForEach-Object { $_.Trim().TrimStart('*').Trim() } | Where-Object { $_ })
  if ($names -contains $Name) {
    & terraform workspace select $Name
    if ($LASTEXITCODE -ne 0) {
      throw "terraform workspace select $Name failed with exit $LASTEXITCODE"
    }
    return
  }
  if (-not $Create) {
    throw "Terraform workspace '$Name' does not exist."
  }
  & terraform workspace new $Name
  if ($LASTEXITCODE -ne 0) {
    throw "terraform workspace new $Name failed with exit $LASTEXITCODE"
  }
}

function Get-LabRepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Get-LabCatalogPath {
  return (Join-Path (Get-LabRepoRoot) "lab-environments.json")
}

function Read-LabCatalog {
  param([string]$Path = (Get-LabCatalogPath))

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Lab catalog not found: $Path"
  }
  return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Get-LabEnvNames {
  param($Catalog)
  if ($null -eq $Catalog.environments) {
    return @()
  }
  return @($Catalog.environments.PSObject.Properties.Name)
}

function Assert-LabEnvName {
  param([Parameter(Mandatory = $true)][string]$Name)

  if ($Name -notmatch $script:LabEnvNamePattern) {
    throw "Environment name '$Name' must match $($script:LabEnvNamePattern) (VM name prefix and inventory file name)."
  }
}

function Assert-ExactClusterSet {
  param($Object, [string]$Label)

  if ($null -eq $Object) {
    throw "$Label is missing. Expected exactly: $($script:LabClusterNames -join ', ')."
  }
  $names = @($Object.PSObject.Properties.Name)
  $missing = @($script:LabClusterNames | Where-Object { $names -notcontains $_ })
  $extra = @($names | Where-Object { $script:LabClusterNames -notcontains $_ })
  if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
    throw "$Label must define exactly $($script:LabClusterNames -join ', ')."
  }
}

function Assert-PositiveInt {
  param($Value, [string]$Label, [int]$Minimum = 1)

  if ($Value -isnot [int] -and $Value -isnot [long]) {
    throw "$Label must be an integer."
  }
  if ([int]$Value -lt $Minimum) {
    throw "$Label must be >= $Minimum."
  }
}

function Assert-LabCatalog {
  param($Catalog)

  if ($null -eq $Catalog.defaults) {
    throw "Catalog is missing defaults."
  }
  $defaults = $Catalog.defaults
  if ([string]::IsNullOrWhiteSpace($defaults.hyperv_switch_name)) {
    throw "defaults.hyperv_switch_name is required."
  }
  Assert-PositiveInt $defaults.master_cpu_count "defaults.master_cpu_count"
  Assert-PositiveInt $defaults.worker_cpu_count "defaults.worker_cpu_count"
  Assert-PositiveInt $defaults.master_memory_mb "defaults.master_memory_mb"
  Assert-PositiveInt $defaults.worker_memory_mb "defaults.worker_memory_mb"
  Assert-ExactClusterSet $defaults.clusters "defaults.clusters"
  foreach ($cluster in $script:LabClusterNames) {
    $cfg = $defaults.clusters.$cluster
    Assert-PositiveInt $cfg.master_count "defaults.clusters.$cluster.master_count"
    Assert-PositiveInt $cfg.worker_count "defaults.clusters.$cluster.worker_count" -Minimum 0
  }

  $envNames = @(Get-LabEnvNames $Catalog)
  if ($envNames.Count -eq 0) {
    throw "Catalog environments is empty."
  }

  $podSeen = @{}
  $svcSeen = @{}
  $netSeen = @{}
  foreach ($envName in $envNames) {
    Assert-LabEnvName $envName
    $env = $Catalog.environments.$envName
    Assert-PositiveInt $env.master_memory_mb "$envName.master_memory_mb"
    Assert-PositiveInt $env.worker_memory_mb "$envName.worker_memory_mb"
    foreach ($mapName in @('pod_cidrs', 'service_cidrs', 'istio_networks')) {
      Assert-ExactClusterSet $env.$mapName "$envName.$mapName"
    }
    if ($null -ne $env.clusters) {
      Assert-ExactClusterSet $env.clusters "$envName.clusters"
    }

    foreach ($cluster in $script:LabClusterNames) {
      $pod = [string]$env.pod_cidrs.$cluster
      $svc = [string]$env.service_cidrs.$cluster
      $net = [string]$env.istio_networks.$cluster
      if ($pod -notmatch $script:LabCidrPattern) {
        throw "$envName pod CIDR '$pod' ($cluster) is not an IPv4 CIDR."
      }
      if ($svc -notmatch $script:LabCidrPattern) {
        throw "$envName service CIDR '$svc' ($cluster) is not an IPv4 CIDR."
      }
      if ([string]::IsNullOrWhiteSpace($net)) {
        throw "$envName Istio network for $cluster is empty."
      }
      $where = "$envName/$cluster"
      if ($podSeen.ContainsKey($pod)) {
        throw "Pod CIDR $pod is used by both $($podSeen[$pod]) and $where."
      }
      if ($svcSeen.ContainsKey($svc)) {
        throw "Service CIDR $svc is used by both $($svcSeen[$svc]) and $where."
      }
      if ($netSeen.ContainsKey($net)) {
        throw "Istio network '$net' is used by both $($netSeen[$net]) and $where."
      }
      $podSeen[$pod] = $where
      $svcSeen[$svc] = $where
      $netSeen[$net] = $where
    }
  }
}

function Assert-LabEnv {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    $Catalog
  )

  Assert-LabEnvName $Name
  $names = @(Get-LabEnvNames $Catalog)
  if ($names -notcontains $Name) {
    throw "Environment '$Name' is not in lab-environments.json. Defined: $($names -join ', '). Add it with scripts/new-lab-env.ps1."
  }
}

function Get-UsedSecondOctets {
  param([string[]]$Cidrs)

  $used = @()
  foreach ($cidr in $Cidrs) {
    if ($cidr -match '^10\.(\d+)\.\d+\.\d+/\d+$') {
      $used += [int]$Matches[1]
    }
  }
  return $used
}

function Get-NextFreeOctets {
  param(
    [int[]]$Used,
    [int]$Start,
    [int]$Count
  )

  $found = @()
  $n = $Start
  while ($found.Count -lt $Count) {
    if ($Used -notcontains $n) {
      $found += $n
    }
    $n++
    if ($n -gt 255) {
      throw "No free 10.x.0.0/16 ranges left starting at second octet $Start."
    }
  }
  return $found
}

function ConvertTo-LabJson {
  param($Value, [int]$Indent = 0)

  $pad = "  " * $Indent
  $padIn = "  " * ($Indent + 1)
  if ($null -eq $Value) { return "null" }
  if ($Value -is [bool]) {
    if ($Value) { return "true" }
    return "false"
  }
  if ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal]) {
    return ([string][int64]$Value)
  }

  $pairs = @()
  if ($Value -is [string]) {
    $escaped = ($Value -replace '\\', '\\' -replace '"', '\"')
    return ('"' + $escaped + '"')
  }
  if ($Value -is [System.Collections.IDictionary]) {
    foreach ($key in @($Value.Keys)) {
      $pairs += ,@($key, $Value[$key])
    }
  } elseif ($Value -is [System.Management.Automation.PSCustomObject]) {
    foreach ($prop in $Value.PSObject.Properties) {
      $pairs += ,@($prop.Name, $prop.Value)
    }
  } else {
    throw "Unsupported catalog value type $($Value.GetType().FullName)."
  }

  if ($pairs.Count -eq 0) { return "{}" }
  $lines = @("{")
  for ($i = 0; $i -lt $pairs.Count; $i++) {
    $comma = ""
    if ($i -lt ($pairs.Count - 1)) { $comma = "," }
    $rendered = ConvertTo-LabJson -Value $pairs[$i][1] -Indent ($Indent + 1)
    $lines += ('{0}"{1}": {2}{3}' -f $padIn, $pairs[$i][0], $rendered, $comma)
  }
  $lines += ($pad + "}")
  return ($lines -join "`n")
}

function ConvertTo-LabOrdered {
  param($Value)

  if ($null -eq $Value) {
    return $null
  }
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $ordered = [ordered]@{}
    foreach ($prop in $Value.PSObject.Properties) {
      $ordered[$prop.Name] = ConvertTo-LabOrdered $prop.Value
    }
    return $ordered
  }
  if ($Value -is [System.Collections.IDictionary]) {
    $ordered = [ordered]@{}
    foreach ($key in $Value.Keys) {
      $ordered[$key] = ConvertTo-LabOrdered $Value[$key]
    }
    return $ordered
  }
  return $Value
}

function Add-LabEnvironment {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Path = (Get-LabCatalogPath)
  )

  Assert-LabEnvName $Name
  $catalog = Read-LabCatalog -Path $Path
  Assert-LabCatalog $catalog

  $existing = @(Get-LabEnvNames $catalog)
  if ($existing -contains $Name) {
    throw "Environment '$Name' already exists in $Path."
  }

  $podCidrs = @()
  $svcCidrs = @()
  $nets = @()
  foreach ($envName in $existing) {
    $env = $catalog.environments.$envName
    foreach ($cluster in $script:LabClusterNames) {
      $podCidrs += [string]$env.pod_cidrs.$cluster
      $svcCidrs += [string]$env.service_cidrs.$cluster
      $nets += [string]$env.istio_networks.$cluster
    }
  }

  $podOctets = @(Get-NextFreeOctets -Used @(Get-UsedSecondOctets $podCidrs) -Start 244 -Count 2)
  $svcOctets = @(Get-NextFreeOctets -Used @(Get-UsedSecondOctets $svcCidrs) -Start 96 -Count 2)
  $net1 = "network-$Name-1"
  $net2 = "network-$Name-2"
  if ($nets -contains $net1 -or $nets -contains $net2 -or $net1 -eq $net2) {
    throw "Istio network names '$net1' and '$net2' are not unique."
  }

  $entry = [ordered]@{
    master_memory_mb = [int]$catalog.defaults.master_memory_mb
    worker_memory_mb = [int]$catalog.defaults.worker_memory_mb
    pod_cidrs        = [ordered]@{
      cluster1 = "10.$($podOctets[0]).0.0/16"
      cluster2 = "10.$($podOctets[1]).0.0/16"
    }
    service_cidrs    = [ordered]@{
      cluster1 = "10.$($svcOctets[0]).0.0/16"
      cluster2 = "10.$($svcOctets[1]).0.0/16"
    }
    istio_networks   = [ordered]@{
      cluster1 = $net1
      cluster2 = $net2
    }
  }

  $ordered = ConvertTo-LabOrdered $catalog
  $ordered.environments[$Name] = $entry
  $json = ConvertTo-LabJson $ordered
  Assert-LabCatalog (ConvertFrom-Json $json)

  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, $json.TrimEnd() + "`n", $utf8)
  return $entry
}
