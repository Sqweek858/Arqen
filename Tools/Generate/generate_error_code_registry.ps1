$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
Import-Module (Join-Path $RepoRoot "Tools\Common\CommandAutomationCommon.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "error_code_registry.txt"
$summaryPath = Join-Path $generated "error_code_summary.txt"
$codeMap = @{}
$patterns = @(
    'CompileError\("[A-Z]+",\s*"([A-Z][0-9]{3})"',
    'Write-BackendError\s+"([A-Z][0-9]{3})"',
    'Add-Diagnostic\s+"([A-Z][0-9]{3})"',
    'Error\s+([A-Z][0-9]{3})'
)

$files = @()
$files += Get-ChildItem (Join-Path $root "Tools") -Include "*.ps1", "*.psm1", "*.cs" -File -Recurse
$files += Get-ChildItem (Join-Path $root "Docs") -Include "*.md", "*.txt" -File -Recurse -ErrorAction SilentlyContinue

foreach ($file in $files | Sort-Object FullName) {
    $rel = ConvertTo-ArqenRelativePath $file.FullName
    $text = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -eq $text) { continue }
    foreach ($pattern in $patterns) {
        foreach ($m in [regex]::Matches($text, $pattern)) {
            $code = $m.Groups[1].Value
            if (-not $codeMap.ContainsKey($code)) {
                $codeMap[$code] = New-Object System.Collections.Generic.List[string]
            }
            if (-not $codeMap[$code].Contains($rel)) {
                $codeMap[$code].Add($rel) | Out-Null
            }
        }
    }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("ERROR_CODE_REGISTRY|generated") | Out-Null
foreach ($code in ($codeMap.Keys | Sort-Object)) {
    $stage = switch -Regex ($code) {
        '^L' { 'lexer'; break }
        '^P' { 'parser'; break }
        '^S' { 'semantic'; break }
        '^I' { 'ir'; break }
        '^B' { 'backend'; break }
        '^C' { 'codegen'; break }
        default { 'unknown' }
    }
    $lines.Add("ERROR|$code|stage=$stage|refs=$($codeMap[$code].Count)|files=$($codeMap[$code] -join ';')") | Out-Null
}
$lines.Add("TOTAL|$($codeMap.Count)") | Out-Null
Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8

$summary = @(
    "TOTAL|$($codeMap.Count)",
    "LEXER|$(@($codeMap.Keys | Where-Object { $_.StartsWith('L') }).Count)",
    "PARSER|$(@($codeMap.Keys | Where-Object { $_.StartsWith('P') }).Count)",
    "SEMANTIC|$(@($codeMap.Keys | Where-Object { $_.StartsWith('S') }).Count)",
    "BACKEND|$(@($codeMap.Keys | Where-Object { $_.StartsWith('B') }).Count)"
)
Set-Content -Path $summaryPath -Value $summary -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
exit 0
