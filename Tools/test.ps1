param(
    [switch]$AllCommand,
    [switch]$Everything,
    [switch]$List,
    [switch]$BuildDriver,
    [switch]$StopOnFail,
    [switch]$Changed,
    [switch]$IncludeBuildScripts,
    [switch]$IncludeScaffoldScripts,
    [switch]$IncludeHistoricalValidators,
    [switch]$IncludeSpecCoverageValidators,
    [switch]$IncludeExpectedIr,
    [switch]$SkipValidators,
    [switch]$SkipSamples,
    [switch]$SkipBackendFixtures,
    [string[]]$Folder = @(),
    [string[]]$Group = @(),
    [string[]]$Case = @(),
    [string[]]$Tool = @(),
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

function Get-ArqenRepoRoot {
    $dir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    while ($true) {
        if (
            (Test-Path (Join-Path $dir "Docs\MILESTONES.md")) -and
            (Test-Path (Join-Path $dir "Tools\M10GDriver")) -and
            (Test-Path (Join-Path $dir "Tests\CommandTests"))
        ) {
            return $dir
        }

        $parent = Split-Path -Parent $dir
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $dir) {
            break
        }

        $dir = $parent
    }

    throw "Could not locate Arqen repo root from $PSScriptRoot"
}

function Add-StringArrayParam {
    param(
        [hashtable]$Table,
        [string]$Name,
        [string[]]$Values
    )

    $clean = @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($clean.Count -gt 0) {
        $Table[$Name] = $clean
    }
}

$RepoRoot = Get-ArqenRepoRoot
$sliceRunnerPath = Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1"


$everythingRunnerPath = Join-Path $RepoRoot "Tools\Internal\Test\run_everything.ps1"
if ($Everything) {
    if (-not (Test-Path $everythingRunnerPath)) {
        throw "Everything test runner not found: $everythingRunnerPath"
    }
    $everythingParams = @{}
    if ($BuildDriver) { $everythingParams["BuildDriver"] = $true }
    if ($StopOnFail) { $everythingParams["StopOnFail"] = $true }
    if ($IncludeBuildScripts) { $everythingParams["IncludeBuildScripts"] = $true }
    if ($IncludeScaffoldScripts) { $everythingParams["IncludeScaffoldScripts"] = $true }
    if ($IncludeHistoricalValidators) { $everythingParams["IncludeHistoricalValidators"] = $true }
    if ($IncludeSpecCoverageValidators) { $everythingParams["IncludeSpecCoverageValidators"] = $true }
    if ($IncludeExpectedIr) { $everythingParams["IncludeExpectedIr"] = $true }
    if ($SkipValidators) { $everythingParams["SkipValidators"] = $true }
    if ($SkipSamples) { $everythingParams["SkipSamples"] = $true }
    if ($SkipBackendFixtures) { $everythingParams["SkipBackendFixtures"] = $true }
    & $everythingRunnerPath @everythingParams @RemainingArgs
    exit $LASTEXITCODE
}
if (-not (Test-Path $sliceRunnerPath)) {
    throw "Test slice runner not found: $sliceRunnerPath"
}

$runnerParams = @{}
if ($AllCommand) { $runnerParams["AllCommand"] = $true }
if ($List) { $runnerParams["List"] = $true }
if ($BuildDriver) { $runnerParams["BuildDriver"] = $true }
if ($StopOnFail) { $runnerParams["StopOnFail"] = $true }
if ($Changed) { $runnerParams["Changed"] = $true }
Add-StringArrayParam $runnerParams "Folder" $Folder
Add-StringArrayParam $runnerParams "Group" $Group
Add-StringArrayParam $runnerParams "Case" $Case
Add-StringArrayParam $runnerParams "Tool" $Tool

if ($runnerParams.Count -eq 0 -and ($null -eq $RemainingArgs -or $RemainingArgs.Count -eq 0)) {
    $runnerParams["List"] = $true
}

& $sliceRunnerPath @runnerParams @RemainingArgs
exit $LASTEXITCODE
