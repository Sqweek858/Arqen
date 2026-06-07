param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$failed = $false
function Emit-Check {
    param([string]$Name, [bool]$Ok, [string]$Message)
    if ($Ok) { Write-Host "PASS|$Name|$Message" } else { Write-Host "FAIL|$Name|$Message"; $script:failed = $true }
}

$lexerPath = Join-Path $RepoRoot "Tools/M10GDriver/Frontend/Lexer.cs"
$keywordTool = Join-Path $RepoRoot "Tools/generate_keyword_registry.ps1"
$generatedPath = Join-Path $RepoRoot "Build/Generated/keyword_registry.txt"
$lexerOutPath = Join-Path $RepoRoot "Build/Generated/lexer_keyword_registry.txt"

Emit-Check "keyword_lexer_exists" (Test-Path $lexerPath) "lexer source present"
Emit-Check "keyword_generator_exists" (Test-Path $keywordTool) "keyword generator present"

$lexerText = if (Test-Path $lexerPath) { [System.IO.File]::ReadAllText($lexerPath) } else { "" }
$lexerKeywords = New-Object System.Collections.Generic.HashSet[string]
foreach ($m in [regex]::Matches($lexerText, 'word\s+is\s+([^\r\n]+)')) {
    foreach ($q in [regex]::Matches($m.Groups[1].Value, '"([a-z_][a-z0-9_]*)"')) {
        [void]$lexerKeywords.Add($q.Groups[1].Value)
    }
}

$lexerLines = $lexerKeywords | Sort-Object | ForEach-Object { "LEXER_KEYWORD|$_" }
New-Item -ItemType Directory -Force -Path (Split-Path $lexerOutPath -Parent) | Out-Null
Set-Content -Path $lexerOutPath -Value $lexerLines -Encoding UTF8
$lexerLines | ForEach-Object { Write-Host $_ }

if (Test-Path $keywordTool) {
    & $keywordTool *> $null
}

$specKeywords = @()
if (Test-Path $generatedPath) {
    $specKeywords = @(Get-Content $generatedPath | Where-Object { $_ -match '^KEYWORD\|' } | ForEach-Object { ($_ -split '\|', 2)[1].Trim() })
}

$driverText = (
    Get-ChildItem (Join-Path $RepoRoot "Tools/M10GDriver") -Recurse -Filter *.cs |
    Sort-Object FullName |
    ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }
) -join "`n"

$strictKeywordRefs = New-Object System.Collections.Generic.HashSet[string]
foreach ($m in [regex]::Matches($driverText, 'ExpectKeyword\("([a-z_][a-z0-9_]*)"\)')) { [void]$strictKeywordRefs.Add($m.Groups[1].Value) }
foreach ($m in [regex]::Matches($driverText, 'IsKeyword\("([a-z_][a-z0-9_]*)"\)')) { [void]$strictKeywordRefs.Add($m.Groups[1].Value) }
foreach ($m in [regex]::Matches($driverText, 'MatchKeyword\("([a-z_][a-z0-9_]*)"\)')) { [void]$strictKeywordRefs.Add($m.Groups[1].Value) }

$missingStrict = @($strictKeywordRefs | Where-Object { -not $lexerKeywords.Contains($_) -and $_ -notin @('true','false') } | Sort-Object -Unique)
$specOnly = @($specKeywords | Where-Object { -not $lexerKeywords.Contains($_) -and $_ -notin @('true','false') } | Sort-Object -Unique)

Emit-Check "keyword_lexer_min_count" ($lexerKeywords.Count -ge 50) "lexer keyword count=$($lexerKeywords.Count)"
Emit-Check "keyword_spec_min_count" ($specKeywords.Count -ge 25) "spec keyword count=$($specKeywords.Count)"
Emit-Check "keyword_strict_refs_in_lexer" ($missingStrict.Count -eq 0) ("missing=" + ($missingStrict -join ','))
if ($specOnly.Count -gt 0) { Write-Host ("WARN|keyword_spec_words_not_lexer|count=$($specOnly.Count)|" + ($specOnly -join ',')) } else { Write-Host "PASS|keyword_spec_words_not_lexer|count=0" }

$reservedDocs = @(
    (Join-Path $RepoRoot "Backends/DX12/DX12_BACKEND_CONTRACT.md"),
    (Join-Path $RepoRoot "Runtime/RUNTIME_CONTRACT.md"),
    (Join-Path $RepoRoot "Docs/M18B_DX12_READY_GATE.md")
)
$docsText = ($reservedDocs | Where-Object { Test-Path $_ } | ForEach-Object { [System.IO.File]::ReadAllText($_) }) -join "`n"
foreach ($reserved in @('dx12','shader','render_pass','frame_update')) {
    Emit-Check "keyword_reserved_$reserved" ($docsText -match [regex]::Escape($reserved)) "reserved keyword/action documented"
}

if ($failed) { exit 1 }
exit 0
