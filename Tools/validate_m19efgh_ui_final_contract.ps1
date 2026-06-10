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
function Read-TextSafe {
    param([string]$Path)
    if (Test-Path $Path) { return [System.IO.File]::ReadAllText($Path) }
    return ""
}

$parserPath = Join-Path $RepoRoot "Tools/M10GDriver/Parser/Parser.UiFinal.cs"
$corePath = Join-Path $RepoRoot "Tools/M10GDriver/Parser/Parser.Core.cs"
$modelsPath = Join-Path $RepoRoot "Tools/M10GDriver/Core/Models.cs"
$astPath = Join-Path $RepoRoot "Tools/M10GDriver/Frontend/AstEmit.cs"
$irEmitPath = Join-Path $RepoRoot "Tools/M10GDriver/Frontend/IrEmit.cs"
$irModelPath = Join-Path $RepoRoot "Tools/M10GDriver/Backend/IrModel.cs"
$specPath = Join-Path $RepoRoot "Specs/Commands/ui_final.command.txt"
$testRoot = Join-Path $RepoRoot "Tests/CommandTests/ui_final"
$expectedPath = Join-Path $testRoot "expected.txt"
$irDocPath = Join-Path $RepoRoot "IR/ARQIR_V0_CONTRACT.md"
$runtimeDocPath = Join-Path $RepoRoot "Runtime/RUNTIME_CONTRACT.md"

$parser = Read-TextSafe $parserPath
$core = Read-TextSafe $corePath
$models = Read-TextSafe $modelsPath
$ast = Read-TextSafe $astPath
$irEmit = Read-TextSafe $irEmitPath
$irModel = Read-TextSafe $irModelPath
$spec = Read-TextSafe $specPath
$irDoc = Read-TextSafe $irDocPath
$runtimeDoc = Read-TextSafe $runtimeDocPath

Emit-Check "m19efgh_parser_exists" (Test-Path $parserPath) "Parser.UiFinal.cs present"
Emit-Check "m19efgh_dispatch_present" ($core -match 'ParseUiBindingStatement' -and $core -match 'ParseUiStateStatement' -and $core -match 'ParseUiResourceDefinitionStatement') "parser dispatch knows UI final statements"
Emit-Check "m19efgh_when_extension" ($parser -match 'ParseUiEventStatementAfterWhen' -and $parser -match 'UiEventNames') "when parser has UI event branch"
Emit-Check "m19efgh_models_present" ($models -match 'record UiEvent' -and $models -match 'record UiBinding' -and $models -match 'record UiState' -and $models -match 'record UiResource' -and $models -match 'record UiResourceUse') "UI final model records present"
Emit-Check "m19efgh_ast_lines" ($ast -match 'UI_EVENT' -and $ast -match 'UI_BIND' -and $ast -match 'UI_STATE' -and $ast -match 'UI_RESOURCE_USE') "AST emits UI final metadata"
Emit-Check "m19efgh_ir_lines" ($irEmit -match 'UI_EVENT' -and $irEmit -match 'UI_BIND' -and $irEmit -match 'UI_STATE' -and $irEmit -match 'UI_RESOURCE_USE') "IR emits UI final metadata"
Emit-Check "m19efgh_backend_ir_accepts_metadata" ($irModel -match 'case "UI_EVENT"' -and $irModel -match 'case "UI_BIND"' -and $irModel -match 'case "UI_STATE"' -and $irModel -match 'case "UI_RESOURCE_USE"') "backend strict IR accepts UI final metadata"
Emit-Check "m19efgh_spec_present" (Test-Path $specPath) "ui_final spec present"
Emit-Check "m19efgh_spec_lists_tests" ($spec -match 'VALID_TEST' -and $spec -match 'INVALID_TEST') "spec lists tests"
Emit-Check "m19efgh_tests_present" (Test-Path $expectedPath) "ui_final expected.txt present"

$validCount = if (Test-Path $testRoot) { @(Get-ChildItem $testRoot -Filter 'valid_*.arq' -File).Count } else { 0 }
$invalidCount = if (Test-Path $testRoot) { @(Get-ChildItem $testRoot -Filter 'invalid_*.arq' -File).Count } else { 0 }
Emit-Check "m19efgh_valid_test_count" ($validCount -ge 6) "valid=$validCount"
Emit-Check "m19efgh_invalid_test_count" ($invalidCount -ge 19) "invalid=$invalidCount"
Emit-Check "m19efgh_ir_doc_mentions_ui_final" ($irDoc -match 'UI_EVENT' -and $irDoc -match 'UI_BIND' -and $irDoc -match 'UI_RESOURCE_USE') "IR doc mentions UI final metadata"
Emit-Check "m19efgh_runtime_doc_boundary" ($runtimeDoc -match 'M19E/F/G/H UI final boundary' -and $runtimeDoc -match 'metadata only') "runtime doc keeps UI final metadata-only"

if ($failed) { exit 1 }
exit 0
