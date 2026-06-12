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
function Fail-M28B { param([string]$Message) throw "M28B DX12 full peripheral input scene failed: $Message" }

if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (git rev-parse --show-toplevel).Trim() }
if ([string]::IsNullOrWhiteSpace($SourcePath)) { $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_full_peripheral_input_scene_m28b.arq" }
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $RepoRoot "Build\M28B" }
if (-not (Test-Path $SourcePath)) { Fail-M28B "source not found: $SourcePath" }
if ($FrameCount -lt 1) { Fail-M28B "FrameCount must be positive. Use -KeepOpen for an indefinite window." }
if ($TargetFps -lt 1) { Fail-M28B "TargetFps must be positive." }
if ($HoldMilliseconds -lt 1) { Fail-M28B "HoldMilliseconds must be positive." }

$driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
if (-not (Test-Path $driver)) { Fail-M28B "compiler driver not found: $driver" }

Push-Location $RepoRoot
try {
    & $driver $SourcePath *> $null
    if ($LASTEXITCODE -ne 0) { Fail-M28B "compiler failed for $SourcePath with exit $LASTEXITCODE. Rebuild the driver with .\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail if the exe is stale." }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $irPath = Join-Path $RepoRoot ("Build\IR\{0}.arqir" -f $stem)
    if (-not (Test-Path $irPath)) { Fail-M28B "expected IR was not generated: $irPath" }

    $irText = Get-Content $irPath -Raw
    foreach ($marker in @("DX12_MOUSE_CAPTURE", "DX12_MOUSE_MOVE", "DX12_MOUSE_BUTTON", "DX12_MOUSE_WHEEL", "DX12_KEY_BINDING", "DX12_OBJECT_PRIMITIVE", "DX12_CAMERA_PROJECTION")) {
        if (-not $irText.Contains($marker)) { Fail-M28B "compiled IR does not contain $marker. Rebuild the driver from M28B source." }
    }
    foreach ($marker in @("window=MainWindow", "target=MainCamera", "button=Left", "button=Right", "button=Middle", "projection=perspective", "kind=box")) {
        if (-not $irText.Contains($marker)) { Fail-M28B "compiled IR missing M28B marker: $marker" }
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $lowerer = Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1"
    if (-not (Test-Path $lowerer)) { Fail-M28B "lowerer missing: $lowerer" }

    if ([string]::IsNullOrWhiteSpace($Renderer)) {
        & $lowerer -IrPath $irPath -OutDir $OutDir -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    } else {
        & $lowerer -IrPath $irPath -OutDir $OutDir -Renderer $Renderer -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    }

    $manifestPath = Join-Path $OutDir "dx12_clear_manifest.generated.txt"
    $configPath = Join-Path $OutDir "dx12_clear_config.generated.h"
    if (-not (Test-Path $manifestPath)) { Fail-M28B "manifest was not generated: $manifestPath" }
    if (-not (Test-Path $configPath)) { Fail-M28B "config header was not generated: $configPath" }

    $manifest = Get-Content $manifestPath -Raw
    $config = Get-Content $configPath -Raw
    foreach ($marker in @("M28B_PERIPHERAL_INPUT|True", "M28B_MOUSE_CAPTURE|True", "M28B_MOUSE_MOVE_BINDINGS|1", "M28B_MOUSE_BUTTON_BINDINGS|3", "M28B_MOUSE_WHEEL_BINDINGS|1", "M28_BOX_PRIMITIVE|True", "M27_PERSPECTIVE_CAMERA|True")) {
        if (-not $manifest.Contains($marker)) { Fail-M28B "manifest missing marker: $marker" }
    }
    foreach ($marker in @("ARQEN_M28B_PERIPHERAL_INPUT_ENABLED 1", "ARQEN_M28B_MOUSE_CAPTURE_ENABLED 1", "ARQEN_M28B_MOUSE_MOVE_BINDING_COUNT 1", "ARQEN_M28B_MOUSE_BUTTON_BINDING_COUNT 3", "ARQEN_M28B_MOUSE_WHEEL_BINDING_COUNT 1", "ARQEN_M27_PERSPECTIVE_CAMERA_ENABLED 1")) {
        if (-not $config.Contains($marker)) { Fail-M28B "config missing marker: $marker" }
    }

    if ($BuildNative -or $Run) {
        $builder = Join-Path $RepoRoot "Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1"
        if (-not (Test-Path $builder)) { Fail-M28B "native build helper missing: $builder" }
        if ([string]::IsNullOrWhiteSpace($Renderer)) {
            & $builder -IrPath $irPath -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m28b_dx12_full_peripheral_input_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        } else {
            & $builder -IrPath $irPath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m28b_dx12_full_peripheral_input_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        }
    }

    if (-not $Quiet) { Write-Host "PASS|m28b_dx12_full_peripheral_input_scene|source=$SourcePath|out=$OutDir|keep_open=$([bool]$KeepOpen)|fps=$TargetFps" }
} finally {
    Pop-Location
}
