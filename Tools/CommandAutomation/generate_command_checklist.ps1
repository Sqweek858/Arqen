param(
    [Parameter(Mandatory=$true)]
    [string]$CommandId
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "CommandAutomationCommon.psm1") -Force

function Normalize-CommandId {
    param([string]$Value)
    $id = $Value.Trim().ToLowerInvariant() -replace '[\s-]+', '_'
    $id = $id -replace '[^a-z0-9_]', ''
    return $id.Trim("_")
}

$id = Normalize-CommandId $CommandId
if ([string]::IsNullOrWhiteSpace($id)) {
    Write-Error "CommandId is required."
    exit 2
}

$outDir = Join-Path (Get-ArqenGeneratedDir) "CommandSkeletons"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outPath = Join-Path $outDir "$id.implementation_checklist.txt"

$lines = @(
    "CHECK|spec_exists|pending",
    "CHECK|keywords_in_registry|pending",
    "CHECK|lexer_keywords_added|pending",
    "CHECK|parser_rule_added|pending",
    "CHECK|ast_node_emitted|pending",
    "CHECK|semantic_validation_added|pending",
    "CHECK|ir_lowering_added|pending",
    "CHECK|backend_support_confirmed|pending",
    "CHECK|valid_test_added|pending",
    "CHECK|invalid_tests_added|pending",
    "CHECK|all_errors_validated|pending",
    "CHECK|cache_invalidates_on_spec_change|pending",
    "CHECK|run_all_tests_updated|pending"
)

Set-Content -Path $outPath -Value $lines -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
exit 0
