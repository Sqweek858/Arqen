$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "CommandAutomationCommon.psm1") -Force

$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "command_spec_validation.txt"
$required = @("COMMAND_ID", "CANONICAL", "CATEGORY", "TOKENS", "AST_NODE", "SEMANTIC", "IR", "BACKEND", "VALID_TEST", "INVALID_TEST")
$seen = @{}
$lines = @()
$failed = $false

foreach ($spec in Get-ArqenCommandSpecs) {
    $id = Get-ArqenSpecValue $spec "COMMAND_ID" $spec.Id
    $errors = @()

    foreach ($key in $required) {
        $value = Get-ArqenSpecValue $spec $key ""
        if ([string]::IsNullOrWhiteSpace($value)) {
            $errors += "missing $key"
        }
    }

    if ($seen.ContainsKey($id)) {
        $errors += "duplicate COMMAND_ID"
    } else {
        $seen[$id] = $true
    }

    foreach ($key in @("VALID_TEST", "INVALID_TEST")) {
        $value = Get-ArqenSpecValue $spec $key ""
        if (-not (Test-ArqenReferencedPath $value)) {
            $errors += "missing referenced $key"
        }
    }

    if ($errors.Count -eq 0) {
        $lines += "PASS|$id"
    } else {
        $failed = $true
        $lines += "FAIL|$id|$($errors -join ', ')"
    }
}

Set-Content -Path $outPath -Value $lines -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
