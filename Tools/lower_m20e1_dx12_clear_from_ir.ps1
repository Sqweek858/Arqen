param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "Common\ArqenTooling.psm1") -Force
$RepoRoot = Get-ArqenRepoRoot -StartPath $PSScriptRoot
$script = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
if (-not (Test-Path $script)) { throw "Missing DX12 lowering helper: $script" }
& $script @RemainingArgs
exit $LASTEXITCODE
