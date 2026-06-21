param(
    [switch]$BuildDriver,
    [switch]$StopOnFail,
    [switch]$IncludeBuildScripts,
    [switch]$IncludeScaffoldScripts,
    [switch]$IncludeHistoricalValidators,
    [switch]$IncludeSpecCoverageValidators,
    [switch]$IncludeExpectedIr,
    [switch]$SkipValidators,
    [switch]$SkipSamples,
    [switch]$SkipBackendFixtures
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "Common\ArqenTooling.psm1") -Force

$RepoRoot = Get-ArqenRepoRoot -StartPath $PSScriptRoot
$LogDir = Join-Path $RepoRoot "Build\Logs"
$GeneratedDir = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $LogDir,$GeneratedDir | Out-Null

$script:Total = 0
$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0
$script:Lines = New-Object System.Collections.Generic.List[string]

function Add-Result {
    param([string]$Status,[string]$Name,[string]$Detail = "")
    $script:Total += 1
    if ($Status -eq "PASS") { $script:Passed += 1 }
    elseif ($Status -eq "FAIL") { $script:Failed += 1 }
    elseif ($Status -eq "SKIP") { $script:Skipped += 1 }

    $line = if ([string]::IsNullOrWhiteSpace($Detail)) { "$Status|$Name" } else { "$Status|$Name|$Detail" }
    $script:Lines.Add($line) | Out-Null
    Write-Host $line
    if ($Status -eq "FAIL" -and $StopOnFail) { Write-SummaryAndExit 1 }
}

function Convert-ToSafeStepName {
    param([string]$Name)
    $safe = ($Name -replace '^[A-Za-z]+\|','') -replace '[^A-Za-z0-9]+','_'
    return $safe.Trim('_')
}

function Add-ImportedResult {
    param([string]$Status,[string]$Prefix,[string]$Name,[string]$Detail = "")
    Add-Result $Status ("$Prefix" + (Convert-ToSafeStepName $Name)) $Detail
}

function Import-TestSliceLog {
    param([string]$Path,[string]$Prefix)
    if (-not (Test-Path $Path)) {
        Add-Result "FAIL" "${Prefix}log_missing" $Path
        return
    }

    $imported = 0
    foreach ($raw in Get-Content $Path) {
        $line = $raw.Trim()
        if ($line -match '^(PASS|FAIL)\|([^|]+)(?:\|(.*))?$') {
            $status = $matches[1]
            $name = $matches[2]
            $detail = if ($matches.Count -ge 4) { $matches[3] } else { "" }
            Add-ImportedResult $status $Prefix $name $detail
            $imported += 1
        }
    }
    Add-Result "PASS" "${Prefix}imported_count" "count=$imported"
}

function Write-SummaryAndExit {
    param([int]$Code)
    $summary = "SUMMARY|pass=$script:Passed|fail=$script:Failed|skip=$script:Skipped|total=$script:Total"
    Write-Host $summary
    $script:Lines.Add($summary) | Out-Null
    $outPath = Join-Path $GeneratedDir "everything_test_report.txt"
    [System.IO.File]::WriteAllLines($outPath, $script:Lines, [System.Text.UTF8Encoding]::new($false))
    Write-Host "LOG|$outPath"
    exit $Code
}

function Invoke-ArqenStep {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$Block,
        [switch]$AllowSkip
    )

    Push-Location $RepoRoot
    try {
        $global:LASTEXITCODE = 0
        & $Block *> (Join-Path $LogDir "$Name.log")
        $exit = if ($null -eq $LASTEXITCODE) { if ($?) { 0 } else { 1 } } else { [int]$LASTEXITCODE }
        if ($exit -eq 0) { Add-Result "PASS" $Name "exit=0" }
        elseif ($AllowSkip) { Add-Result "SKIP" $Name "exit=$exit" }
        else { Add-Result "FAIL" $Name "exit=$exit log=Build\Logs\$Name.log" }
    } catch {
        if ($AllowSkip) { Add-Result "SKIP" $Name $_.Exception.Message }
        else { Add-Result "FAIL" $Name $_.Exception.Message }
    } finally {
        Pop-Location
    }
}

function Invoke-CompilerCase {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [int]$ExpectedExit = 0,
        [switch]$BackendOnly
    )

    Push-Location $RepoRoot
    try {
        $args = @()
        if ($BackendOnly) { $args += "--backend-only" }
        $args += $SourcePath
        & (Join-Path $RepoRoot "Tools\arqc.ps1") @args *> (Join-Path $LogDir "$Name.log")
        $exit = if ($null -eq $LASTEXITCODE) { if ($?) { 0 } else { 1 } } else { [int]$LASTEXITCODE }
        if ($exit -eq $ExpectedExit) { Add-Result "PASS" $Name "exit=$exit" }
        else { Add-Result "FAIL" $Name "exit=$exit expected=$ExpectedExit log=Build\Logs\$Name.log" }
    } catch {
        Add-Result "FAIL" $Name $_.Exception.Message
    } finally {
        Pop-Location
    }
}

function Invoke-ValidatorByRelativePath {
    param([string]$RelativePath)
    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path $path)) {
        Add-Result "FAIL" ("validator_missing_" + (Convert-ToSafeStepName $RelativePath)) $RelativePath
        return
    }
    $name = "validator_" + (([IO.Path]::GetFileNameWithoutExtension($path)) -replace '^validate_','' -replace '[^A-Za-z0-9]+','_')
    Invoke-ArqenStep $name { & $path }
}

Write-Host "INFO|repo_root|$RepoRoot"
Write-Host "INFO|command_tests|expanded into this report from Build\Logs\test_slice.last.txt"
Write-Host "INFO|historical_validators|default=off; use -IncludeHistoricalValidators for old milestone/doc validators"

if ($BuildDriver) { Invoke-ArqenStep "build_driver" { & (Join-Path $RepoRoot "Tools\arqc.ps1") -BuildDriver } }

Invoke-ArqenStep "clean_check" { & (Join-Path $RepoRoot "Tools\clean.ps1") -CheckOnly }
Invoke-ArqenStep "tool_surface" { & (Join-Path $RepoRoot "Tools\validate.ps1") tool_surface }
Invoke-ArqenStep "trash" { & (Join-Path $RepoRoot "Tools\validate.ps1") trash }
Invoke-ArqenStep "repo_verify_validators" { & (Join-Path $RepoRoot "Tools\verify_repo.ps1") -RunValidators }
Invoke-ArqenStep "runtime_registry" { & (Join-Path $RepoRoot "Tools\generate.ps1") runtime_registry }

$generators = @(Get-ChildItem (Join-Path $RepoRoot "Tools\Generate") -Recurse -File -Filter "generate_*.ps1" | Sort-Object FullName)
foreach ($generator in $generators) {
    $name = "generator_" + ($generator.BaseName -replace '^generate_','' -replace '[^A-Za-z0-9]+','_')
    Invoke-ArqenStep $name { & $generator.FullName }
}

Invoke-ArqenStep "runtime_action_catalog" { & (Join-Path $RepoRoot "Tools\validate.ps1") runtime_action_catalog }
Invoke-ArqenStep "backend_docs" { & (Join-Path $RepoRoot "Tools\validate.ps1") backend_docs }

Invoke-ArqenStep "command_tests_runner" { & (Join-Path $RepoRoot "Tools\test.ps1") -AllCommand }
Import-TestSliceLog (Join-Path $LogDir "test_slice.last.txt") "cmd_"

if (-not $SkipValidators) {
    $activeValidators = @(
        "Tools\Validate\Core\validate_backend_capabilities.ps1",
        "Tools\Validate\Core\validate_backend_contract_docs.ps1",
        "Tools\Validate\Core\validate_ir_contract.ps1",
        "Tools\Validate\Core\validate_keyword_registry.ps1",
        "Tools\Validate\Core\validate_parser_split.ps1",
        "Tools\Validate\Core\validate_parser_statement_map.ps1",
        "Tools\Validate\Core\validate_repo_hygiene.ps1",
        "Tools\Validate\Core\validate_runtime_action_catalog.ps1",
        "Tools\Validate\Core\validate_strict_ir.ps1",
        "Tools\Validate\Core\validate_test_slice.ps1",
        "Tools\Validate\Core\validate_tool_surface.ps1",
        "Tools\Validate\Core\validate_trash.ps1",
        "Tools\Validate\Core\validate_wrapper_cache_contract.ps1",
        "Tools\Validate\Runtime\validate_m61_m62_enum_scope_params.ps1"
    )

    if ($IncludeSpecCoverageValidators) {
        $activeValidators += @(
            "Tools\Validate\Core\validate_command_specs.ps1",
            "Tools\Validate\Core\validate_command_test_coverage.ps1"
        )
    } else {
        Add-Result "SKIP" "spec_coverage_validators" "use -IncludeSpecCoverageValidators to enforce command spec/coverage metadata"
    }

    if ($IncludeHistoricalValidators) {
        $validators = @(Get-ChildItem (Join-Path $RepoRoot "Tools\Validate") -Recurse -File -Filter "validate_*.ps1" | Sort-Object FullName)
        foreach ($validator in $validators) {
            $rel = ConvertTo-ArqenRelativePath $validator.FullName $RepoRoot
            $name = "validator_" + ($validator.BaseName -replace '^validate_','' -replace '[^A-Za-z0-9]+','_')
            Invoke-ArqenStep $name { & $validator.FullName }
        }
    } else {
        foreach ($rel in $activeValidators) { Invoke-ValidatorByRelativePath $rel }
        Add-Result "SKIP" "historical_validators" "use -IncludeHistoricalValidators to run old M19-M60 milestone validators"
    }
} else {
    Add-Result "SKIP" "all_validators" "SkipValidators set"
}

if ($IncludeExpectedIr) {
    Invoke-ArqenStep "expected_ir" { & (Join-Path $RepoRoot "Tools\verify_expected_ir.ps1") }
} else {
    Add-Result "SKIP" "expected_ir" "legacy ExpectedIR fixtures are opt-in; use -IncludeExpectedIr"
}

if (-not $SkipBackendFixtures) {
    $backendExpected = Join-Path $RepoRoot "Tests\Backend\WindowsX64PE\expected.txt"
    if (Test-Path $backendExpected) {
        foreach ($raw in Get-Content $backendExpected) {
            $line = $raw.Trim()
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
            $parts = $line.Split('|')
            if ($parts.Length -lt 2) { Add-Result "FAIL" "backend_bad_expected" $line; continue }
            $file = $parts[0]
            $expectedExit = [int]$parts[1]
            $source = Join-Path (Split-Path -Parent $backendExpected) $file
            if (-not (Test-Path $source)) { Add-Result "FAIL" "backend_$([IO.Path]::GetFileNameWithoutExtension($file))" "missing $file"; continue }
            $backendOnly = $file.EndsWith('.arqir', [System.StringComparison]::OrdinalIgnoreCase)
            Invoke-CompilerCase "backend_$([IO.Path]::GetFileNameWithoutExtension($file))" $source $expectedExit -BackendOnly:$backendOnly
        }
    } else {
        Add-Result "SKIP" "backend_fixtures" "missing Tests\Backend\WindowsX64PE\expected.txt"
    }
} else {
    Add-Result "SKIP" "backend_fixtures" "SkipBackendFixtures set"
}

$cacheDir = Join-Path $RepoRoot "Tests\Cache"
if (Test-Path $cacheDir) {
    $cacheCases = @(
        @{ File = "cache_valid.arq"; Exit = 0 },
        @{ File = "cache_invalid.arq"; Exit = 1 }
    )
    foreach ($case in $cacheCases) {
        $source = Join-Path $cacheDir $case.File
        if (Test-Path $source) { Invoke-CompilerCase "cache_$([IO.Path]::GetFileNameWithoutExtension($case.File))" $source $case.Exit }
        else { Add-Result "SKIP" "cache_$([IO.Path]::GetFileNameWithoutExtension($case.File))" "missing $($case.File)" }
    }
}

$diagDir = Join-Path $RepoRoot "Tests\Diagnostics"
if (Test-Path $diagDir) {
    foreach ($source in @(Get-ChildItem $diagDir -File -Filter "*.arq" | Sort-Object Name)) {
        Invoke-CompilerCase "diagnostic_$($source.BaseName)" $source.FullName 1
    }
}

if (-not $SkipSamples) {
    $sampleRoot = Join-Path $RepoRoot "Tests\Samples"
    if (Test-Path $sampleRoot) {
        foreach ($source in @(Get-ChildItem $sampleRoot -Recurse -File -Filter "*.arq" | Sort-Object FullName)) {
            $rel = ConvertTo-ArqenRelativePath $source.FullName $RepoRoot
            $name = "sample_" + (($rel -replace '^Tests[\\/]Samples[\\/]','') -replace '[^A-Za-z0-9]+','_').Trim('_')
            Invoke-CompilerCase $name $source.FullName 0
        }
    }
} else {
    Add-Result "SKIP" "samples" "SkipSamples set"
}

if ($IncludeBuildScripts) {
    foreach ($script in @(Get-ChildItem (Join-Path $RepoRoot "Tools\Build") -Recurse -File -Filter "build_*.ps1" | Sort-Object FullName)) {
        $name = "buildscript_" + ($script.BaseName -replace '^build_','' -replace '[^A-Za-z0-9]+','_')
        Invoke-ArqenStep $name { & $script.FullName } -AllowSkip
    }
} else {
    Add-Result "SKIP" "build_scripts" "set -IncludeBuildScripts to run native/DX12 build scripts"
}

if ($IncludeScaffoldScripts) {
    foreach ($script in @(Get-ChildItem (Join-Path $RepoRoot "Tools\Scaffold") -Recurse -File -Filter "*.ps1" | Sort-Object FullName)) {
        $name = "scaffold_" + ($script.BaseName -replace '[^A-Za-z0-9]+','_')
        Invoke-ArqenStep $name { & $script.FullName -Help } -AllowSkip
    }
} else {
    Add-Result "SKIP" "scaffold_scripts" "set -IncludeScaffoldScripts to smoke scaffold scripts"
}

if ($script:Failed -gt 0) { Write-SummaryAndExit 1 }
Write-SummaryAndExit 0
