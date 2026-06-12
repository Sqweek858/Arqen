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
function Fail-M29B { param([string]$Message) throw "M29B DX12 UE-style viewport navigation scene failed: $Message" }

if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (git rev-parse --show-toplevel).Trim() }
if ([string]::IsNullOrWhiteSpace($SourcePath)) { $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_ue_style_viewport_navigation_scene_m29b.arq" }
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $RepoRoot "Build\M29B" }
if (-not (Test-Path $SourcePath)) { Fail-M29B "source not found: $SourcePath" }
if ($FrameCount -lt 1) { Fail-M29B "FrameCount must be positive. Use -KeepOpen for an indefinite window." }
if ($TargetFps -lt 1) { Fail-M29B "TargetFps must be positive." }
if ($HoldMilliseconds -lt 1) { Fail-M29B "HoldMilliseconds must be positive." }

$driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
if (-not (Test-Path $driver)) { Fail-M29B "compiler driver not found: $driver" }

Push-Location $RepoRoot
try {
    & $driver $SourcePath *> $null
    if ($LASTEXITCODE -ne 0) { Fail-M29B "compiler failed for $SourcePath with exit $LASTEXITCODE. Rebuild the driver with .\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail if the exe is stale." }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $irPath = Join-Path $RepoRoot ("Build\IR\{0}.arqir" -f $stem)
    if (-not (Test-Path $irPath)) { Fail-M29B "expected IR was not generated: $irPath" }

    $irText = Get-Content $irPath -Raw
    foreach ($marker in @("DX12_MOUSE_CAPTURE", "DX12_MOUSE_MOVE", "DX12_KEY_BINDING", "DX12_MOUSE_WHEEL", "DX12_OBJECT_TRANSFORM", "DX12_DIRECTIONAL_LIGHT", "DX12_LIGHT_USE", "DX12_LIGHT_PROPERTY", "DX12_OBJECT_PRIMITIVE", "DX12_CAMERA_PROJECTION")) {
        if (-not $irText.Contains($marker)) { Fail-M29B "compiled IR does not contain $marker. Rebuild the driver from M29B source." }
    }
    foreach ($marker in @("window=MainWindow", "target=MainCamera", "key=W", "key=Q", "key=E", "projection=perspective", "kind=box")) {
        if (-not $irText.Contains($marker)) { Fail-M29B "compiled IR missing M29B marker: $marker" }
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $lowerer = Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1"
    if (-not (Test-Path $lowerer)) { Fail-M29B "lowerer missing: $lowerer" }

    if ([string]::IsNullOrWhiteSpace($Renderer)) {
        & $lowerer -IrPath $irPath -OutDir $OutDir -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    } else {
        & $lowerer -IrPath $irPath -OutDir $OutDir -Renderer $Renderer -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    }

    $manifestPath = Join-Path $OutDir "dx12_clear_manifest.generated.txt"
    $configPath = Join-Path $OutDir "dx12_clear_config.generated.h"
    if (-not (Test-Path $manifestPath)) { Fail-M29B "manifest was not generated: $manifestPath" }
    if (-not (Test-Path $configPath)) { Fail-M29B "config header was not generated: $configPath" }

    $manifest = Get-Content $manifestPath -Raw
    $config = Get-Content $configPath -Raw
    foreach ($marker in @("M29B_UE_STYLE_VIEWPORT_NAVIGATION|True", "M29B_CAMERA_RELATIVE_MOVEMENT|True", "M29B_RMB_HOLD_NAVIGATION|True", "M28B_MOUSE_CAPTURE|True", "M26_KEY_BINDINGS|7", "M29_FAKE_LIGHTING|True", "M28_BOX_PRIMITIVE|True", "M27_PERSPECTIVE_CAMERA|True")) {
        if (-not $manifest.Contains($marker)) { Fail-M29B "manifest missing marker: $marker" }
    }
    foreach ($marker in @("ARQEN_M29B_UE_STYLE_VIEWPORT_NAVIGATION_ENABLED 1", "ARQEN_M29B_CAMERA_RELATIVE_MOVEMENT_ENABLED 1", "ARQEN_M28B_MOUSE_CAPTURE_ENABLED 1", "ARQEN_M26_KEY_BINDING_COUNT 7", "ARQEN_M27_PERSPECTIVE_CAMERA_ENABLED 1")) {
        if (-not $config.Contains($marker)) { Fail-M29B "config missing marker: $marker" }
    }

    if ($BuildNative -or $Run) {
        $builder = Join-Path $RepoRoot "Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1"
        if (-not (Test-Path $builder)) { Fail-M29B "native build helper missing: $builder" }
        if ([string]::IsNullOrWhiteSpace($Renderer)) {
            & $builder -IrPath $irPath -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m29b_dx12_ue_style_viewport_navigation_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        } else {
            & $builder -IrPath $irPath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m29b_dx12_ue_style_viewport_navigation_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        }
    }

    if (-not $Quiet) { Write-Host "PASS|m29b_dx12_ue_style_viewport_navigation_scene|source=$SourcePath|out=$OutDir|keep_open=$([bool]$KeepOpen)|fps=$TargetFps" }
} finally {
    Pop-Location
}
