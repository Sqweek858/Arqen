param(
    [string[]]$Folder = @(),
    [string[]]$Group = @(),
    [string[]]$Case = @(),
    [string[]]$Tool = @(),
    [switch]$Changed,
    [switch]$AllCommand,
    [switch]$List,
    [switch]$BuildDriver,
    [switch]$StopOnFail,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "Common\ArqenTooling.psm1") -Force

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

$RepoRoot = Get-ArqenRepoRoot -StartPath $PSScriptRoot
$script = Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1"
if (-not (Test-Path $script)) { throw "Missing test slice runner: $script" }

$runnerParams = @{}
if ($Changed) { $runnerParams["Changed"] = $true }
if ($AllCommand) { $runnerParams["AllCommand"] = $true }
if ($List) { $runnerParams["List"] = $true }
if ($BuildDriver) { $runnerParams["BuildDriver"] = $true }
if ($StopOnFail) { $runnerParams["StopOnFail"] = $true }
Add-StringArrayParam $runnerParams "Folder" $Folder
Add-StringArrayParam $runnerParams "Group" $Group
Add-StringArrayParam $runnerParams "Case" $Case
Add-StringArrayParam $runnerParams "Tool" $Tool

& $script @runnerParams @RemainingArgs
exit $LASTEXITCODE
