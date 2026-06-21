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
function Fail-M30A { param([string]$Message) throw "M30A DX12 UI overlay controls scene failed: $Message" }

if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (git rev-parse --show-toplevel).Trim() }
if ([string]::IsNullOrWhiteSpace($SourcePath)) { $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_ui_overlay_controls_scene_m30a.arq" }
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $RepoRoot "Build\M30A" }
if (-not (Test-Path $SourcePath)) { Fail-M30A "source not found: $SourcePath" }
if ($FrameCount -lt 1) { Fail-M30A "FrameCount must be positive. Use -KeepOpen for an indefinite window." }
if ($TargetFps -lt 1) { Fail-M30A "TargetFps must be positive." }
if ($HoldMilliseconds -lt 1) { Fail-M30A "HoldMilliseconds must be positive." }

$driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
if (-not (Test-Path $driver)) { Fail-M30A "compiler driver not found: $driver" }

Push-Location $RepoRoot
try {
    & $driver $SourcePath *> $null
    if ($LASTEXITCODE -ne 0) { Fail-M30A "compiler failed for $SourcePath with exit $LASTEXITCODE. Rebuild the driver with .\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail if the exe is stale." }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $irPath = Join-Path $RepoRoot ("Build\IR\{0}.arqir" -f $stem)
    if (-not (Test-Path $irPath)) { Fail-M30A "expected IR was not generated: $irPath" }

    $irText = Get-Content $irPath -Raw
    foreach ($marker in @("UI_OBJECT", "UI_SET", "UI_LAYOUT", "STYLE", "UI_EVENT", "DX12_OBJECT_SELECTOR", "DX12_DIRECTIONAL_LIGHT", "DX12_OBJECT_PRIMITIVE")) {
        if (-not $irText.Contains($marker)) { Fail-M30A "compiled IR does not contain $marker." }
    }
    foreach ($marker in @("name=InspectorPanel", "name=AnimationSwitch", "name=LightSwitch", "property=checked", "event=clicked", "kind=box", "projection=perspective")) {
        if (-not $irText.Contains($marker)) { Fail-M30A "compiled IR missing M30A marker: $marker" }
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $lowerer = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
    if (-not (Test-Path $lowerer)) { Fail-M30A "lowerer missing: $lowerer" }

    if ([string]::IsNullOrWhiteSpace($Renderer)) {
        & $lowerer -IrPath $irPath -OutDir $OutDir -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    } else {
        & $lowerer -IrPath $irPath -OutDir $OutDir -Renderer $Renderer -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    }

    $manifestPath = Join-Path $OutDir "dx12_clear_manifest.generated.txt"
    $configPath = Join-Path $OutDir "dx12_clear_config.generated.h"
    if (-not (Test-Path $manifestPath)) { Fail-M30A "manifest was not generated: $manifestPath" }
    if (-not (Test-Path $configPath)) { Fail-M30A "config header was not generated: $configPath" }

    $manifest = Get-Content $manifestPath -Raw
    $config = Get-Content $configPath -Raw
    foreach ($marker in @("M30A_UI_OVERLAY|True", "M30A_UI_CONTROLS|3", "M30A_UI_TEXT_BITMAP|True", "M29C_OBJECT_SELECTOR|True", "M29_FAKE_LIGHTING|True")) {
        if (-not $manifest.Contains($marker)) { Fail-M30A "manifest missing marker: $marker" }
    }
    foreach ($marker in @("ARQEN_M30A_DX12_UI_OVERLAY 1", "ARQEN_M30A_UI_OVERLAY_ENABLED 1", "ARQEN_M30A_UI_CONTROL_COUNT 3", "ARQEN_DX12_UI_ACTION_TOGGLE_ANIMATION", "ARQEN_DX12_UI_ACTION_TOGGLE_FAKE_LIGHT")) {
        if (-not $config.Contains($marker)) { Fail-M30A "config missing marker: $marker" }
    }

    if ($BuildNative -or $Run) {
        $builder = Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1"
        if (-not (Test-Path $builder)) { Fail-M30A "native build helper missing: $builder" }
        if ([string]::IsNullOrWhiteSpace($Renderer)) {
            & $builder -IrPath $irPath -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m30a_dx12_ui_overlay_controls_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        } else {
            & $builder -IrPath $irPath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m30a_dx12_ui_overlay_controls_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        }
    }

    if (-not $Quiet) { Write-Host "PASS|m30a_dx12_ui_overlay_controls_scene|source=$SourcePath|out=$OutDir|keep_open=$([bool]$KeepOpen)|fps=$TargetFps" }
} finally {
    Pop-Location
}
