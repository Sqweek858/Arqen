param(
    [Parameter(Mandatory=$true)]
    [string]$CommandId
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
Import-Module (Join-Path $RepoRoot "Tools\Common\CommandAutomationCommon.psm1") -Force

function Normalize-CommandId {
    param([string]$Value)
    $id = $Value.Trim().ToLowerInvariant() -replace '[\s-]+', '_'
    $id = $id -replace '[^a-z0-9_]', ''
    return $id.Trim("_")
}

function Find-CommandSpec {
    param([string]$Id)
    foreach ($spec in Get-ArqenCommandSpecs) {
        $specId = Get-ArqenSpecValue $spec "COMMAND_ID" $spec.Id
        $fileId = [IO.Path]::GetFileNameWithoutExtension($spec.Path).Replace(".command", "")
        if ((Normalize-CommandId $specId) -eq $Id -or (Normalize-CommandId $spec.Id) -eq $Id -or (Normalize-CommandId $fileId) -eq $Id) {
            return $spec
        }
    }
    return $null
}

$id = Normalize-CommandId $CommandId
if ([string]::IsNullOrWhiteSpace($id)) {
    Write-Error "CommandId is required."
    exit 2
}

$spec = Find-CommandSpec $id
$status = "skeleton"
$tokens = ""
$ast = ""
$semantic = ""
$ir = ""
$backend = ""
if ($spec) {
    $status = Get-ArqenSpecValue $spec "STATUS" "stable"
    $tokens = Get-ArqenSpecValue $spec "TOKENS" ""
    $ast = Get-ArqenSpecValue $spec "AST_NODE" ""
    $semantic = Get-ArqenSpecValue $spec "SEMANTIC" ""
    $ir = Get-ArqenSpecValue $spec "IR" ""
    $backend = Get-ArqenSpecValue $spec "BACKEND" ""
}

$keywords = @(Get-ArqenKeywordTokens $tokens)
$keywordReason = if ($keywords.Count -gt 0) { "add keywords $($keywords -join ',')" } else { "no new keywords detected" }
$parserReason = if ([string]::IsNullOrWhiteSpace($tokens)) { "add parser rule from command syntax" } else { "add rule $tokens" }
$astReason = if ([string]::IsNullOrWhiteSpace($ast) -or $ast -eq "none") { "no AST node required" } else { "emit $ast" }
$semanticReason = if ([string]::IsNullOrWhiteSpace($semantic)) { "confirm semantic behavior" } else { $semantic }
$irReason = if ([string]::IsNullOrWhiteSpace($ir) -or $ir -eq "none") { "no IR lowering required" } else { "lower to $ir action" }
$backendNeed = if ([string]::IsNullOrWhiteSpace($backend) -or $backend -eq "none" -or $backend -match 'exit|show_message') { "not-required" } else { "required" }
$backendReason = if ($backendNeed -eq "not-required") { "existing backend can be reused or no backend is needed" } else { "confirm backend support for $backend" }

$outDir = Join-Path (Get-ArqenGeneratedDir) "CommandSkeletons"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outPath = Join-Path $outDir "$id.touch_map.txt"

$lines = @(
    "COMMAND|$id",
    "STATUS|$status",
    "TOUCH|lexer|required|reason=$keywordReason",
    "TOUCH|parser|required|reason=$parserReason",
    "TOUCH|ast|required|reason=$astReason",
    "TOUCH|semantic|required|reason=$semanticReason",
    "TOUCH|ir|required|reason=$irReason",
    "TOUCH|backend|$backendNeed|reason=$backendReason",
    "TOUCH|tests|required|reason=valid and invalid command tests",
    "TOUCH|spec|required|reason=command spec must exist",
    "TOUCH|diagnostics|required|reason=parser/semantic errors must aggregate into all_errors",
    "TOUCH|cache|not-required|reason=command specs/tool hashes already invalidate cache"
)

Set-Content -Path $outPath -Value $lines -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
exit 0
