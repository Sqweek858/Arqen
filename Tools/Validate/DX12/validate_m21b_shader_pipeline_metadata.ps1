param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m21b_shader_pipeline_metadata_validation.txt"
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
$expectedPath = Join-Path $RepoRoot "Tests\CommandTests\dx12\expected.txt"
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_shader_pipeline_m21b.arq"
$toolMapPath = Join-Path $RepoRoot "Docs\Info\TOOLS.md"
$capPath = Join-Path $RepoRoot "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt"

$models = Read-TextSafe $modelsPath
$core = Read-TextSafe $corePath
$dx12Parser = Read-TextSafe $dx12ParserPath
$ast = Read-TextSafe $astPath
$irEmit = Read-TextSafe $irEmitPath
$irModel = Read-TextSafe $irModelPath
$expected = Read-TextSafe $expectedPath
$sample = Read-TextSafe $samplePath
$toolMap = Read-TextSafe $toolMapPath
$cap = Read-TextSafe $capPath

Emit-Check "m21b_models_present" ($models -match 'record Dx12Shader' -and $models -match 'record Dx12Pipeline' -and $models -match 'record Dx12PipelineBind') "shader/pipeline/bind models present"
Emit-Check "m21b_parser_rules_wired" ($core -match 'ParseDx12ShaderDefinitionStatement' -and $core -match 'ParseDx12PipelineDefinitionStatement' -and $core -match 'ParseDx12PipelineUseStatement') "parser rules wired"
Emit-Check "m21b_parser_semantics" ($dx12Parser -match 'vertex source file' -and $dx12Parser -match 'triangle list' -and $dx12Parser -match 'already has a pipeline binding') "shader/pipeline semantics present"
Emit-Check "m21b_ast_ir_emit" ($ast -match 'DX12_SHADER' -and $ast -match 'DX12_PIPELINE_BIND' -and $irEmit -match 'Dx12ShaderIrLine' -and $irEmit -match 'Dx12PipelineBindIrLine') "AST/IR emit shader pipeline metadata"
Emit-Check "m21b_strict_ir_accepts_metadata" ($irModel -match 'case "DX12_SHADER"' -and $irModel -match 'case "DX12_PIPELINE"' -and $irModel -match 'case "DX12_PIPELINE_BIND"') "strict IR accepts M21 metadata"
Emit-Check "m21b_sample_exists" ((Test-Path $samplePath) -and $sample.Contains('define shader called "TriangleShader"') -and $sample.Contains('use pipeline "TrianglePipeline"')) "M21B sample present"

$validCount = 0
$invalidCount = 0
if (Test-Path $expectedPath) {
    $entries = @(Get-Content $expectedPath | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") })
    $validCount = @($entries | Where-Object { $_ -match '^valid_dx12_(shader|pipeline)' }).Count
    $invalidCount = @($entries | Where-Object { $_ -match '^invalid_dx12_(shader|pipeline)' }).Count
}
Emit-Check "m21b_valid_test_count" ($validCount -ge 4) "valid=$validCount"
Emit-Check "m21b_invalid_test_count" ($invalidCount -ge 13) "invalid=$invalidCount"
Emit-Check "m21b_expected_error_codes" ($expected -match 'invalid_dx12_shader_missing_vertex.*S282' -and $expected -match 'invalid_dx12_pipeline_bind_renderer_mismatch.*S286') "expected invalid cases include shader/pipeline errors"
Emit-Check "m21b_tool_map" ($toolMap -match 'validate_m21a_shader_pipeline_bible\.ps1' -and $toolMap -match 'validate_m21b_shader_pipeline_metadata\.ps1') "tool map documents M21 validators"
Emit-Check "m21b_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
