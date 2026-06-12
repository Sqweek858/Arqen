param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m21g_constant_buffer_metadata_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Emit-Check { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

$modelsPath = Join-Path $RepoRoot "Tools\M10GDriver\Core\Models.cs"
$corePath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Core.cs"
$dx12ParserPath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Dx12.cs"
$astPath = Join-Path $RepoRoot "Tools\M10GDriver\Frontend\AstEmit.cs"
$irEmitPath = Join-Path $RepoRoot "Tools\M10GDriver\Frontend\IrEmit.cs"
$irModelPath = Join-Path $RepoRoot "Tools\M10GDriver\Backend\IrModel.cs"
$lowererPath = Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1"
$headerPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.h"
$cppPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp"
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_animated_triangle_m21h.arq"
$docsPath = Join-Path $RepoRoot "Docs\M21G_M21H_CONSTANT_COLOR_ANIMATION.md"
$toolMapPath = Join-Path $RepoRoot "Docs\TOOL_MAP.md"
$capPath = Join-Path $RepoRoot "Backends\WindowsX64PE\Config\capabilities_v0.txt"

$models = Read-TextSafe $modelsPath
$core = Read-TextSafe $corePath
$parser = Read-TextSafe $dx12ParserPath
$ast = Read-TextSafe $astPath
$irEmit = Read-TextSafe $irEmitPath
$irModel = Read-TextSafe $irModelPath
$lowerer = Read-TextSafe $lowererPath
$header = Read-TextSafe $headerPath
$cpp = Read-TextSafe $cppPath
$sample = Read-TextSafe $samplePath
$docs = Read-TextSafe $docsPath
$toolMap = Read-TextSafe $toolMapPath
$cap = Read-TextSafe $capPath

Emit-Check "m21g_models_present" ($models.Contains('Dx12ConstantBuffer') -and $models.Contains('Dx12ConstantBufferBind')) "constant buffer AST models present"
Emit-Check "m21g_parser_rules_present" ($core.Contains('ParseDx12ConstantBufferDefinitionStatement') -and $core.Contains('ParseDx12ConstantBufferUseStatement') -and $parser.Contains('Expected constant after define') -and $parser.Contains('Expected buffer after constant')) "parser has constant buffer syntax"
Emit-Check "m21g_ir_emit_present" ($ast.Contains('DX12_CONSTANT_BUFFER') -and $irEmit.Contains('Dx12ConstantBufferIrLine') -and $irModel.Contains('DX12_CONSTANT_BUFFER_BIND')) "AST/IR strict model includes constant buffer metadata"
Emit-Check "m21g_lowerer_runtime_markers" ($lowerer.Contains('DX12_CONSTANT_BUFFER') -and $lowerer.Contains('ARQEN_M21G_TINT_ENABLED') -and $lowerer.Contains('ARQEN_M21G_TINT_COLOR')) "lowerer emits tint config macros"
Emit-Check "m21g_native_tint_path" ($header.Contains('enableTint') -and $cpp.Contains('SetGraphicsRootConstantBufferView') -and $cpp.Contains('UpdateTintBuffer')) "native bridge accepts tint constant buffer"
Emit-Check "m21g_sample_uses_constant_buffer" ($sample.Contains('define constant buffer called "TriangleParams"') -and $sample.Contains('use constant buffer "TriangleParams" for pipeline "TrianglePipeline"')) "sample uses constant buffer"
Emit-Check "m21g_docs_tooling" ($docs -match 'constant buffer' -and $docs -match 'TriangleParams' -and $toolMap -match 'validate_m21g_constant_buffer_metadata\.ps1') "docs/tool map document M21G"
Emit-Check "m21g_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
