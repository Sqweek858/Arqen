param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (git rev-parse --show-toplevel).Trim() }
$outPath = Join-Path $RepoRoot "Build\Generated\m28b_dx12_full_peripheral_input_validation.txt"
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
$lowerer = Read-All (Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1")
$runtimeH = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.h")
$runtimeCpp = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp")
$nativeBuilder = Read-All (Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1")
$wrapper = Read-All (Join-Path $RepoRoot "Tools\Build\DX12\build_m28b_dx12_full_peripheral_input_scene.ps1")
$expected = Read-All (Join-Path $RepoRoot "Tests\CommandTests\dx12\expected.txt")
$toolMap = Read-All (Join-Path $RepoRoot "Docs\Info\TOOLS.md")
$milestones = Read-All (Join-Path $RepoRoot "Docs\MILESTONES.md")
$docs = Read-All (Join-Path $RepoRoot "Docs\Milestones\\M26_M30.md")
$handoff = Read-All (Join-Path $RepoRoot "Docs\Milestones\\M26_M30.md")
$sampleReadme = Read-All (Join-Path $RepoRoot "Samples\README.md")
$spec = Read-All (Join-Path $RepoRoot "Tests\CommandTests\misc\dx12.command.txt")
$registry = Read-All (Join-Path $RepoRoot "Docs\Language\LANGUAGE.md")
$irContract = Read-All (Join-Path $RepoRoot "Docs\Reference\IR\ARQIR_V0_CONTRACT.md")
$runtimeRegistryTool = Read-All (Join-Path $RepoRoot "Tools\Generate\generate_runtime_action_registry.ps1")
$m21fValidator = Read-All (Join-Path $RepoRoot "Tools\Validate\DX12\validate_m21f_dx12_frame_loop.ps1")
$windowExpected = Read-All (Join-Path $RepoRoot "Tests\CommandTests\window\expected.txt")
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_full_peripheral_input_scene_m28b.arq"
$sample = Read-All $samplePath

Emit-Check "m28b_models_ast_ir" ($models.Contains('record Dx12MouseCapture') -and $models.Contains('record Dx12MouseMoveBinding') -and $models.Contains('record Dx12MouseButtonBinding') -and $models.Contains('record Dx12MouseWheelBinding') -and $ast.Contains('DX12_MOUSE_CAPTURE') -and $ir.Contains('DX12_MOUSE_MOVE') -and $strict.Contains('DX12_MOUSE_WHEEL')) "M28B mouse/peripheral metadata model/AST/IR/strict IR present"
Emit-Check "m28b_parser_syntax" ($core.Contains('ParseDx12MouseCaptureStatement') -and $core.Contains('ParseDx12MouseInputStatement') -and $parser.Contains('capture mouse for window') -and $parser.Contains('when mouse moves rotate camera') -and $parser.Contains('mouse wheel camera delta') -and $parser.Contains('Unsupported mouse button') -and $parser.Contains('S382') -and $parser.Contains('S383') -and $parser.Contains('S385')) "parser recognizes mouse capture/move/wheel/button syntax with strict errors"
Emit-Check "m28b_command_tests" ($expected.Contains('valid_dx12_full_peripheral_input_metadata.arq') -and $expected.Contains('invalid_dx12_mouse_capture_unknown_window.arq') -and $expected.Contains('invalid_dx12_mouse_move_bad_vector.arq') -and $expected.Contains('invalid_dx12_mouse_button_bad_button.arq') -and $expected.Contains('invalid_dx12_mouse_wheel_unknown_camera.arq')) "M28B positive and negative command tests are listed"
Emit-Check "m28b_sample_exists" ((Test-Path $samplePath) -and $sample.Contains('capture mouse for window "MainWindow"') -and $sample.Contains('when mouse moves rotate camera "MainCamera" by [0.12, 0.12]') -and $sample.Contains('when mouse wheel moves move camera "MainCamera"') -and $sample.Contains('when mouse button "Left" is held move camera') -and $sample.Contains('when key "Q" is held move camera') -and $sample.Contains('when key "E" is held move camera') -and $sample.Contains('define box called "CubeC"')) "official M28B full peripheral input sample present"
Emit-Check "m28b_lowerer_markers" ($lowerer.Contains('DX12_MOUSE_CAPTURE') -and $lowerer.Contains('M28B_PERIPHERAL_INPUT') -and $lowerer.Contains('ARQEN_M28B_MOUSE_MOVE_BINDING_DATA') -and $lowerer.Contains('Resolve-MouseButtonLiteral') -and $lowerer.Contains('Resolve-MouseWheelActionLiteral')) "lowerer emits M28B manifest/config markers and validates camera/window contracts"
Emit-Check "m28b_runtime_input" ($runtimeH.Contains('ArqenDx12MouseMoveBinding') -and $runtimeH.Contains('ArqenDx12MouseButtonBinding') -and $runtimeH.Contains('ArqenDx12MouseWheelBinding') -and $runtimeCpp.Contains('UpdateMouseInput') -and $runtimeCpp.Contains('SetCapture') -and $runtimeCpp.Contains('SetCursorPos') -and $runtimeCpp.Contains('GetAsyncKeyState') -and $runtimeCpp.Contains('InterlockedExchange(mouseWheelDelta_') -and $runtimeCpp.Contains('ClampFloat(perspectiveCamera_.pitchDegrees')) "runtime handles mouse look, buttons, wheel, capture, and pitch clamp"
Emit-Check "m28b_native_builder" ($nativeBuilder.Contains('WM_MOUSEWHEEL') -and $nativeBuilder.Contains('gArqenM28BMouseWheelDelta') -and $nativeBuilder.Contains('ARQEN_M28B_PERIPHERAL_INPUT_ENABLED == 0') -and $nativeBuilder.Contains('ArqenDx12MouseMoveBinding mouseMoveBindings') -and $nativeBuilder.Contains('triangleDesc.mouseWheelDelta')) "native builder forwards mouse wheel/buttons/move data and frees Q for vertical input when M28B is enabled"
Emit-Check "m28b_wrapper" ($wrapper.Contains('dx12_full_peripheral_input_scene_m28b.arq') -and $wrapper.Contains('M28B_PERIPHERAL_INPUT|True') -and $wrapper.Contains('M28B_MOUSE_BUTTON_BINDINGS|3') -and $wrapper.Contains('m28b_dx12_full_peripheral_input_scene.exe')) "M28B wrapper validates compile/lower/native-build markers"
Emit-Check "m28b_docs_spec_toolmap" ($docs.Contains('M28B') -and $docs.Contains('mouse buttons') -and $handoff.Contains('build_m28b_dx12_full_peripheral_input_scene.ps1') -and $toolMap.Contains('validate_m28b_dx12_full_peripheral_input.ps1') -and $milestones.Contains('M28B') -and $sampleReadme.Contains('dx12_full_peripheral_input_scene_m28b.arq') -and $spec.Contains('M28B_FULL_PERIPHERAL_INPUT_SYNTAX') -and $registry.Contains('capture mouse for window') -and $irContract.Contains('DX12_MOUSE_CAPTURE')) "docs/spec/tool map/sample README/IR contract document M28B contracts"
Emit-Check "m28b_future_scope_blocked" ($docs.Contains('No key remapping') -and $docs.Contains('No controller') -and $docs.Contains('No collision') -and $docs.Contains('No physics') -and $docs.Contains('No UI widgets')) "M28B explicitly avoids larger input/gameplay families"
Emit-Check "m28b_regression_window_key_events_preserved" ($core.Contains('PeekWord("key") && !PeekWord("pressed", 2)') -and $windowExpected.Contains('valid_escape_close_window.arq|0') -and $windowExpected.Contains('invalid_duplicate_key_event.arq|1') -and $windowExpected.Contains('invalid_unsupported_key.arq|1')) "M28B DX12 key syntax no longer hijacks legacy window key events"
Emit-Check "m28b_regression_runtime_registry_preserved" ($runtimeRegistryTool.Contains('window_style_title_bar_color') -and $runtimeRegistryTool.Contains('window_style_title_text_color') -and $runtimeRegistryTool.Contains('baseline_ir')) "indirect M27D window style runtime actions stay visible to M18B registry"
Emit-Check "m28b_regression_m21f_frame_loop_preserved" ($m21fValidator.Contains('infinite || frame < frameCount') -and $m21fValidator.Contains('SleepToTargetFrame')) "M21F validator accepts the M22 keep-open frame-loop extension"

$wrapperPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m28b_dx12_full_peripheral_input_scene.ps1"
if (Test-Path $wrapperPath) {
    try {
        & $wrapperPath -RepoRoot $RepoRoot -SourcePath $samplePath -OutDir (Join-Path $RepoRoot "Build\M28B") -FrameCount 90 -TargetFps 30 -HoldMilliseconds 3000 -Quiet
        $manifestPath = Join-Path $RepoRoot "Build\M28B\dx12_clear_manifest.generated.txt"
        $configPath = Join-Path $RepoRoot "Build\M28B\dx12_clear_config.generated.h"
        $manifest = Read-All $manifestPath
        $config = Read-All $configPath
        Emit-Check "m28b_wrapper_compiles_lowers_scene" ($manifest.Contains('M28B_PERIPHERAL_INPUT|True') -and $manifest.Contains('M28B_MOUSE_CAPTURE|True') -and $manifest.Contains('M28B_MOUSE_BUTTON_BINDINGS|3') -and $manifest.Contains('M28B_MOUSE_WHEEL_BINDINGS|1') -and $config.Contains('ARQEN_M28B_PERIPHERAL_INPUT_ENABLED 1') -and $config.Contains('ARQEN_M28B_MOUSE_CAPTURE_ENABLED 1') -and $config.Contains('ARQEN_M28B_MOUSE_BUTTON_BINDING_COUNT 3')) "M28B wrapper compiles/lowers official sample with peripheral input markers"
    } catch {
        Emit-Check "m28b_wrapper_compiles_lowers_scene" $false $_.Exception.Message
    }
} else { Emit-Check "m28b_wrapper_compiles_lowers_scene" $false "M28B wrapper missing" }

[System.IO.File]::WriteAllLines($outPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "OUT|$outPath"
if ($failed) { exit 1 }
