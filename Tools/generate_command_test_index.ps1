$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "CommandAutomationCommon.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "command_test_index.txt"
$testRoot = Join-Path $root "Tests\CommandTests"
$lines = @()

foreach ($folder in Get-ChildItem $testRoot -Directory | Sort-Object Name) {
    foreach ($file in Get-ChildItem $folder.FullName -Filter "*.arq" -File | Sort-Object Name) {
        $kind = if ($file.Name.StartsWith("valid_")) { "valid" } elseif ($file.Name.StartsWith("invalid_")) { "invalid" } else { "unknown" }
        $lines += "TEST|$($folder.Name)|$kind|$(ConvertTo-ArqenRelativePath $file.FullName)"
    }
}

Set-Content -Path $outPath -Value $lines -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
exit 0
