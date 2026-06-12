param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m21c_vertex_draw_metadata_validation.txt"
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
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_first_triangle_m21d.arq"
$miniBiblePath = Join-Path $RepoRoot "Docs\M21_SHADER_PIPELINE_MINI_BIBLE.md"
$capPath = Join-Path $RepoRoot "Backends\WindowsX64PE\Config\capabilities_v0.txt"

$models = Read-TextSafe $modelsPath
$core = Read-TextSafe $corePath
$dx12Parser = Read-TextSafe $dx12ParserPath
$ast = Read-TextSafe $astPath
$irEmit = Read-TextSafe $irEmitPath
$irModel = Read-TextSafe $irModelPath
$expected = Read-TextSafe $expectedPath
$sample = Read-TextSafe $samplePath
$miniBible = Read-TextSafe $miniBiblePath
$cap = Read-TextSafe $capPath

Emit-Check "m21c_models_present" ($models -match 'record Dx12VertexBuffer' -and $models -match 'record Dx12Vertex\(' -and $models -match 'record Dx12VertexBufferBind' -and $models -match 'record Dx12Draw') "vertex/draw models present"
Emit-Check "m21c_parser_rules_wired" ($core -match 'ParseDx12VertexBufferDefinitionStatement' -and $core -match 'ParseDx12VertexBufferUseStatement' -and $core -match 'ParseDx12DrawStatement') "parser rules wired"
Emit-Check "m21c_parser_semantics" ($dx12Parser -match 'position must be a vec3' -and $dx12Parser -match 'color must be a vec4' -and $dx12Parser -match 'must have a pipeline binding before draw' -and $dx12Parser -match 'must have a vertex buffer binding before draw') "vertex/draw semantics present"
Emit-Check "m21c_ast_ir_emit" ($ast -match 'DX12_VERTEX_BUFFER' -and $ast -match 'DX12_DRAW' -and $irEmit -match 'Dx12VertexBufferIrLine' -and $irEmit -match 'Dx12DrawIrLine') "AST/IR emit vertex/draw metadata"
Emit-Check "m21c_strict_ir_accepts_metadata" ($irModel -match 'case "DX12_VERTEX_BUFFER"' -and $irModel -match 'case "DX12_VERTEX"' -and $irModel -match 'case "DX12_VERTEX_BUFFER_BIND"' -and $irModel -match 'case "DX12_DRAW"') "strict IR accepts M21C metadata"
Emit-Check "m21c_sample_exists" ((Test-Path $samplePath) -and $sample.Contains('define vertex buffer called "TriangleVertices"') -and $sample.Contains('draw 3 vertices with renderer "MainRenderer"')) "M21D sample includes M21C syntax"

$validCount = 0
$invalidCount = 0
if (Test-Path $expectedPath) {
    $entries = @(Get-Content $expectedPath | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") })
    $validCount = @($entries | Where-Object { $_ -match '^valid_dx12_(vertex|first_triangle)' }).Count
    $invalidCount = @($entries | Where-Object { $_ -match '^invalid_dx12_(vertex|draw)' }).Count
}
Emit-Check "m21c_valid_test_count" ($validCount -ge 4) "valid=$validCount"
Emit-Check "m21c_invalid_test_count" ($invalidCount -ge 15) "invalid=$invalidCount"
Emit-Check "m21c_expected_error_codes" ($expected -match 'invalid_dx12_vertex_position_vec2.*S288' -and $expected -match 'invalid_dx12_draw_without_pipeline.*S293') "expected invalid cases include vertex/draw errors"
Emit-Check "m21c_docs_present" ($miniBible -match 'M21C implemented' -and $miniBible -match 'DX12_VERTEX_BUFFER' -and $miniBible -match 'DX12_DRAW') "M21C docs present"
Emit-Check "m21c_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
