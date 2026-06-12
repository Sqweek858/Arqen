param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$outPath = Join-Path $RepoRoot "Build\Generated\m27_dx12_perspective_depth_validation.txt"
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
$wrapper = Read-All (Join-Path $RepoRoot "Tools\build_m27c_dx12_perspective_depth_scene.ps1")
$toolMap = Read-All (Join-Path $RepoRoot "Docs\TOOL_MAP.md")
$milestones = Read-All (Join-Path $RepoRoot "Docs\MILESTONES.md")
$docs = Read-All (Join-Path $RepoRoot "Docs\M27_DX12_PERSPECTIVE_DEPTH.md")
$handoff = Read-All (Join-Path $RepoRoot "Docs\M27_HANDOFF.md")
$sampleReadme = Read-All (Join-Path $RepoRoot "Samples\README.md")
$spec = Read-All (Join-Path $RepoRoot "Specs\Commands\dx12.command.txt")
$expected = Read-All (Join-Path $RepoRoot "Tests\CommandTests\dx12\expected.txt")
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_perspective_depth_scene_m27c.arq"
$sample = Read-All $samplePath

Emit-Check "m27_models_ast_ir" ($models.Contains('record Dx12CameraProjection') -and $models.Contains('Dx12CameraProjections') -and $ast.Contains('DX12_CAMERA_PROJECTION|') -and $ir.Contains('DX12_CAMERA_PROJECTION|') -and $strict.Contains('DX12_CAMERA_PROJECTION')) "M27 camera projection metadata model/AST/IR/strict IR present"
Emit-Check "m27_parser_perspective_syntax" ($core.Contains('_dx12CameraProjections') -and $parser.Contains('CurrentWordIs("camera")') -and $parser.Contains('projection') -and $parser.Contains('perspective') -and $parser.Contains('fov_y_degrees') -and $parser.Contains('near_plane') -and $parser.Contains('far_plane') -and $parser.Contains('DX12 camera field of view')) "parser recognizes projection/rotation/FOV/near/far camera syntax"
Emit-Check "m27_command_tests" ($expected.Contains('valid_dx12_perspective_camera_metadata.arq') -and $expected.Contains('invalid_dx12_camera_bad_projection.arq') -and $expected.Contains('invalid_dx12_camera_bad_fov.arq') -and $expected.Contains('invalid_dx12_camera_bad_near_plane.arq')) "positive and negative command tests listed for M27 syntax"
Emit-Check "m27_sample_exists" ((Test-Path $samplePath) -and $sample.Contains('set camera "MainCamera" projection to perspective') -and $sample.Contains('set field of view of camera "MainCamera" to 70 deg') -and $sample.Contains('set near plane of camera "MainCamera" to 0.1') -and $sample.Contains('draw "FarPanel"')) "official M27C perspective/depth sample present"
Emit-Check "m27_lowerer_markers" ($lowerer.Contains('DX12_CAMERA_PROJECTION') -and $lowerer.Contains('M27_DEPTH_BUFFER') -and $lowerer.Contains('M27_CAMERA_PROJECTION') -and $lowerer.Contains('M27_PERSPECTIVE_CAMERA') -and $lowerer.Contains('ARQEN_M27_PERSPECTIVE_CAMERA_DATA') -and $lowerer.Contains('far plane must be greater than near plane')) "lowerer emits M27 manifest/config markers and validates perspective camera contract"
Emit-Check "m27_runtime_depth_buffer" ($runtimeHeader.Contains('enableDepth') -and $runtimeCpp.Contains('CreateDepthResources') -and $runtimeCpp.Contains('CreateDepthStencilView') -and $runtimeCpp.Contains('ClearDepthStencilView') -and $runtimeCpp.Contains('D3D12_DEPTH_WRITE_MASK_ALL') -and $runtimeCpp.Contains('D3D12_COMPARISON_FUNC_LESS_EQUAL') -and $runtimeCpp.Contains('DXGI_FORMAT_D32_FLOAT')) "runtime creates/clears D3D12 depth buffer and enables z testing"
Emit-Check "m27_runtime_perspective_camera" ($runtimeHeader.Contains('struct ArqenDx12PerspectiveCamera') -and $runtimeHeader.Contains('enablePerspectiveCamera') -and $runtimeCpp.Contains('ProjectPerspectiveVertex') -and $runtimeCpp.Contains('perspectiveCameraEnabled_') -and $runtimeCpp.Contains('pitchDegrees') -and $runtimeCpp.Contains('fovYDegrees')) "runtime projects vertices through perspective camera without replacing orthographic path"
Emit-Check "m27_native_builder" ($nativeBuilder.Contains('ARQEN_M27_PERSPECTIVE_CAMERA_DATA') -and $nativeBuilder.Contains('enablePerspectiveCamera') -and $nativeBuilder.Contains('enableDepth')) "native build helper passes M27 perspective/depth data into runtime desc"
Emit-Check "m27_wrapper" ($wrapper.Contains('dx12_perspective_depth_scene_m27c.arq') -and $wrapper.Contains('M27_DEPTH_BUFFER|True') -and $wrapper.Contains('ARQEN_M27_PERSPECTIVE_CAMERA_ENABLED 1') -and $wrapper.Contains('m27c_dx12_perspective_depth_scene.exe')) "M27C wrapper validates compile/lower/native-build markers"
Emit-Check "m27_docs_spec_toolmap" ($docs.Contains('M27A') -and $docs.Contains('M27B') -and $docs.Contains('M27C') -and $handoff.Contains('build_m27c_dx12_perspective_depth_scene.ps1') -and $toolMap.Contains('validate_m27_dx12_perspective_depth.ps1') -and $milestones.Contains('M27') -and $sampleReadme.Contains('dx12_perspective_depth_scene_m27c.arq') -and $spec.Contains('M27_PERSPECTIVE_CAMERA_SYNTAX')) "docs/spec/tool map/sample README document M27 contracts"
Emit-Check "m27_future_scope_blocked" ($docs.Contains('No scene graph') -and $docs.Contains('No mouse input') -and $docs.Contains('No lighting') -and $docs.Contains('No mesh import')) "M27 explicitly avoids future M27D/E or larger rendering families"

$wrapperPath = Join-Path $RepoRoot "Tools\build_m27c_dx12_perspective_depth_scene.ps1"
if (Test-Path $wrapperPath) {
    try {
        & $wrapperPath -RepoRoot $RepoRoot -SourcePath $samplePath -OutDir (Join-Path $RepoRoot "Build\M27C") -FrameCount 90 -TargetFps 30 -HoldMilliseconds 3000 -Quiet
        $manifestPath = Join-Path $RepoRoot "Build\M27C\dx12_clear_manifest.generated.txt"
        $configPath = Join-Path $RepoRoot "Build\M27C\dx12_clear_config.generated.h"
        $manifest = Read-All $manifestPath
        $config = Read-All $configPath
        Emit-Check "m27_wrapper_compiles_lowers_scene" ($manifest.Contains('M27_DEPTH_BUFFER|True') -and $manifest.Contains('M27_CAMERA_PROJECTION|perspective') -and $manifest.Contains('M27_PERSPECTIVE_CAMERA|True') -and $config.Contains('ARQEN_M27_DEPTH_BUFFER_ENABLED 1') -and $config.Contains('ARQEN_M27_PERSPECTIVE_CAMERA_ENABLED 1')) "M27 wrapper compiles/lowers official sample with perspective/depth markers"
    } catch {
        Emit-Check "m27_wrapper_compiles_lowers_scene" $false $_.Exception.Message
    }
} else {
    Emit-Check "m27_wrapper_compiles_lowers_scene" $false "M27 wrapper missing"
}

[System.IO.File]::WriteAllLines($outPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "OUT|$outPath"
if ($failed) { exit 1 }
