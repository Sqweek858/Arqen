param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$outPath = Join-Path $RepoRoot "Build\Generated\m27d_m28a_dx12_window_style_box_validation.txt"
New-Item -ItemType Directory -Force -Path (Split-Path $outPath -Parent) | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Read-All([string]$Path) {
    if (-not (Test-Path $Path)) { return "" }
    return Get-Content $Path -Raw
}
function Emit-Check([string]$Name, [bool]$Ok, [string]$Message) {
    $status = if ($Ok) { "PASS" } else { "FAIL" }
    $script:lines.Add("$status|$Name|$Message") | Out-Null
    Write-Host "$status|$Name|$Message"
    if (-not $Ok) { $script:failed = $true }
}

$models = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Core\Models.cs")
$core = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Core.cs")
$parser = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Dx12.cs")
$styleParser = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Style.cs")
$ast = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Frontend\AstEmit.cs")
$ir = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Frontend\IrEmit.cs")
$strict = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Backend\IrModel.cs")
$backendDriver = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Backend\BackendDriver.cs")
$capabilities = Read-All (Join-Path $RepoRoot "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt")
$runtimeRegistryTool = Read-All (Join-Path $RepoRoot "Tools\Generate\generate_runtime_action_registry.ps1")
$lowerer = Read-All (Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1")
$nativeBuilder = Read-All (Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1")
$wrapper = Read-All (Join-Path $RepoRoot "Tools\Build\DX12\build_m28a_dx12_window_style_box_scene.ps1")
$validator = Read-All (Join-Path $RepoRoot "Tools\Validate\DX12\validate_m27d_m28a_dx12_window_style_box.ps1")
$expected = Read-All (Join-Path $RepoRoot "Tests\CommandTests\dx12\expected.txt")
$toolMap = Read-All (Join-Path $RepoRoot "Docs\Info\TOOLS.md")
$milestones = Read-All (Join-Path $RepoRoot "Docs\MILESTONES.md")
$docs = Read-All (Join-Path $RepoRoot "Docs\Milestones\\M26_M30.md")
$handoff = Read-All (Join-Path $RepoRoot "Docs\Milestones\\M26_M30.md")
$sampleReadme = Read-All (Join-Path $RepoRoot "Samples\README.md")
$spec = Read-All (Join-Path $RepoRoot "Tests\CommandTests\misc\dx12.command.txt")
$registry = Read-All (Join-Path $RepoRoot "Docs\Language\LANGUAGE.md")
$irContract = Read-All (Join-Path $RepoRoot "Docs\Reference\IR\ARQIR_V0_CONTRACT.md")
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_window_style_box_scene_m28a.arq"
$sample = Read-All $samplePath

Emit-Check "m27d_style_parser_contract" ($styleParser.Contains('title bar color') -and $styleParser.Contains('title text color') -and $styleParser.Contains('RegisterNativeWindowStyleProperty') -and $styleParser.Contains('window_style_title_bar_color') -and $styleParser.Contains('window_style_title_text_color') -and $styleParser.Contains('S370') -and $styleParser.Contains('S372')) "M27D native window style parser contract is present and strict"
Emit-Check "m27d_lowerer_native_window_markers" ($lowerer.Contains('window_style_title_bar_color') -and $lowerer.Contains('M27D_NATIVE_WINDOW_STYLE') -and $lowerer.Contains('ARQEN_M27D_TITLE_BAR_ENABLED') -and $nativeBuilder.Contains('DwmSetWindowAttribute') -and $nativeBuilder.Contains('DWMWA_CAPTION_COLOR') -and $nativeBuilder.Contains('DWMWA_TEXT_COLOR') -and $nativeBuilder.Contains('dwmapi.lib')) "M27D lowerer/native builder emits DWM title bar style markers"
Emit-Check "m27d_backend_actions_supported" ($backendDriver.Contains('"window_style_title_bar_color"') -and $backendDriver.Contains('"window_style_title_text_color"') -and $capabilities.Contains('window_style_title_bar_color|supported') -and $capabilities.Contains('window_style_title_text_color|supported') -and $runtimeRegistryTool.Contains('"window_style_title_bar_color"') -and $runtimeRegistryTool.Contains('"window_style_title_text_color"')) "M27D window style runtime actions are accepted by backend capability gates"
Emit-Check "m28a_models_ast_ir" ($models.Contains('record Dx12ObjectPrimitive') -and $models.Contains('Dx12ObjectPrimitives') -and $ast.Contains('DX12_OBJECT_PRIMITIVE|') -and $ir.Contains('DX12_OBJECT_PRIMITIVE|') -and $strict.Contains('DX12_OBJECT_PRIMITIVE')) "M28A box primitive metadata model/AST/IR/strict IR present"
Emit-Check "m28a_parser_box_contract" ($core.Contains('ParseDx12BoxPrimitiveDefinitionStatement') -and $parser.Contains('Expected box after define') -and $parser.Contains('DX12 box object name') -and $parser.Contains('generated 36-vertex draw count') -and $parser.Contains('S381')) "M28A parser recognizes define box and blocks manual primitive vertex data"
Emit-Check "m27d_m28a_command_tests" ($expected.Contains('valid_dx12_window_style_titlebar_metadata.arq') -and $expected.Contains('invalid_dx12_window_style_unknown_target.arq') -and $expected.Contains('invalid_dx12_window_style_named_color.arq') -and $expected.Contains('valid_dx12_box_primitive_metadata.arq') -and $expected.Contains('invalid_dx12_box_duplicate_object.arq') -and $expected.Contains('invalid_dx12_box_unknown_draw.arq') -and $expected.Contains('invalid_dx12_box_manual_vertex_buffer.arq')) "M27D/M28A positive and negative command tests are listed"
Emit-Check "m27d_m28a_sample_exists" ((Test-Path $samplePath) -and $sample.Contains('with style for "MainWindow"') -and $sample.Contains('title bar color: color "#000000"') -and $sample.Contains('define box called "CubeA"') -and $sample.Contains('define box called "CubeB"') -and $sample.Contains('set camera "MainCamera" projection to perspective') -and $sample.Contains('draw "CubeA"') -and $sample.Contains('draw "CubeB"')) "official M27D/M28A window style + box sample present"
Emit-Check "m28a_lowerer_box_generation" ($lowerer.Contains('New-M28BoxPrimitiveVertices') -and $lowerer.Contains('__arqen_m28_box_') -and $lowerer.Contains('M28_BOX_PRIMITIVE|') -and $lowerer.Contains('ARQEN_M28_BOX_PRIMITIVE_ENABLED') -and $lowerer.Contains('OBJECT_PRIMITIVE|object=')) "lowerer generates M28A box vertices and manifest/config markers"
Emit-Check "m27d_m28a_wrapper" ($wrapper.Contains('dx12_window_style_box_scene_m28a.arq') -and $wrapper.Contains('M27D_NATIVE_WINDOW_STYLE|True') -and $wrapper.Contains('M28_BOX_PRIMITIVE|True') -and $wrapper.Contains('m28a_dx12_window_style_box_scene.exe')) "M28A wrapper validates compile/lower/native build markers"
Emit-Check "m27d_m28a_docs_spec_toolmap" ($docs.Contains('M27D') -and $docs.Contains('M28A') -and $handoff.Contains('build_m28a_dx12_window_style_box_scene.ps1') -and $toolMap.Contains('validate_m27d_m28a_dx12_window_style_box.ps1') -and $milestones.Contains('M28A') -and $sampleReadme.Contains('dx12_window_style_box_scene_m28a.arq') -and $spec.Contains('M27D_NATIVE_WINDOW_STYLE_SYNTAX') -and $spec.Contains('M28A_BOX_PRIMITIVE_SYNTAX') -and $registry.Contains('define box called') -and $irContract.Contains('DX12_OBJECT_PRIMITIVE')) "docs/spec/tool map/sample README/IR contract document M27D/M28A contracts"
Emit-Check "m27d_m28a_future_scope_blocked" ($docs.Contains('No custom title bar') -and $docs.Contains('No lighting') -and $docs.Contains('No mesh import') -and $docs.Contains('No scene graph')) "M27D/M28A explicitly avoid larger rendering/UI families"

$wrapperPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m28a_dx12_window_style_box_scene.ps1"
if (Test-Path $wrapperPath) {
    try {
        & $wrapperPath -RepoRoot $RepoRoot -SourcePath $samplePath -OutDir (Join-Path $RepoRoot "Build\M28A") -FrameCount 90 -TargetFps 30 -HoldMilliseconds 3000 -Quiet
        $manifestPath = Join-Path $RepoRoot "Build\M28A\dx12_clear_manifest.generated.txt"
        $configPath = Join-Path $RepoRoot "Build\M28A\dx12_clear_config.generated.h"
        $manifest = Read-All $manifestPath
        $config = Read-All $configPath
        Emit-Check "m27d_m28a_wrapper_compiles_lowers_scene" ($manifest.Contains('M27D_NATIVE_WINDOW_STYLE|True') -and $manifest.Contains('M28_BOX_PRIMITIVE|True') -and $manifest.Contains('M28_BOX_PRIMITIVE_COUNT|2') -and $config.Contains('ARQEN_M27D_TITLE_BAR_ENABLED 1') -and $config.Contains('ARQEN_M28_BOX_PRIMITIVE_ENABLED 1')) "M28A wrapper compiles/lowers official sample with native window style and box primitive markers"
    } catch {
        Emit-Check "m27d_m28a_wrapper_compiles_lowers_scene" $false $_.Exception.Message
    }
} else {
    Emit-Check "m27d_m28a_wrapper_compiles_lowers_scene" $false "M28A wrapper missing"
}

[System.IO.File]::WriteAllLines($outPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "OUT|$outPath"
if ($failed) { exit 1 }
