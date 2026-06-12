param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (git rev-parse --show-toplevel).Trim() }
$outPath = Join-Path $RepoRoot "Build\Generated\m29b_dx12_ue_style_viewport_navigation_validation.txt"
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

$runtimeCpp = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp")
$nativeBuilder = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1")
$lowerer = Read-All (Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1")
$wrapper = Read-All (Join-Path $RepoRoot "Tools\build_m29b_dx12_ue_style_viewport_navigation_scene.ps1")
$toolMap = Read-All (Join-Path $RepoRoot "Docs\TOOL_MAP.md")
$milestones = Read-All (Join-Path $RepoRoot "Docs\MILESTONES.md")
$docs = Read-All (Join-Path $RepoRoot "Docs\M29B_DX12_UE_STYLE_VIEWPORT_NAVIGATION.md")
$handoff = Read-All (Join-Path $RepoRoot "Docs\M29B_HANDOFF.md")
$sampleReadme = Read-All (Join-Path $RepoRoot "Samples\README.md")
$spec = Read-All (Join-Path $RepoRoot "Specs\Commands\dx12.command.txt")
$irContract = Read-All (Join-Path $RepoRoot "IR\ARQIR_V0_CONTRACT.md")
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_ue_style_viewport_navigation_scene_m29b.arq"
$sample = Read-All $samplePath

Emit-Check "m29b_sample_exists" ((Test-Path $samplePath) -and $sample.Contains('capture mouse for window "MainWindow"') -and $sample.Contains('when mouse moves rotate camera "MainCamera"') -and $sample.Contains('when key "W" is held move camera') -and $sample.Contains('when key "Q" is held move camera') -and -not $sample.Contains('when key "R" is pressed reset camera')) "official M29B UE-style viewport navigation sample exists and does not bind R/reset"
Emit-Check "m29b_runtime_soft_capture" ($runtimeCpp.Contains('RequiresViewportNavigationHold') -and $runtimeCpp.Contains('IsRightMouseDown') -and $runtimeCpp.Contains('SetViewportNavigationActive') -and $runtimeCpp.Contains('viewportNavigationActive_') -and $runtimeCpp.Contains('ReleaseCapture') -and $runtimeCpp.Contains('SetCursorVisible(true)')) "runtime uses RMB-held soft mouse capture and releases cursor when RMB is up"
Emit-Check "m29b_runtime_no_startup_capture" ($runtimeCpp.Contains('cursor remains free until RMB is held') -and -not $runtimeCpp.Contains('if (mouseCaptureEnabled_ && hwnd_)')) "runtime no longer locks/warps mouse at initialization"
Emit-Check "m29b_camera_relative_movement" ($runtimeCpp.Contains('RotatePerspectiveLocalToWorld') -and $runtimeCpp.Contains('MoveActiveCamera(binding.x, binding.y, binding.z, dt)') -and $runtimeCpp.Contains('worldY + dy') -and $runtimeCpp.Contains('RequiresViewportNavigationHold() || viewportNavigationActive_')) "runtime maps WASD local X/Z through camera rotation and gates movement while RMB is up"
Emit-Check "m29b_window_cursor_arrow" ($nativeBuilder.Contains('wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);')) "native generated window class uses a normal arrow cursor when viewport navigation is inactive"
Emit-Check "m29b_lowerer_markers" ($lowerer.Contains('M29B_UE_STYLE_VIEWPORT_NAVIGATION') -and $lowerer.Contains('ARQEN_M29B_UE_STYLE_VIEWPORT_NAVIGATION_ENABLED') -and $lowerer.Contains('M29B_CAMERA_RELATIVE_MOVEMENT')) "lowerer emits M29B manifest/config markers without adding public syntax"
Emit-Check "m29b_wrapper" ($wrapper.Contains('dx12_ue_style_viewport_navigation_scene_m29b.arq') -and $wrapper.Contains('M29B_UE_STYLE_VIEWPORT_NAVIGATION|True') -and $wrapper.Contains('M29B_RMB_HOLD_NAVIGATION|True') -and $wrapper.Contains('m29b_dx12_ue_style_viewport_navigation_scene.exe')) "M29B wrapper validates compile/lower/native-build markers"
Emit-Check "m29b_docs_spec_toolmap" ($docs.Contains('M29B') -and $docs.Contains('RMB') -and $docs.Contains('camera-relative') -and $handoff.Contains('build_m29b_dx12_ue_style_viewport_navigation_scene.ps1') -and $toolMap.Contains('validate_m29b_dx12_ue_style_viewport_navigation.ps1') -and $milestones.Contains('M29B') -and $sampleReadme.Contains('dx12_ue_style_viewport_navigation_scene_m29b.arq') -and $spec.Contains('M29B_UE_STYLE_VIEWPORT_NAVIGATION') -and $irContract.Contains('M29B_UE_STYLE_VIEWPORT_NAVIGATION')) "docs/spec/tool map/sample README/IR contract document M29B contracts"
Emit-Check "m29b_future_scope_blocked" ($docs.Contains('No gizmo') -and $docs.Contains('No selection') -and $docs.Contains('No key remapping') -and $docs.Contains('No collision') -and $docs.Contains('No physics')) "M29B explicitly avoids editor/gameplay/input families outside viewport QOL"

$wrapperPath = Join-Path $RepoRoot "Tools\build_m29b_dx12_ue_style_viewport_navigation_scene.ps1"
if (Test-Path $wrapperPath) {
    try {
        & $wrapperPath -RepoRoot $RepoRoot -SourcePath $samplePath -OutDir (Join-Path $RepoRoot "Build\M29B") -FrameCount 90 -TargetFps 30 -HoldMilliseconds 3000 -Quiet
        $manifestPath = Join-Path $RepoRoot "Build\M29B\dx12_clear_manifest.generated.txt"
        $configPath = Join-Path $RepoRoot "Build\M29B\dx12_clear_config.generated.h"
        $manifest = Read-All $manifestPath
        $config = Read-All $configPath
        Emit-Check "m29b_wrapper_compiles_lowers_scene" ($manifest.Contains('M29B_UE_STYLE_VIEWPORT_NAVIGATION|True') -and $manifest.Contains('M29B_CAMERA_RELATIVE_MOVEMENT|True') -and $manifest.Contains('M29B_RMB_HOLD_NAVIGATION|True') -and $config.Contains('ARQEN_M29B_UE_STYLE_VIEWPORT_NAVIGATION_ENABLED 1') -and $config.Contains('ARQEN_M29B_CAMERA_RELATIVE_MOVEMENT_ENABLED 1')) "M29B wrapper compiles/lowers official sample with UE-style viewport navigation markers"
    } catch {
        Emit-Check "m29b_wrapper_compiles_lowers_scene" $false $_.Exception.Message
    }
} else { Emit-Check "m29b_wrapper_compiles_lowers_scene" $false "M29B wrapper missing" }

[System.IO.File]::WriteAllLines($outPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "OUT|$outPath"
if ($failed) { exit 1 }
