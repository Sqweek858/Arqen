$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
Import-Module (Join-Path $RepoRoot "Tools\Common\CommandAutomationCommon.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "command_status.txt"
$lines = @()
$implementedIds = @{}

foreach ($spec in Get-ArqenCommandSpecs) {
    $id = Get-ArqenSpecValue $spec "COMMAND_ID" $spec.Id
    $implementedIds[$id] = $true
    $valid = Get-ArqenSpecValue $spec "VALID_TEST" ""
    $invalid = Get-ArqenSpecValue $spec "INVALID_TEST" ""
    $tokens = Get-ArqenSpecValue $spec "TOKENS" ""
    $ast = Get-ArqenSpecValue $spec "AST_NODE" "none"
    $semantic = Get-ArqenSpecValue $spec "SEMANTIC" ""
    $ir = Get-ArqenSpecValue $spec "IR" "none"
    $backend = Get-ArqenSpecValue $spec "BACKEND" "none"
    $status = Get-ArqenSpecValue $spec "STATUS" "stable"
    $tests = if ((Test-ArqenReferencedPath $valid) -and (Test-ArqenReferencedPath $invalid)) { "yes" } else { "no" }
    $lexer = if ([string]::IsNullOrWhiteSpace($tokens)) { "no" } else { "yes" }
    $parser = if ($ast -eq "none") { "no" } else { "yes" }
    $astStatus = if ($ast -eq "none") { "none" } else { "yes" }
    $semanticStatus = if ([string]::IsNullOrWhiteSpace($semantic)) { "no" } else { "yes" }
    $irStatus = if ($ir -eq "none") { "none" } else { "yes" }
    $backendStatus = if ($backend -eq "none") { "none" } else { "yes" }
    $lines += "COMMAND|$id|spec=yes|tests=$tests|lexer=$lexer|parser=$parser|ast=$astStatus|semantic=$semanticStatus|ir=$irStatus|backend=$backendStatus|status=$status"
}

$draft = Join-Path $root "Experiments\CommandDrafts\BlendMixToCode\COMMAND_SPEC.command.txt"
if ((Test-Path $draft) -and -not $implementedIds.ContainsKey("BlendMixToCode")) {
    $lines += "COMMAND|BlendMixToCode|spec=draft|tests=draft|lexer=no|parser=no|ast=no|semantic=no|ir=no|backend=no|status=planned"
}

Set-Content -Path $outPath -Value $lines -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
exit 0
