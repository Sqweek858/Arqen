param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (git rev-parse --show-toplevel).Trim() }
$outPath = Join-Path $RepoRoot "Build\Generated\m30a_dx12_ui_overlay_controls_validation.txt"
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

$lowerer = Read-All (Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1")
$runtimeHeader = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.h")
$runtimeCpp = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp")
$nativeBuilder = Read-All (Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1")
$wrapper = Read-All (Join-Path $RepoRoot "Tools\Build\DX12\build_m30a_dx12_ui_overlay_controls_scene.ps1")
$toolMap = Read-All (Join-Path $RepoRoot "Docs\Info\TOOLS.md")
$milestones = Read-All (Join-Path $RepoRoot "Docs\MILESTONES.md")
$docs = Read-All (Join-Path $RepoRoot "Docs\Milestones\\M26_M30.md")
$handoff = Read-All (Join-Path $RepoRoot "Docs\Milestones\\M26_M30.md")
$sampleReadme = Read-All (Join-Path $RepoRoot "Samples\README.md")
$spec = Read-All (Join-Path $RepoRoot "Tests\CommandTests\misc\dx12.command.txt")
$irContract = Read-All (Join-Path $RepoRoot "Docs\Reference\IR\ARQIR_V0_CONTRACT.md")
$expected = Read-All (Join-Path $RepoRoot "Tests\CommandTests\dx12\expected.txt")
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_ui_overlay_controls_scene_m30a.arq"
$sample = Read-All $samplePath

Emit-Check "m30a_existing_ui_contract_used" ($sample.Contains('define shape called "InspectorPanel"') -and $sample.Contains('define text called "PanelTitle"') -and $sample.Contains('define checkbox called "AnimationSwitch"') -and $sample.Contains('with layout for "InspectorPanel"') -and $sample.Contains('with style for "InspectorPanel"')) "M30A sample uses existing M19 UI/style/layout contracts rather than new UI syntax"
Emit-Check "m30a_lowerer_ui_bridge" ($lowerer.Contains('UI_OBJECT') -and $lowerer.Contains('UI_SET') -and $lowerer.Contains('UI_LAYOUT') -and $lowerer.Contains('STYLE') -and $lowerer.Contains('M30B/M30C: lower existing M19 UI/style/layout metadata') -and $lowerer.Contains('New-UiTextVertices') -and $lowerer.Contains('New-UiRectVerticesClipped') -and $lowerer.Contains('ARQEN_M30A_UI_CONTROL_DATA') -and $lowerer.Contains('foreach ($candidate in @($value))') -and $lowerer.Contains('$transformIndexBase = [uint64]2147483648')) "lowerer consumes UI/style/layout metadata and emits overlay vertices/control config with scalar-safe layout math plus M30B clipping bridge"
Emit-Check "m30a_runtime_ui_bridge" ($runtimeHeader.Contains('ArqenDx12UiControl') -and $runtimeHeader.Contains('ARQEN_DX12_UI_ACTION_TOGGLE_ANIMATION') -and $runtimeHeader.Contains('ARQEN_DX12_UI_ACTION_TOGGLE_FAKE_LIGHT') -and $runtimeCpp.Contains('UpdateUiOverlayInput') -and $runtimeCpp.Contains('ApplyUiOverlayFeedback') -and $runtimeCpp.Contains('IsArqenDx12UiDrawCall') -and $runtimeCpp.Contains('D3D12_BLEND_SRC_ALPHA')) "runtime supports UI overlay draw calls, alpha blend, clickable controls, and switch feedback"
Emit-Check "m30a_native_builder" ($nativeBuilder.Contains('ArqenDx12UiControl uiControls') -and $nativeBuilder.Contains('triangleDesc.enableUiOverlay') -and $nativeBuilder.Contains('ARQEN_M30A_UI_CONTROL_DATA')) "native builder forwards M30A UI control data into runtime desc"
Emit-Check "m30a_command_tests" ($expected.Contains('valid_dx12_ui_overlay_controls_metadata.arq') -and $expected.Contains('invalid_dx12_ui_overlay_unknown_target.arq')) "M30A command metadata coverage is listed in dx12 expected tests"
Emit-Check "m30a_sample_exists" ((Test-Path $samplePath) -and $sample.Contains('AnimationSwitch') -and $sample.Contains('LightSwitch') -and $sample.Contains('AnimationButton') -and $sample.Contains('when clicked "AnimationSwitch"') -and $sample.Contains('draw "CubeA"')) "official M30A UI overlay controls sample present"
Emit-Check "m30a_docs_spec_toolmap" ($docs.Contains('M30A') -and $docs.Contains('DX12 UI overlay') -and $docs.Contains('AnimationSwitch') -and $docs.Contains('LightSwitch') -and $handoff.Contains('build_m30a_dx12_ui_overlay_controls_scene.ps1') -and $toolMap.Contains('validate_m30a_dx12_ui_overlay_controls.ps1') -and $milestones.Contains('M30A') -and $sampleReadme.Contains('dx12_ui_overlay_controls_scene_m30a.arq') -and $spec.Contains('M30A_UI_OVERLAY') -and $irContract.Contains('UI_OBJECT')) "docs/spec/tool map/sample README/IR contract document M30A UI runtime subset"
Emit-Check "m30a_future_scope_blocked" ($docs.Contains('No docking editor') -and $docs.Contains('No font loading') -and $docs.Contains('No text input') -and $docs.Contains('No sliders') -and $docs.Contains('No drag/drop')) "M30A explicitly avoids larger UI/editor families"

$wrapperPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m30a_dx12_ui_overlay_controls_scene.ps1"
if (Test-Path $wrapperPath) {
    try {
        & $wrapperPath -RepoRoot $RepoRoot -SourcePath $samplePath -OutDir (Join-Path $RepoRoot "Build\M30A") -FrameCount 90 -TargetFps 30 -HoldMilliseconds 3000 -Quiet
        $manifestPath = Join-Path $RepoRoot "Build\M30A\dx12_clear_manifest.generated.txt"
        $configPath = Join-Path $RepoRoot "Build\M30A\dx12_clear_config.generated.h"
        $manifest = Read-All $manifestPath
        $config = Read-All $configPath
        Emit-Check "m30a_wrapper_compiles_lowers_scene" ($manifest.Contains('M30A_UI_OVERLAY|True') -and $manifest.Contains('M30A_UI_CONTROLS|3') -and $config.Contains('ARQEN_M30A_UI_OVERLAY_ENABLED 1') -and $config.Contains('ARQEN_M30A_UI_CONTROL_COUNT 3')) "M30A wrapper compiles/lowers official sample with UI overlay markers"
    } catch {
        Emit-Check "m30a_wrapper_compiles_lowers_scene" $false $_.Exception.Message
    }
} else { Emit-Check "m30a_wrapper_compiles_lowers_scene" $false "M30A wrapper missing" }

[System.IO.File]::WriteAllLines($outPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "OUT|$outPath"
if ($failed) { exit 1 }
