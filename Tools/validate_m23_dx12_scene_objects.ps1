param(
    [string]$RepoRoot = "",
    [switch]$SkipCompileLower
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m23_dx12_scene_objects_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Emit-Check { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

$docsPath = Join-Path $RepoRoot "Docs\M23_DX12_REAL_SCENE_OBJECTS.md"
$handoffPath = Join-Path $RepoRoot "Docs\M23_HANDOFF.md"
$toolMapPath = Join-Path $RepoRoot "Docs\TOOL_MAP.md"
$specPath = Join-Path $RepoRoot "Specs\Commands\dx12.command.txt"
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_multi_object_scene_m23c.arq"
$explicitSamplePath = Join-Path $RepoRoot "Samples\DX12\dx12_explicit_multi_draw_m23c.arq"
$wrapperPath = Join-Path $RepoRoot "Tools\build_m23c_dx12_multi_object_scene.ps1"
$parserPath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Dx12.cs"
$modelsPath = Join-Path $RepoRoot "Tools\M10GDriver\Core\Models.cs"
$astPath = Join-Path $RepoRoot "Tools\M10GDriver\Frontend\AstEmit.cs"
$irPath = Join-Path $RepoRoot "Tools\M10GDriver\Frontend\IrEmit.cs"
$lowererPath = Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1"
$runtimeCppPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp"
$runtimeHeaderPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.h"
$nativeHelperPath = Join-Path $RepoRoot "Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1"
$expectedPath = Join-Path $RepoRoot "Tests\CommandTests\dx12\expected.txt"
$capPath = Join-Path $RepoRoot "Backends\WindowsX64PE\Config\capabilities_v0.txt"

$docs = Read-TextSafe $docsPath
$handoff = Read-TextSafe $handoffPath
$toolMap = Read-TextSafe $toolMapPath
$spec = Read-TextSafe $specPath
$sample = Read-TextSafe $samplePath
$explicitSample = Read-TextSafe $explicitSamplePath
$wrapper = Read-TextSafe $wrapperPath
$parser = Read-TextSafe $parserPath
$models = Read-TextSafe $modelsPath
$ast = Read-TextSafe $astPath
$ir = Read-TextSafe $irPath
$lowerer = Read-TextSafe $lowererPath
$runtimeCpp = Read-TextSafe $runtimeCppPath
$runtimeHeader = Read-TextSafe $runtimeHeaderPath
$nativeHelper = Read-TextSafe $nativeHelperPath
$expected = Read-TextSafe $expectedPath
$cap = Read-TextSafe $capPath

Emit-Check "m23a_docs_syntax" ((Test-Path $docsPath) -and $docs.Contains('define object called "CrystalA"') -and $docs.Contains('draw "CrystalA"') -and $docs.Contains('M23A')) "M23A object syntax documented"
Emit-Check "m23b_models_ast_ir" ($models.Contains('record Dx12Object') -and $models.Contains('record Dx12ObjectBinding') -and $models.Contains('record Dx12DrawObject') -and $ast.Contains('DX12_OBJECT|') -and $ast.Contains('DX12_OBJECT_BIND|') -and $ast.Contains('DX12_DRAW_OBJECT|') -and $ir.Contains('DX12_OBJECT|') -and $ir.Contains('DX12_OBJECT_BIND|') -and $ir.Contains('DX12_DRAW_OBJECT|')) "real object metadata models and AST/IR emission present"
Emit-Check "m23b_parser_object_syntax" ($parser.Contains('ParseDx12ObjectDefinitionStatement') -and $parser.Contains('ParseDx12ObjectRendererUseStatement') -and $parser.Contains('BindDx12ObjectPipeline') -and $parser.Contains('BindDx12ObjectVertexBuffer') -and $parser.Contains('ResolveAndAddDx12ObjectDraw')) "parser supports object definition, binding, and draw by name"
Emit-Check "m23c_parser_explicit_multidraw" ($parser.Contains('draw 3 vertices') -or ($parser.Contains('Expected buffer after from') -and $parser.Contains('Expected pipeline after with') -and $parser.Contains('Expected renderer after using'))) "parser supports explicit multi-draw public syntax"
Emit-Check "m23c_samples" ((Test-Path $samplePath) -and (Test-Path $explicitSamplePath) -and $sample.Contains('define object called "CrystalA"') -and $sample.Contains('draw "CrystalA"') -and $explicitSample.Contains('draw 3 vertices from buffer')) "official object and explicit multi-draw samples present"
Emit-Check "m23c_lowerer_markers" ($lowerer.Contains('DX12_DRAW_OBJECT') -and $lowerer.Contains('ARQEN_M23_DRAW_CALL_DATA') -and $lowerer.Contains('M23_DRAW_CALLS|') -and $lowerer.Contains('native_m23_scene_multi_draw')) "lowerer consumes object draw metadata and emits M23 config/manifest"
Emit-Check "m23c_runtime_draw_calls" ($runtimeHeader.Contains('struct ArqenDx12DrawCall') -and $runtimeCpp.Contains('drawCallCount_') -and $runtimeCpp.Contains('DrawInstanced(drawCalls_[i].vertexCount') -and $nativeHelper.Contains('ARQEN_M23_DRAW_CALL_DATA')) "native runtime supports generated draw-call table"
Emit-Check "m23_tests_expected" ($expected.Contains('valid_dx12_object_draw_metadata.arq') -and $expected.Contains('valid_dx12_explicit_multi_draw_metadata.arq') -and $expected.Contains('invalid_dx12_object_duplicate.arq') -and $expected.Contains('invalid_dx12_object_unknown_draw.arq')) "M23 command tests listed in expected.txt"
Emit-Check "m23_docs_tool_map_spec" ($handoff.Contains('M23C') -and $toolMap.Contains('build_m23c_dx12_multi_object_scene.ps1') -and $toolMap.Contains('validate_m23_dx12_scene_objects.ps1') -and $spec.Contains('M23C_OBJECT_DRAW_SYNTAX')) "handoff/tool map/spec document M23"

if ($SkipCompileLower) {
    Emit-Check "m23c_wrapper_compiles_lowers_scene" $true "skipped by request"
} else {
    $buildOk = $false
    $buildNote = "not run"
    try {
        & $wrapperPath -RepoRoot $RepoRoot -SourcePath $samplePath -OutDir (Join-Path $RepoRoot "Build\M23C") -FrameCount 60 -TargetFps 30 -HoldMilliseconds 2000 -Quiet
        $manifestPath = Join-Path $RepoRoot "Build\M23C\dx12_clear_manifest.generated.txt"
        $configPath = Join-Path $RepoRoot "Build\M23C\dx12_clear_config.generated.h"
        $manifest = Read-TextSafe $manifestPath
        $config = Read-TextSafe $configPath
        $buildOk = ($manifest.Contains('M23_SCENE_OBJECTS|5') -and $manifest.Contains('M23_DRAW_CALLS|5') -and $manifest.Contains('M23_OBJECT_MODE|True') -and $manifest.Contains('TRIANGLE_MODE|native_m23_scene_multi_draw') -and $manifest.Contains('DRAW_CALL_4|object=CrystalE') -and $config.Contains('ARQEN_M23_MULTI_DRAW_ENABLED 1') -and $config.Contains('ARQEN_M23_DRAW_CALL_COUNT 5'))
        $buildNote = "manifest/config checked"
    } catch {
        $buildOk = $false
        $buildNote = $_.Exception.Message
    }
    Emit-Check "m23c_wrapper_compiles_lowers_scene" $buildOk $buildNote
}

Emit-Check "m23_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported in main backend"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
