$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "CommandAutomationCommon.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "wrapper_cache_contract_validation.txt"
$wrapperPath = Join-Path $root "Tools\arqc_m10jk.ps1"
$wrapper = Get-Content $wrapperPath -Raw
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) { $lines.Add("PASS|$Name|$Detail") | Out-Null } else { $script:failed = $true; $lines.Add("FAIL|$Name|$Detail") | Out-Null }
}

Add-Result "cache_schema_version" ($wrapper.Contains('$cacheSchemaVersion')) "cache schema participates in state"
Add-Result "cache_key_source_hash" ($wrapper.Contains('SOURCE_HASH|')) "source hash included"
Add-Result "cache_key_compiler_version" ($wrapper.Contains('COMPILER_VERSION|')) "compiler version included"
Add-Result "cache_key_driver_hash" ($wrapper.Contains('DRIVER_HASH|')) "wrapper hash included"
Add-Result "cache_key_m10g_hash" ($wrapper.Contains('M10G_HASH|')) "compiled driver hash included"
Add-Result "cache_key_backend_helper_hash" ($wrapper.Contains('BACKEND_HELPER_HASH|')) "backend helper hash included"
Add-Result "cache_key_backend_config_hash" ($wrapper.Contains('BACKEND_CONFIG_HASH|')) "backend config hash included"
Add-Result "cache_key_command_specs_hash" ($wrapper.Contains('COMMAND_SPECS_HASH|')) "command specs hash included"
Add-Result "cache_key_target" ($wrapper.Contains('TARGET|$cacheTarget')) "target included"
Add-Result "cache_artifact_validation" ($wrapper.Contains('Test-ArqPeArtifact $cacheArtifactPath') -and $wrapper.Contains('Test-ArqPeArtifact $artifactPath')) "cache hit and restored artifact are validated"
Add-Result "cache_backend_only_bypass" ($wrapper.Contains('$backendOnly') -and $wrapper.Contains('backend-only')) "backend-only bypasses normal cache"
Add-Result "cache_rebuild_reason" ($wrapper.Contains('$rebuild') -and $wrapper.Contains('rebuild')) "rebuild invalidates cache"
Add-Result "cache_record_status_success" ($wrapper.Contains('STATUS|success') -and $wrapper.Contains('CACHE_KEY|$cacheKey')) "cache record tracks key and success"
Add-Result "lint_window_statements" ($wrapper.Contains('"run"') -and $wrapper.Contains('"when"') -and $wrapper.Contains('"close"')) "wrapper lint knows window statements"

Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
