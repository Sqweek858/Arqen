param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$outPath = Join-Path $RepoRoot "Build\Generated\m24_m25_m26_dx12_runtime_scene_validation.txt"
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
$parser = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Dx12.cs")
$core = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Core.cs")
$ast = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Frontend\AstEmit.cs")
$ir = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Frontend\IrEmit.cs")
$strict = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Backend\IrModel.cs")
$lowerer = Read-All (Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1")
$runtimeHeader = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.h")
$runtimeCpp = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp")
$nativeBuilder = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1")
$docs = Read-All (Join-Path $RepoRoot "Docs\M24_M25_M26_RUNTIME_SCENE.md")
$handoff = Read-All (Join-Path $RepoRoot "Docs\M24_M25_M26_HANDOFF.md")
$toolMap = Read-All (Join-Path $RepoRoot "Docs\TOOL_MAP.md")
$spec = Read-All (Join-Path $RepoRoot "Specs\Commands\dx12.command.txt")
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_interactive_camera_scene_m26c.arq"
$sample = Read-All $samplePath
$expected = Read-All (Join-Path $RepoRoot "Tests\CommandTests\dx12\expected.txt")

Emit-Check "m24_models_ast_ir" ($models.Contains('record Dx12ObjectTransform') -and $ast.Contains('DX12_OBJECT_TRANSFORM|') -and $ir.Contains('DX12_OBJECT_TRANSFORM|') -and $strict.Contains('DX12_OBJECT_TRANSFORM')) "M24 object transform metadata model/AST/IR/strict IR present"
Emit-Check "m25_models_ast_ir" ($models.Contains('record Dx12Camera') -and $models.Contains('record Dx12CameraUse') -and $models.Contains('record Dx12CameraTransform') -and $ast.Contains('DX12_CAMERA|') -and $ir.Contains('DX12_CAMERA_USE|') -and $strict.Contains('DX12_CAMERA_TRANSFORM')) "M25 camera metadata model/AST/IR/strict IR present"
Emit-Check "m26_models_ast_ir" ($models.Contains('record Dx12KeyBinding') -and $ast.Contains('DX12_KEY_BINDING|') -and $ir.Contains('DX12_KEY_BINDING|') -and $strict.Contains('DX12_KEY_BINDING')) "M26 keyboard metadata model/AST/IR/strict IR present"
Emit-Check "m24_parser_syntax" ($core.Contains('ParseDx12TransformOrCameraStatement') -and $parser.Contains('AddDx12ObjectTransform') -and $parser.Contains('DX12 object rotation z must be numeric degrees') -and $parser.Contains('DX12 object scale must be a vec3')) "parser recognizes M24 object transform syntax"
Emit-Check "m25_parser_syntax" ($core.Contains('ParseDx12CameraDefinitionStatement') -and $parser.Contains('ParseDx12CameraDefinitionStatement') -and $parser.Contains('ParseDx12CameraUseStatement') -and $parser.Contains('DX12 camera zoom must be numeric')) "parser recognizes M25 orthographic camera syntax"
Emit-Check "m26_parser_syntax" ($core.Contains('ParseDx12KeyboardInputStatement') -and $parser.Contains('move_camera_held') -and $parser.Contains('reset_camera_pressed') -and $parser.Contains('toggle_animation_pressed')) "parser recognizes M26 keyboard input syntax"
Emit-Check "m24_lowerer_runtime_markers" ($lowerer.Contains('ARQEN_M24_OBJECT_TRANSFORM_DATA') -and $lowerer.Contains('M24_TRANSFORM_RUNTIME') -and $runtimeHeader.Contains('struct ArqenDx12ObjectTransform') -and $runtimeCpp.Contains('UpdateSceneVertexBuffer')) "lowerer/runtime support M24 transform table and per-frame vertex updates"
Emit-Check "m25_lowerer_runtime_markers" ($lowerer.Contains('ARQEN_M25_CAMERA_DATA') -and $lowerer.Contains('M25_ORTHOGRAPHIC_CAMERA') -and $runtimeHeader.Contains('struct ArqenDx12OrthographicCamera') -and $runtimeCpp.Contains('camera_.zoom')) "lowerer/runtime support M25 orthographic camera"
Emit-Check "m26_lowerer_runtime_markers" ($lowerer.Contains('ARQEN_M26_KEY_BINDING_DATA') -and $runtimeHeader.Contains('ArqenDx12KeyBinding') -and $runtimeCpp.Contains('GetAsyncKeyState') -and $runtimeCpp.Contains('animationPaused_') -and $nativeBuilder.Contains('ARQEN_M26_KEY_BINDING_DATA')) "lowerer/native builder/runtime support M26 keyboard input"
Emit-Check "m26_sample_exists" ((Test-Path $samplePath) -and $sample.Contains('define camera called "MainCamera"') -and $sample.Contains('when key "W" is held move camera') -and $sample.Contains('when key "Space" is pressed toggle animation')) "official M26 interactive camera scene sample present"
Emit-Check "m24_m25_m26_tests_expected" ($expected.Contains('valid_dx12_transform_camera_input_metadata.arq') -and $expected.Contains('invalid_dx12_transform_unknown_object.arq') -and $expected.Contains('invalid_dx12_camera_unknown_use.arq') -and $expected.Contains('invalid_dx12_input_bad_key.arq')) "M24/M25/M26 command tests listed in dx12 expected.txt"
Emit-Check "m24_m25_m26_docs_tooling" ($docs.Contains('M24') -and $docs.Contains('M25') -and $docs.Contains('M26') -and $handoff.Contains('build_m26c_dx12_interactive_camera_scene.ps1') -and $toolMap.Contains('validate_m24_m25_m26_dx12_runtime_scene.ps1') -and $spec.Contains('M26_KEYBOARD_INPUT_SYNTAX')) "docs/spec/tool map document M24/M25/M26"

$wrapper = Join-Path $RepoRoot "Tools\build_m26c_dx12_interactive_camera_scene.ps1"
if (Test-Path $wrapper) {
    try {
        & $wrapper -RepoRoot $RepoRoot -SourcePath $samplePath -OutDir (Join-Path $RepoRoot "Build\M26C") -FrameCount 90 -TargetFps 30 -HoldMilliseconds 3000 -Quiet
        $manifestPath = Join-Path $RepoRoot "Build\M26C\dx12_clear_manifest.generated.txt"
        $configPath = Join-Path $RepoRoot "Build\M26C\dx12_clear_config.generated.h"
        $manifest = Read-All $manifestPath
        $config = Read-All $configPath
        Emit-Check "m26_wrapper_compiles_lowers_scene" ($manifest.Contains('M24_TRANSFORM_RUNTIME|True') -and $manifest.Contains('M25_ORTHOGRAPHIC_CAMERA|True') -and $manifest.Contains('M26_KEYBOARD_INPUT|True') -and $config.Contains('ARQEN_M24_TRANSFORM_RUNTIME_ENABLED 1') -and $config.Contains('ARQEN_M25_CAMERA_ENABLED 1') -and $config.Contains('ARQEN_M26_KEYBOARD_INPUT_ENABLED 1')) "M26 wrapper compiles/lowers official sample with transform/camera/input markers"
    } catch {
        Emit-Check "m26_wrapper_compiles_lowers_scene" $false $_.Exception.Message
    }
} else {
    Emit-Check "m26_wrapper_compiles_lowers_scene" $false "M26 wrapper missing"
}

Emit-Check "m26_capability_still_unsupported" ($toolMap.Contains('M24/M25/M26') -and $docs.Contains('do not implement scene graph parenting')) "DX12 UI/scene graph families remain explicit future work"

[System.IO.File]::WriteAllLines($outPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "OUT|$outPath"
if ($failed) { exit 1 }
