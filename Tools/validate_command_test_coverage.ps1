$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "CommandAutomationCommon.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "command_test_coverage_validation.txt"
$testRoot = Join-Path $root "Tests\CommandTests"
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

$totalFolders = 0
$totalTests = 0
foreach ($folder in Get-ChildItem $testRoot -Directory | Sort-Object Name) {
    $totalFolders += 1
    $expected = Join-Path $folder.FullName "expected.txt"
    Add-Result "expected_$($folder.Name)" (Test-Path $expected) "expected.txt required"
    if (-not (Test-Path $expected)) { continue }

    $listed = @{}
    foreach ($raw in Get-Content $expected) {
        $line = $raw.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
        $parts = $line.Split([char]"|")
        if ($parts.Length -lt 4) {
            Add-Result "expected_format_$($folder.Name)" $false $line
            continue
        }
        $listed[$parts[0]] = $true
        Add-Result "expected_file_$($folder.Name)_$($parts[0])" (Test-Path (Join-Path $folder.FullName $parts[0])) "expected entry points to existing .arq"
    }

    $validCount = 0
    $invalidCount = 0
    foreach ($test in Get-ChildItem $folder.FullName -Filter "*.arq" -File | Sort-Object Name) {
        $totalTests += 1
        if ($test.Name.StartsWith("valid_")) { $validCount += 1 }
        if ($test.Name.StartsWith("invalid_")) { $invalidCount += 1 }
        Add-Result "listed_$($folder.Name)_$($test.Name)" $listed.ContainsKey($test.Name) "every .arq must be in expected.txt"
    }
    Add-Result "has_valid_$($folder.Name)" ($validCount -gt 0) "at least one valid case"
    Add-Result "has_invalid_$($folder.Name)" ($invalidCount -gt 0) "at least one invalid case"
}

$lines.Insert(0, "SUMMARY|folders=$totalFolders|tests=$totalTests")
Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
