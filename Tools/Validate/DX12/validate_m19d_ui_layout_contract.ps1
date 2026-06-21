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

$parserPath = Join-Path $RepoRoot "Tools/M10GDriver/Parser/Parser.Layout.cs"
$corePath = Join-Path $RepoRoot "Tools/M10GDriver/Parser/Parser.Core.cs"
$modelsPath = Join-Path $RepoRoot "Tools/M10GDriver/Core/Models.cs"
$astPath = Join-Path $RepoRoot "Tools/M10GDriver/Frontend/AstEmit.cs"
$irEmitPath = Join-Path $RepoRoot "Tools/M10GDriver/Frontend/IrEmit.cs"
$irModelPath = Join-Path $RepoRoot "Tools/M10GDriver/Backend/IrModel.cs"
$specPath = Join-Path $RepoRoot "Tests/CommandTests/misc/ui_layout.command.txt"
$testRoot = Join-Path $RepoRoot "Tests/CommandTests/ui_layout"
$expectedPath = Join-Path $testRoot "expected.txt"
$irDocPath = Join-Path $RepoRoot "Docs/Reference/IR/ARQIR_V0_CONTRACT.md"
$runtimeDocPath = Join-Path $RepoRoot "Docs/Reference/Runtime/RUNTIME_CONTRACT.md"

$parser = Read-TextSafe $parserPath
$core = Read-TextSafe $corePath
$models = Read-TextSafe $modelsPath
$ast = Read-TextSafe $astPath
$irEmit = Read-TextSafe $irEmitPath
$irModel = Read-TextSafe $irModelPath
$spec = Read-TextSafe $specPath
$irDoc = Read-TextSafe $irDocPath
$runtimeDoc = Read-TextSafe $runtimeDocPath

Emit-Check "m19d_layout_parser_exists" (Test-Path $parserPath) "Parser.Layout.cs present"
Emit-Check "m19d_dispatch_present" ($core -match 'ParseUiParentStatement' -and $core -match 'ParseUiLayoutStatement' -and $core -match 'ParseUiDockStatement') "parser dispatch knows parent/layout/dock"
Emit-Check "m19d_models_present" ($models -match 'record UiLayoutProperty' -and $models -match 'record UiParent' -and $models -match 'record UiDock') "layout model records present"
Emit-Check "m19d_layout_properties" ($parser -match 'UiLayoutProperties' -and $parser -match 'offset x' -and $parser -match 'columns' -and $parser -match 'rows') "layout property whitelist present"
Emit-Check "m19d_layout_values" ($parser -match 'UiLayoutAnchorValues' -and $parser -match 'UiLayoutModeValues' -and $parser -match 'UiLayoutDirectionValues') "layout enum values present"
Emit-Check "m19d_hierarchy_validation" ($parser -match 'WouldCreateParentCycle' -and $parser -match 'ValidateUiParentTarget' -and $parser -match 'already has a parent or dock') "hierarchy validation present"
Emit-Check "m19d_ast_lines" ($ast -match 'UI_LAYOUT' -and $ast -match 'UI_PARENT' -and $ast -match 'UI_DOCK') "AST emits hierarchy/layout metadata"
Emit-Check "m19d_ir_lines" ($irEmit -match 'UI_LAYOUT' -and $irEmit -match 'UI_PARENT' -and $irEmit -match 'UI_DOCK') "IR emits hierarchy/layout metadata"
Emit-Check "m19d_backend_ir_accepts_metadata" ($irModel -match 'case "UI_LAYOUT"' -and $irModel -match 'case "UI_PARENT"' -and $irModel -match 'case "UI_DOCK"') "backend strict IR accepts layout metadata"
Emit-Check "m19d_spec_present" (Test-Path $specPath) "ui_layout spec present"
Emit-Check "m19d_spec_lists_tests" ($spec -match 'VALID_TEST' -and $spec -match 'INVALID_TEST') "spec lists tests"
Emit-Check "m19d_tests_present" (Test-Path $expectedPath) "ui_layout expected.txt present"

$validCount = if (Test-Path $testRoot) { @(Get-ChildItem $testRoot -Filter 'valid_*.arq' -File).Count } else { 0 }
$invalidCount = if (Test-Path $testRoot) { @(Get-ChildItem $testRoot -Filter 'invalid_*.arq' -File).Count } else { 0 }
Emit-Check "m19d_valid_test_count" ($validCount -ge 7) "valid=$validCount"
Emit-Check "m19d_invalid_test_count" ($invalidCount -ge 17) "invalid=$invalidCount"
Emit-Check "m19d_ir_doc_mentions_layout" ($irDoc -match 'UI_LAYOUT' -and $irDoc -match 'UI_PARENT' -and $irDoc -match 'UI_DOCK') "IR doc mentions layout metadata"
Emit-Check "m19d_runtime_doc_boundary" ($runtimeDoc -match 'M19D UI hierarchy/layout boundary' -and $runtimeDoc -match 'not runtime actions') "runtime doc keeps layout metadata-only"

if ($failed) { exit 1 }
exit 0
