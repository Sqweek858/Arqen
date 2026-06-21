$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "Common\ArqenTooling.psm1") -Force

$root = Get-ArqenRepoRoot -StartPath $PSScriptRoot
$generated = Join-Path $root "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "wrapper_cache_contract_validation.txt"
$wrapperPath = Join-Path $root "Tools\arqc.ps1"
$driverPath = Join-Path $root "Tools\M10GDriver\Program.cs"
$wrapper = Get-Content $wrapperPath -Raw
$driver = Get-Content $driverPath -Raw
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) { $lines.Add("PASS|$Name|$Detail") | Out-Null } else { $script:failed = $true; $lines.Add("FAIL|$Name|$Detail") | Out-Null }
}

Add-Result "active_wrapper_exists" (Test-Path $wrapperPath) "Tools\arqc.ps1"
Add-Result "active_driver_source_exists" (Test-Path $driverPath) "Tools\M10GDriver\Program.cs"
Add-Result "wrapper_supports_build_driver" ($wrapper.Contains("BuildDriver") -and $wrapper.Contains("dotnet publish")) "active wrapper can rebuild driver"
Add-Result "wrapper_forwards_to_m10g" ($wrapper.Contains("arqc_m10g.exe") -and $wrapper.Contains("@RemainingArgs")) "active wrapper forwards remaining args"
Add-Result "wrapper_requires_driver" ($wrapper.Contains("Driver not found")) "clear missing driver error"
Add-Result "driver_supports_backend_only" ($driver.Contains("--backend-only")) "backend-only still supported by active driver"
Add-Result "driver_supports_output_arg" ($driver.Contains('"-o"')) "-o output still supported by active driver"
Add-Result "legacy_wrapper_removed" (-not (Test-Path (Join-Path (Join-Path $root "Tools\Legacy") "arqc_m10jk.ps1"))) "legacy bootstrap wrapper is not active tooling"

Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
