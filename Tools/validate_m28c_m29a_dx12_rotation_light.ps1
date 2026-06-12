param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (git rev-parse --show-toplevel).Trim() }
$outPath = Join-Path $RepoRoot "Build\Generated\m28c_m29a_dx12_rotation_light_validation.txt"
New-Item -ItemType Directory -Force -Path (Split-Path $outPath -Parent) | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false
function Read-All([string]$Path) { if (-not (Test-Path $Path)) { return "" }; return Get-Content $Path -Raw }
function Emit-Check([string]$Name, [bool]$Ok, [string]$Message) {
    $status = if ($Ok) { "PASS" } else { "FAIL" }
    $script:lines.Add("$status|$Name|$Message") | Out-Null
    Write-Host "$status|$Name|$Message"
    if (-not $Ok) { $script:failed = $true }
}

$models = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Core\Models.cs")
$core = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Core.cs")
$parser = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Dx12.cs")
$ast = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Frontend\AstEmit.cs")
$ir = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Frontend\IrEmit.cs")
$strict = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Backend\IrModel.cs")
$lowerer = Read-All (Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1")
$runtimeH = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.h")
$runtimeCpp = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp")
$nativeBuilder = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1")
$wrapper = Read-All (Join-Path $RepoRoot "Tools\build_m29a_dx12_rotation3d_fake_light_scene.ps1")
$expected = Read-All (Join-Path $RepoRoot "Tests\CommandTests\dx12\expected.txt")
$toolMap = Read-All (Join-Path $RepoRoot "Docs\TOOL_MAP.md")
$milestones = Read-All (Join-Path $RepoRoot "Docs\MILESTONES.md")
$docs = Read-All (Join-Path $RepoRoot "Docs\M28C_M29A_DX12_ROTATION_LIGHT.md")
$handoff = Read-All (Join-Path $RepoRoot "Docs\M28C_M29A_HANDOFF.md")
$sampleReadme = Read-All (Join-Path $RepoRoot "Samples\README.md")
$spec = Read-All (Join-Path $RepoRoot "Specs\Commands\dx12.command.txt")
$registry = Read-All (Join-Path $RepoRoot "Docs\COMMAND_REGISTRY.md")
$irContract = Read-All (Join-Path $RepoRoot "IR\ARQIR_V0_CONTRACT.md")
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_rotation3d_fake_light_scene_m29a.arq"
$sample = Read-All $samplePath

Emit-Check "m28c_models_ast_ir" ($models.Contains('Dx12ObjectTransform') -and $ast.Contains('DX12_OBJECT_TRANSFORM') -and $ir.Contains('DX12_OBJECT_TRANSFORM') -and $strict.Contains('DX12_OBJECT_TRANSFORM')) "M28C object transform metadata remains in model/AST/IR/strict IR"
Emit-Check "m28c_parser_rotation3d" ($parser.Contains('set rotation of object') -and $parser.Contains('rotation_x') -and $parser.Contains('rotation_y') -and $parser.Contains('DX12 object rotation must be a vec3')) "parser recognizes full object rotation vector plus x/y/z axes"
Emit-Check "m29a_models_ast_ir" ($models.Contains('record Dx12DirectionalLight') -and $models.Contains('record Dx12LightUse') -and $models.Contains('record Dx12LightProperty') -and $ast.Contains('DX12_DIRECTIONAL_LIGHT') -and $ir.Contains('DX12_LIGHT_USE') -and $strict.Contains('DX12_LIGHT_PROPERTY')) "M29A directional light metadata model/AST/IR/strict IR present"
Emit-Check "m29a_parser_light_syntax" ($core.Contains('ParseDx12DirectionalLightDefinitionStatement') -and $core.Contains('ParseDx12LightUseStatement') -and $parser.Contains('define directional light called') -and $parser.Contains('set direction of light') -and $parser.Contains('set intensity of light') -and $parser.Contains('set ambient of light')) "parser recognizes directional light definition/use/properties"
Emit-Check "m28c_m29a_command_tests" ($expected.Contains('valid_dx12_object_rotation3d_light_metadata.arq') -and $expected.Contains('invalid_dx12_object_rotation_bad_vector.arq') -and $expected.Contains('invalid_dx12_light_unknown_use.arq') -and $expected.Contains('invalid_dx12_light_zero_direction.arq') -and $expected.Contains('invalid_dx12_light_bad_intensity.arq')) "positive and negative command tests are listed"
Emit-Check "m29a_sample_exists" ((Test-Path $samplePath) -and $sample.Contains('define directional light called "KeyLight"') -and $sample.Contains('set rotation of object "CubeA"') -and $sample.Contains('set rotation x of object "CubeB"') -and $sample.Contains('use light "KeyLight" for renderer "MainRenderer"')) "official M28C/M29A sample present"
Emit-Check "m29a_lowerer_markers" ($lowerer.Contains('DX12_DIRECTIONAL_LIGHT') -and $lowerer.Contains('DX12_LIGHT_USE') -and $lowerer.Contains('M29_FAKE_LIGHTING') -and $lowerer.Contains('ARQEN_M29_DIRECTIONAL_LIGHT_DATA') -and $lowerer.Contains('Format-DirectionalLightLiteral')) "lowerer emits M28C/M29A manifest/config markers"
Emit-Check "m28c_runtime_rotation" ($runtimeH.Contains('rotationXDegrees') -and $runtimeH.Contains('rotationYDegrees') -and $runtimeCpp.Contains('ApplyObjectRotation') -and $runtimeCpp.Contains('RotateX') -and $runtimeCpp.Contains('RotateY') -and $runtimeCpp.Contains('RotateZ')) "runtime applies full object rotation before projection"
Emit-Check "m29a_runtime_fake_light" ($runtimeH.Contains('ArqenDx12DirectionalLight') -and $runtimeH.Contains('enableFakeLighting') -and $runtimeCpp.Contains('ShadeVertex') -and $runtimeCpp.Contains('fakeLightingEnabled_') -and $runtimeCpp.Contains('directionalLight_')) "runtime applies fake directional lighting on CPU-generated scene vertices"
Emit-Check "m29a_native_builder" ($nativeBuilder.Contains('ArqenDx12DirectionalLight directionalLight') -and $nativeBuilder.Contains('triangleDesc.enableFakeLighting') -and $nativeBuilder.Contains('ARQEN_M29_DIRECTIONAL_LIGHT_DATA')) "native builder forwards fake light data to runtime desc"
Emit-Check "m29a_wrapper" ($wrapper.Contains('dx12_rotation3d_fake_light_scene_m29a.arq') -and $wrapper.Contains('M29_FAKE_LIGHTING|True') -and $wrapper.Contains('M28C_OBJECT_ROTATION_3D|True') -and $wrapper.Contains('m29a_dx12_rotation3d_fake_light_scene.exe')) "wrapper validates compile/lower/native-build markers"
Emit-Check "m29a_docs_spec_toolmap" ($docs.Contains('M29A') -and $docs.Contains('fake directional lighting') -and $handoff.Contains('build_m29a_dx12_rotation3d_fake_light_scene.ps1') -and $toolMap.Contains('validate_m28c_m29a_dx12_rotation_light.ps1') -and $milestones.Contains('M29A') -and $sampleReadme.Contains('dx12_rotation3d_fake_light_scene_m29a.arq') -and $spec.Contains('M29A_FAKE_LIGHTING_SYNTAX') -and $registry.Contains('define directional light called') -and $irContract.Contains('DX12_DIRECTIONAL_LIGHT')) "docs/spec/tool map/sample README/IR contract document M28C/M29A contracts"
Emit-Check "m29a_future_scope_blocked" ($docs.Contains('No mesh import') -and $docs.Contains('No material system') -and $docs.Contains('No shadows') -and $docs.Contains('No gizmo') -and $docs.Contains('No editor camera overhaul')) "M28C/M29A explicitly avoids future rendering/editor families"

$wrapperPath = Join-Path $RepoRoot "Tools\build_m29a_dx12_rotation3d_fake_light_scene.ps1"
if (Test-Path $wrapperPath) {
    try {
        & $wrapperPath -RepoRoot $RepoRoot -SourcePath $samplePath -OutDir (Join-Path $RepoRoot "Build\M29A") -FrameCount 90 -TargetFps 30 -HoldMilliseconds 3000 -Quiet
        $manifestPath = Join-Path $RepoRoot "Build\M29A\dx12_clear_manifest.generated.txt"
        $configPath = Join-Path $RepoRoot "Build\M29A\dx12_clear_config.generated.h"
        $manifest = Read-All $manifestPath
        $config = Read-All $configPath
        Emit-Check "m29a_wrapper_compiles_lowers_scene" ($manifest.Contains('M29_FAKE_LIGHTING|True') -and $manifest.Contains('M28C_OBJECT_ROTATION_3D|True') -and $config.Contains('ARQEN_M29_FAKE_LIGHTING_ENABLED 1') -and $config.Contains('ARQEN_M29_DIRECTIONAL_LIGHT_DATA')) "M29A wrapper compiles/lowers official sample with rotation/light markers"
    } catch {
        Emit-Check "m29a_wrapper_compiles_lowers_scene" $false $_.Exception.Message
    }
} else { Emit-Check "m29a_wrapper_compiles_lowers_scene" $false "M29A wrapper missing" }

[System.IO.File]::WriteAllLines($outPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "OUT|$outPath"
if ($failed) { exit 1 }
