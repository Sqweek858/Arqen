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
    if ($Ok) {
        Write-Host "PASS|$Name|$Message"
    } else {
        Write-Host "FAIL|$Name|$Message"
        $script:failed = $true
    }
}

function Read-TextSafe {
    param([string]$Path)
    if (Test-Path $Path) { return [System.IO.File]::ReadAllText($Path) }
    return ""
}

$parserPath = Join-Path $RepoRoot "Tools/M10GDriver/Parser/Parser.Ui.cs"
$modelsPath = Join-Path $RepoRoot "Tools/M10GDriver/Core/Models.cs"
$astPath = Join-Path $RepoRoot "Tools/M10GDriver/Frontend/AstEmit.cs"
$irEmitPath = Join-Path $RepoRoot "Tools/M10GDriver/Frontend/IrEmit.cs"
$irModelPath = Join-Path $RepoRoot "Tools/M10GDriver/Backend/IrModel.cs"
$specPath = Join-Path $RepoRoot "Specs/Commands/ui_objects.command.txt"
$testRoot = Join-Path $RepoRoot "Tests/CommandTests/ui_objects"
$expectedPath = Join-Path $testRoot "expected.txt"
$irDocPath = Join-Path $RepoRoot "IR/ARQIR_V0_CONTRACT.md"

$parser = Read-TextSafe $parserPath
$models = Read-TextSafe $modelsPath
$ast = Read-TextSafe $astPath
$irEmit = Read-TextSafe $irEmitPath
$irModel = Read-TextSafe $irModelPath
$spec = Read-TextSafe $specPath
$irDoc = Read-TextSafe $irDocPath

Emit-Check "m19c_parser_ui_exists" (Test-Path $parserPath) "Parser.Ui.cs present"
Emit-Check "m19c_models_present" ($models -match 'record UiObject' -and $models -match 'record UiProperty') "UI model records present"
Emit-Check "m19c_define_ui_dispatch" ($parser -match 'ParseUiObjectDefinitionStatement' -and $parser -match 'LooksLikeUiObjectDefinition') "define UI object parser present"
Emit-Check "m19c_set_ui_dispatch" ($parser -match 'ParseUiPropertySetStatement' -and $parser -match 'LooksLikeUiPropertySet') "set UI property parser present"
Emit-Check "m19c_dropdown_options" ($parser -match 'ParseUiDropdownOptionStatement' -and $parser -match 'Duplicate dropdown option') "dropdown option parser present"
Emit-Check "m19c_object_types" ($parser -match 'input field' -and $parser -match 'dropdown' -and $parser -match 'slider') "required UI object types listed"
Emit-Check "m19c_ast_lines" ($ast -match 'UI_OBJECT' -and $ast -match 'UI_SET') "AST emits UI metadata"
Emit-Check "m19c_ir_lines" ($irEmit -match 'UI_OBJECT' -and $irEmit -match 'UI_SET') "IR emits UI metadata"
Emit-Check "m19c_backend_ir_accepts_metadata" ($irModel -match 'case "UI_OBJECT"' -and $irModel -match 'case "UI_SET"') "backend strict IR accepts UI metadata"
Emit-Check "m19c_spec_present" (Test-Path $specPath) "ui_objects spec present"
Emit-Check "m19c_spec_lists_tests" ($spec -match 'VALID_TEST' -and $spec -match 'INVALID_TEST') "spec lists valid and invalid tests"
Emit-Check "m19c_tests_present" (Test-Path $expectedPath) "ui_objects expected.txt present"

$validCount = if (Test-Path $testRoot) { @(Get-ChildItem $testRoot -Filter 'valid_*.arq' -File).Count } else { 0 }
$invalidCount = if (Test-Path $testRoot) { @(Get-ChildItem $testRoot -Filter 'invalid_*.arq' -File).Count } else { 0 }
Emit-Check "m19c_valid_test_count" ($validCount -ge 5) "valid=$validCount"
Emit-Check "m19c_invalid_test_count" ($invalidCount -ge 10) "invalid=$invalidCount"
Emit-Check "m19c_ir_doc_mentions_ui" ($irDoc -match 'UI_OBJECT' -and $irDoc -match 'UI_SET') "IR doc mentions UI metadata"

if ($failed) { exit 1 }
exit 0
