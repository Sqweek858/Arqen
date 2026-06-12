param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m20b_dx12_syntax_contract_validation.txt"
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Emit-Check {
    param([string]$Name, [bool]$Ok, [string]$Message)
    if ($Ok) {
        $script:lines.Add("PASS|$Name|$Message") | Out-Null
        Write-Host "PASS|$Name|$Message"
    } else {
        $script:failed = $true
        $script:lines.Add("FAIL|$Name|$Message") | Out-Null
        Write-Host "FAIL|$Name|$Message"
    }
}
function Read-TextSafe {
    param([string]$Path)
    if (Test-Path $Path) { return [System.IO.File]::ReadAllText($Path) }
    return ""
}

$corePath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Core.cs"
$dx12ParserPath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Dx12.cs"
$modelsPath = Join-Path $RepoRoot "Tools\M10GDriver\Core\Models.cs"
$astPath = Join-Path $RepoRoot "Tools\M10GDriver\Frontend\AstEmit.cs"
$irEmitPath = Join-Path $RepoRoot "Tools\M10GDriver\Frontend\IrEmit.cs"
$irModelPath = Join-Path $RepoRoot "Tools\M10GDriver\Backend\IrModel.cs"
$specPath = Join-Path $RepoRoot "Specs\Commands\dx12.command.txt"
$miniBiblePath = Join-Path $RepoRoot "Docs\M20_DX12_MINI_BIBLE.md"
$m20Path = Join-Path $RepoRoot "Docs\M20_HANDOFF.md"
$dx12ContractPath = Join-Path $RepoRoot "Backends\DX12\DX12_BACKEND_CONTRACT.md"
$irDocPath = Join-Path $RepoRoot "IR\ARQIR_V0_CONTRACT.md"
$runtimeDocPath = Join-Path $RepoRoot "Runtime\RUNTIME_CONTRACT.md"
$capPath = Join-Path $RepoRoot "Backends\WindowsX64PE\Config\capabilities_v0.txt"
$testRoot = Join-Path $RepoRoot "Tests\CommandTests\dx12"
$expectedPath = Join-Path $testRoot "expected.txt"

$core = Read-TextSafe $corePath
$parser = Read-TextSafe $dx12ParserPath
$models = Read-TextSafe $modelsPath
$ast = Read-TextSafe $astPath
$irEmit = Read-TextSafe $irEmitPath
$irModel = Read-TextSafe $irModelPath
$spec = Read-TextSafe $specPath
$miniBible = Read-TextSafe $miniBiblePath
$m20 = Read-TextSafe $m20Path
$dx12Contract = Read-TextSafe $dx12ContractPath
$irDoc = Read-TextSafe $irDocPath
$runtimeDoc = Read-TextSafe $runtimeDocPath
$cap = Read-TextSafe $capPath

Emit-Check "m20b_dx12_parser_exists" (Test-Path $dx12ParserPath) "Parser.Dx12.cs present"
Emit-Check "m20b_dx12_dispatch_present" ($core -match 'ParseDx12RendererDefinitionStatement' -and $core -match 'ParseDx12RendererParentStatement') "parser dispatch has define/parent renderer"
Emit-Check "m20b_dx12_models_present" ($models -match 'record Dx12Renderer' -and $models -match 'record Dx12RendererParent') "dx12 model records present"
Emit-Check "m20b_dx12_parser_syntax" ($parser -match 'define' -and $parser -match 'dx12' -and $parser -match 'renderer' -and $parser -match 'parent' -and $parser -match 'window') "parser recognizes public M20B syntax"
Emit-Check "m20b_dx12_semantics" ($parser -match 'Duplicate DX12 renderer' -and $parser -match 'Unknown DX12 renderer' -and $parser -match 'already has a parent window') "semantic guards present"
Emit-Check "m20b_dx12_ast_lines" ($ast -match 'DX12_RENDERER' -and $ast -match 'DX12_PARENT') "AST emits DX12 metadata"
Emit-Check "m20b_dx12_ir_lines" ($irEmit -match 'DX12_RENDERER' -and $irEmit -match 'DX12_PARENT') "IR emits DX12 metadata"
Emit-Check "m20b_dx12_strict_ir" ($irModel -match 'case "DX12_RENDERER"' -and $irModel -match 'case "DX12_PARENT"') "strict IR accepts DX12 metadata"
Emit-Check "m20b_dx12_spec_present" (Test-Path $specPath) "dx12 command spec present"
Emit-Check "m20b_dx12_spec_parent_keyword" ($spec -match 'parent renderer' -and -not ($spec -match 'attach renderer')) "spec uses parent renderer, not attach renderer"
Emit-Check "m20b_dx12_style_clear_rule" ($spec -match 'STYLE_RULE' -and $miniBible -match 'background color' -and $miniBible -match 'not add this command') "clear/background color uses style path"
Emit-Check "m20b_dx12_docs_present" ((Test-Path $miniBiblePath) -and $m20 -match 'M20B DX12 renderer metadata syntax' -and $dx12Contract -match 'M20B public syntax reservation') "M20B docs present"
Emit-Check "m20b_dx12_ir_doc_present" ($irDoc -match 'M20B DX12 renderer metadata' -and $irDoc -match 'DX12_RENDERER' -and $irDoc -match 'DX12_PARENT') "IR doc mentions metadata"
Emit-Check "m20b_dx12_runtime_boundary" ($runtimeDoc -match 'M20B DX12 renderer metadata boundary' -and $runtimeDoc -match 'does not add runtime actions') "runtime doc keeps metadata-only boundary"
Emit-Check "m20b_dx12_tests_present" (Test-Path $expectedPath) "dx12 expected.txt present"

$validCount = if (Test-Path $testRoot) { @(Get-ChildItem $testRoot -Filter 'valid_*.arq' -File).Count } else { 0 }
$invalidCount = if (Test-Path $testRoot) { @(Get-ChildItem $testRoot -Filter 'invalid_*.arq' -File).Count } else { 0 }
Emit-Check "m20b_dx12_valid_test_count" ($validCount -ge 3) "valid=$validCount"
Emit-Check "m20b_dx12_invalid_test_count" ($invalidCount -ge 6) "invalid=$invalidCount"
Emit-Check "m20b_dx12_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 action families still unsupported"

[System.IO.File]::WriteAllLines($outPath, $lines.ToArray(), [System.Text.UTF8Encoding]::new($false))
if ($failed) { exit 1 }
exit 0
