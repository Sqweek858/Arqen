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

$lexerPath = Join-Path $RepoRoot "Tools/M10GDriver/Frontend/Lexer.cs"
$corePath = Join-Path $RepoRoot "Tools/M10GDriver/Parser/Parser.Core.cs"
$styleParserPath = Join-Path $RepoRoot "Tools/M10GDriver/Parser/Parser.Style.cs"
$astPath = Join-Path $RepoRoot "Tools/M10GDriver/Frontend/AstEmit.cs"
$irPath = Join-Path $RepoRoot "Tools/M10GDriver/Frontend/IrEmit.cs"
$irModelPath = Join-Path $RepoRoot "Tools/M10GDriver/Backend/IrModel.cs"
$specPath = Join-Path $RepoRoot "Specs/Commands/style.command.txt"
$testPath = Join-Path $RepoRoot "Tests/CommandTests/style"
$irDocPath = Join-Path $RepoRoot "IR/ARQIR_V0_CONTRACT.md"
$runtimeDocPath = Join-Path $RepoRoot "Runtime/RUNTIME_CONTRACT.md"

$lexerText = Read-TextSafe $lexerPath
$coreText = Read-TextSafe $corePath
$styleText = Read-TextSafe $styleParserPath
$astText = Read-TextSafe $astPath
$irText = Read-TextSafe $irPath
$irModelText = Read-TextSafe $irModelPath
$irDocText = Read-TextSafe $irDocPath
$runtimeDocText = Read-TextSafe $runtimeDocPath

Emit-Check "m19b_style_parser_present" (Test-Path $styleParserPath) "Parser.Style.cs present"
Emit-Check "m19b_style_dispatch_present" ($coreText -match 'ParseStyleStatement' -and $coreText -match 'with' -and $coreText -match 'style') "statement dispatch knows with style for"
Emit-Check "m19b_style_colon_token" ($lexerText -match 'COLON') "lexer emits COLON for property syntax"
Emit-Check "m19b_style_structural_keywords" ($lexerText -match '"with"' -and $lexerText -match '"style"' -and $lexerText -match '"for"') "style structural keywords are lexed"
Emit-Check "m19b_style_soft_words" ($styleText -match 'ExpectStyleWord' -and $styleText -match 'CurrentWordIs\("px"\)' -and $styleText -match 'CurrentWordIs\("ms"\)') "style property/value words are parsed as soft words"
Emit-Check "m19b_style_state_validation" ($styleText -match 'StyleStates' -and $styleText -match 'hovered' -and $styleText -match 'pressed' -and $styleText -match 'disabled' -and $styleText -match 'selected' -and $styleText -match 'loading' -and $styleText -match 'error' -and $styleText -match 'success' -and $styleText -match 'dragged') "default, component, and status state whitelist present"
Emit-Check "m19b_style_property_validation" ($styleText -match 'StyleProperties' -and $styleText -match 'clip children' -and $styleText -match 'background color' -and $styleText -match 'corner radius' -and $styleText -match 'shadow blur' -and $styleText -match 'transition duration' -and $styleText -match 'font weight' -and $styleText -match 'min width' -and $styleText -match 'pointer events' -and $styleText -match 'translate y' -and $styleText -match 'transition property') "core, extended, and style++ property whitelist present"
Emit-Check "m19b_style_value_validation" ($styleText -match 'ParseStyleOpacityValue' -and $styleText -match 'ParseStyleDimensionValue' -and $styleText -match 'ParseStyleSignedDimensionValue' -and $styleText -match 'ParseStyleColorValue' -and $styleText -match 'ParseStyleDurationValue' -and $styleText -match 'ParseStyleIntegerValue' -and $styleText -match 'ParseStyleFontWeightValue' -and $styleText -match 'ParseStyleAngleValue') "typed style values validated"
Emit-Check "m19b_style_ast_emitted" ($astText -match 'STYLE\|target=' -and $astText -match 'AstStyleLines' -and $astText -match 'STYLE_PRESET\|name=' -and $astText -match 'STYLE_APPLY\|style=') "AST dumps STYLE, STYLE_PRESET, and STYLE_APPLY metadata"
Emit-Check "m19b_style_ir_emitted" ($irText -match 'STYLE\|target=' -and $irText -match 'StyleIrLine' -and $irText -match 'STYLE_PRESET\|name=' -and $irText -match 'STYLE_APPLY\|style=') "IR emits style metadata lines"
Emit-Check "m19b_style_ir_parser_accepts_metadata" ($irModelText -match 'case "STYLE"' -and $irModelText -match 'case "STYLE_PRESET"' -and $irModelText -match 'case "STYLE_APPLY"' -and $irModelText -match 'Malformed STYLE') "backend IR parser accepts style metadata"
Emit-Check "m19b_style_spec_present" (Test-Path $specPath) "style command spec present"
$specText = Read-TextSafe $specPath
Emit-Check "m19b_style_spec_extended_properties" ($specText -match 'SUPPORTED_PROPERTIES' -and $specText -match 'shadow opacity' -and $specText -match 'transition easing' -and $specText -match 'z index' -and $specText -match 'use style' -and $specText -match 'min width' -and $specText -match 'transition property') "style spec documents style++ properties and presets"
Emit-Check "m19b_style_tests_present" (Test-Path $testPath) "style test folder present"

$validCount = if (Test-Path $testPath) { @(Get-ChildItem $testPath -Filter "valid_*.arq" -File).Count } else { 0 }
$invalidCount = if (Test-Path $testPath) { @(Get-ChildItem $testPath -Filter "invalid_*.arq" -File).Count } else { 0 }
Emit-Check "m19b_style_valid_test_count" ($validCount -ge 15) "valid=$validCount"
Emit-Check "m19b_style_invalid_test_count" ($invalidCount -ge 31) "invalid=$invalidCount"
Emit-Check "m19b_style_ir_doc" ($irDocText -match 'STYLE\|target=' -and $irDocText -match 'STYLE_PRESET\|name=' -and $irDocText -match 'STYLE_APPLY\|style=' -and $irDocText -match 'metadata, not executable backend actions') "IR contract documents style metadata"
Emit-Check "m19b_style_runtime_doc" ($runtimeDocText -match 'M19B style/design boundary' -and $runtimeDocText -match 'style presets' -and $runtimeDocText -match 'not runtime actions yet') "runtime contract keeps style out of runtime actions"

if ($failed) { exit 1 }
exit 0
