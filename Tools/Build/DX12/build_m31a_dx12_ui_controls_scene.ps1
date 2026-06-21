param(
    [string]$SourcePath = "",
    [string]$Renderer = "",
    [string]$RepoRoot = "",
    [Alias("Frames")]
    [int]$FrameCount = 900,
    [Alias("Fps")]
    [int]$TargetFps = 60,
    [Alias("Hold")]
    [int]$HoldMilliseconds = 15000,
    [Alias("Interactive")]
    [switch]$KeepOpen,
    [string]$OutDir = "",
    [Alias("Native")]
    [switch]$BuildNative,
    [Alias("RunNative")]
    [switch]$Run,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
function Fail-M30B { param([string]$Message) throw "M30D/M31A/M31B DX12 UI controls scene failed: $Message" }

if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (git rev-parse --show-toplevel).Trim() }
if ([string]::IsNullOrWhiteSpace($SourcePath)) { $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_ui_controls_fancy_scene_m31a.arq" }
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $RepoRoot "Build\M31A" }
if (-not (Test-Path $SourcePath)) { Fail-M30B "source not found: $SourcePath" }
if ($FrameCount -lt 1) { Fail-M30B "FrameCount must be positive. Use -KeepOpen for an indefinite window." }
if ($TargetFps -lt 1) { Fail-M30B "TargetFps must be positive." }
if ($HoldMilliseconds -lt 1) { Fail-M30B "HoldMilliseconds must be positive." }

$driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
if (-not (Test-Path $driver)) { Fail-M30B "compiler driver not found: $driver" }

Push-Location $RepoRoot
try {
    & $driver $SourcePath *> $null
    if ($LASTEXITCODE -ne 0) { Fail-M30B "compiler failed for $SourcePath with exit $LASTEXITCODE. Rebuild the driver with .\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail if the exe is stale." }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $irPath = Join-Path $RepoRoot ("Build\IR\{0}.arqir" -f $stem)
    if (-not (Test-Path $irPath)) { Fail-M30B "expected IR was not generated: $irPath" }

    $irText = Get-Content $irPath -Raw
    foreach ($marker in @("UI_OBJECT", "UI_SET", "UI_LAYOUT", "UI_PARENT", "STYLE", "UI_EVENT", "UI_STATE", "UI_RESOURCE", "UI_RESOURCE_USE", "DX12_OBJECT_SELECTOR", "DX12_DIRECTIONAL_LIGHT", "DX12_OBJECT_PRIMITIVE")) {
        if (-not $irText.Contains($marker)) { Fail-M30B "compiled IR does not contain $marker." }
    }
    foreach ($marker in @("name=InspectorPanel", "name=SliderHintText", "name=AnimationSwitch", "name=LightSwitch", "name=ExposureSlider", "name=ObjectNameInput", "name=QualityDropdown", "property=checked", "property=value", "event=clicked", "body=print string toggle animation", "child=PanelTitle", "parent=InspectorPanel", "kind=box", "projection=perspective")) {
        if (-not $irText.Contains($marker)) { Fail-M30B "compiled IR missing M30D/M31A/M31B marker: $marker" }
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $lowerer = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
    if (-not (Test-Path $lowerer)) { Fail-M30B "lowerer missing: $lowerer" }

    if ([string]::IsNullOrWhiteSpace($Renderer)) {
        & $lowerer -IrPath $irPath -OutDir $OutDir -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    } else {
        & $lowerer -IrPath $irPath -OutDir $OutDir -Renderer $Renderer -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    }

    $manifestPath = Join-Path $OutDir "dx12_clear_manifest.generated.txt"
    $configPath = Join-Path $OutDir "dx12_clear_config.generated.h"
    if (-not (Test-Path $manifestPath)) { Fail-M30B "manifest was not generated: $manifestPath" }
    if (-not (Test-Path $configPath)) { Fail-M30B "config header was not generated: $configPath" }

    $manifest = Get-Content $manifestPath -Raw
    $config = Get-Content $configPath -Raw
    foreach ($marker in @("M30A_UI_OVERLAY|True", "M30B_UI_LAYOUT_HYGIENE|True", "M30B_TEXT_CLIPPING|True", "M30C_UI_PARENT_CLIP_BRIDGE|True", "M30C_PARENT_RELATIVE_LAYOUT|True", "M30D_UI_CLICK_EVENT_BRIDGE|True", "M30D_UI_EVENT_BODY_ACTIONS|True", "M31A_UI_CONTROLS_EXPANSION|True", "M31A_UI_HOVER_PRESS_FOCUS_STATES|True", "M31C_UI_PARENT_CONTAINMENT|True", "M31C_UI_TEXT_PADDING_DEFAULTS|True", "M31C_UI_STYLE_BOX_MODEL|True", "M31C_UI_SLIDER_RUNTIME_VISUALS|True", "M31C_UI_STABLE_CLIENT_PIXEL_SPACE|True", "M31B_UI_RESOURCE_METADATA_BRIDGE|True", "M29C_OBJECT_SELECTOR|True", "M29_FAKE_LIGHTING|True")) {
        if (-not $manifest.Contains($marker)) { Fail-M30B "manifest missing marker: $marker" }
    }
    foreach ($marker in @("ARQEN_M30A_DX12_UI_OVERLAY 1", "ARQEN_M30A_UI_OVERLAY_ENABLED 1", "ARQEN_M30B_TEXT_CLIPPING 1", "ARQEN_M30B_BUTTON_TEXT_CENTERING 1", "ARQEN_M30C_UI_PARENT_CLIP_BRIDGE 1", "ARQEN_M30D_UI_CLICK_EVENT_BRIDGE 1", "ARQEN_M30D_UI_EVENT_BODY_ACTIONS 1", "ARQEN_M31A_UI_CONTROLS_EXPANSION 1", "ARQEN_M31A_UI_HOVER_PRESSED_FOCUS_STATES 1", "ARQEN_M31C_UI_PARENT_CONTAINMENT 1", "ARQEN_M31C_UI_TEXT_PADDING_DEFAULTS 1", "ARQEN_M31C_UI_STYLE_BOX_MODEL 1", "ARQEN_M31C_UI_SLIDER_RUNTIME_VISUALS 1", "ARQEN_M31C_UI_STABLE_CLIENT_PIXEL_SPACE 1", "ARQEN_M31B_UI_RESOURCE_METADATA_BRIDGE 1", "ARQEN_DX12_UI_CONTROL_SLIDER", "ARQEN_DX12_UI_CONTROL_INPUT_FIELD", "ARQEN_DX12_UI_CONTROL_DROPDOWN", "ARQEN_DX12_UI_ACTION_TOGGLE_ANIMATION", "ARQEN_DX12_UI_ACTION_TOGGLE_FAKE_LIGHT")) {
        if (-not $config.Contains($marker)) { Fail-M30B "config missing marker: $marker" }
    }

    if ($BuildNative -or $Run) {
        $builder = Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1"
        if (-not (Test-Path $builder)) { Fail-M30B "native build helper missing: $builder" }
        if ([string]::IsNullOrWhiteSpace($Renderer)) {
            & $builder -IrPath $irPath -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m31a_dx12_ui_controls_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        } else {
            & $builder -IrPath $irPath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m31a_dx12_ui_controls_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        }
    }

    if (-not $Quiet) { Write-Host "PASS|m31a_dx12_ui_controls_scene|source=$SourcePath|out=$OutDir|keep_open=$([bool]$KeepOpen)|fps=$TargetFps" }
} finally {
    Pop-Location
}
