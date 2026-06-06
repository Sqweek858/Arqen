$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "CommandAutomationCommon.psm1") -Force

$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "keyword_registry.txt"
$found = New-Object System.Collections.Generic.HashSet[string]

foreach ($spec in Get-ArqenCommandSpecs) {
    $tokens = Get-ArqenSpecValue $spec "TOKENS" ""
    foreach ($keyword in Get-ArqenKeywordTokens $tokens) {
        $found.Add($keyword) | Out-Null
    }
}

$preferred = @("program", "end", "let", "be", "title", "set", "to", "message", "text", "show", "exit", "blend", "mix", "code", "true", "false")
$ordered = @()
foreach ($keyword in $preferred) {
    if ($found.Contains($keyword)) {
        $ordered += $keyword
    }
}
foreach ($keyword in ($found | Sort-Object)) {
    if ($ordered -notcontains $keyword) {
        $ordered += $keyword
    }
}

$lines = $ordered | ForEach-Object { "KEYWORD|$_" }
Set-Content -Path $outPath -Value $lines -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
exit 0
