$ErrorActionPreference = "Stop"

function Find-ArqenRepoRoot {
    param([string]$StartPath)

    $current = [IO.DirectoryInfo]::new($StartPath)
    while ($null -ne $current) {
        if ((Test-Path (Join-Path $current.FullName "Docs\MILESTONES.md")) -and
            (Test-Path (Join-Path $current.FullName "Tools\M10GDriver")) -and
            (Test-Path (Join-Path $current.FullName "Tests\CommandTests"))) {
            return $current.FullName
        }
        $current = $current.Parent
    }

    throw "Unable to locate Arqen repository root from $StartPath"
}

$RepoRoot = Find-ArqenRepoRoot $PSScriptRoot
Import-Module (Join-Path $RepoRoot "Tools\Common\CommandAutomationCommon.psm1") -Force

$root = $RepoRoot
$generated = Join-Path $root "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "runtime_action_catalog_validation.txt"
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) {
        $lines.Add("PASS|$Name|$Detail") | Out-Null
    } else {
        $script:failed = $true
        $lines.Add("FAIL|$Name|$Detail") | Out-Null
    }
}

function Read-Capabilities {
    param([string]$Path)
    $map = @{}
    foreach ($raw in Get-Content $Path) {
        $line = $raw.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        $parts = $line.Split([char]'|', 2)
        if ($parts.Length -eq 2) { $map[$parts[0]] = $parts[1] }
    }
    return $map
}

$catalogPath = Join-Path $root "Docs\Reference\Runtime\RUNTIME_ACTION_CATALOG.txt"
$backendDriverPath = Join-Path $root "Tools\M10GDriver\Backend\BackendDriver.cs"
$peWriterPath = Join-Path $root "Tools\M10GDriver\Backend\PeWriter.cs"
$capPath = Join-Path $root "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt"
$registryPath = Join-Path $root "Build\Generated\runtime_action_registry.txt"
$registryGeneratorPath = Join-Path $root "Tools\Generate\generate_runtime_action_registry.ps1"
$registryGeneratorLog = Join-Path $generated "runtime_action_registry.validation_generate.log"

Add-Result "catalog_file_exists" (Test-Path $catalogPath) "Docs\Reference\Runtime\RUNTIME_ACTION_CATALOG.txt"
Add-Result "backend_driver_exists" (Test-Path $backendDriverPath) "BackendDriver.cs"
Add-Result "pewriter_exists" (Test-Path $peWriterPath) "PeWriter.cs"
Add-Result "capabilities_exists" (Test-Path $capPath) "capabilities_v0.txt"

if (Test-Path $registryGeneratorPath) {
    Push-Location $root
    try {
        & $registryGeneratorPath *> $registryGeneratorLog
        $registryGeneratorExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally {
        Pop-Location
    }
    Add-Result "runtime_registry_generated" ($registryGeneratorExit -eq 0) "exit=$registryGeneratorExit log=Build\Generated\runtime_action_registry.validation_generate.log"
} else {
    Add-Result "runtime_registry_generator_exists" $false "Tools\Generate\generate_runtime_action_registry.ps1"
}

Add-Result "runtime_registry_exists" (Test-Path $registryPath) "Build\Generated\runtime_action_registry.txt"

if (-not (Test-Path $catalogPath)) {
    Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8
    $lines | ForEach-Object { Write-Host $_ }
    exit 1
}

$catalog = @{}
foreach ($raw in Get-Content $catalogPath) {
    $line = $raw.Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
    $parts = $line.Split('|')
    if ($parts.Count -lt 4 -or $parts[0] -ne 'ACTION') {
        Add-Result "catalog_line_valid" $false $line
        continue
    }
    $name = $parts[1]
    $route = $parts[2]
    $status = $parts[3]
    if ($catalog.ContainsKey($name)) {
        Add-Result "catalog_duplicate_$name" $false "duplicate action"
    }
    $catalog[$name] = @{ Route = $route; Status = $status; Raw = $line }
}

$backendDriver = if (Test-Path $backendDriverPath) { Get-Content $backendDriverPath -Raw } else { '' }
$peWriter = if (Test-Path $peWriterPath) { Get-Content $peWriterPath -Raw } else { '' }
$registry = if (Test-Path $registryPath) { Get-Content $registryPath -Raw } else { '' }
$cap = if (Test-Path $capPath) { Read-Capabilities $capPath } else { @{} }

foreach ($name in ($catalog.Keys | Sort-Object)) {
    $entry = $catalog[$name]
    $route = $entry['Route']
    $status = $entry['Status']
    Add-Result "catalog_backend_$name" ($backendDriver.Contains('"' + $name + '"')) "SupportedBackendActions should contain $name"
    Add-Result "catalog_capability_$name" ($cap.ContainsKey($name) -and $cap[$name] -eq $status) "capability=$status"
    Add-Result "catalog_registry_$name" ($registry.Contains("ACTION|$name|capability=$status")) "runtime registry should contain $name"
    if ($route -eq 'fileio') {
        Add-Result "catalog_pewriter_route_$name" ($peWriter.Contains('"' + $name + '"')) "HasFileIoActions should route $name"
    }
}

foreach ($name in ($cap.Keys | Sort-Object)) {
    if ($name.StartsWith('runtime_', [System.StringComparison]::Ordinal) -and $cap[$name] -eq 'supported') {
        Add-Result "catalog_contains_supported_$name" ($catalog.ContainsKey($name)) "supported runtime capability must be cataloged"
    }
}

Add-Result "catalog_runtime_action_count_min" ($catalog.Count -ge 18) "count=$($catalog.Count)"

Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
