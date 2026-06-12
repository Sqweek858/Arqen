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

function Fail-M27C {
    param([string]$Message)
    throw "M27C DX12 perspective depth scene failed: $Message"
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_perspective_depth_scene_m27c.arq"
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $RepoRoot "Build\M27C"
}
if (-not (Test-Path $SourcePath)) { Fail-M27C "source not found: $SourcePath" }
if ($FrameCount -lt 1) { Fail-M27C "FrameCount must be positive. Use -KeepOpen for an indefinite window." }
if ($TargetFps -lt 1) { Fail-M27C "TargetFps must be positive." }
if ($HoldMilliseconds -lt 1) { Fail-M27C "HoldMilliseconds must be positive." }

$driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
if (-not (Test-Path $driver)) { Fail-M27C "compiler driver not found: $driver" }

Push-Location $RepoRoot
try {
    & $driver $SourcePath *> $null
    if ($LASTEXITCODE -ne 0) { Fail-M27C "compiler failed for $SourcePath with exit $LASTEXITCODE. Rebuild the driver with .\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail if the exe is stale." }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $irPath = Join-Path $RepoRoot ("Build\IR\{0}.arqir" -f $stem)
    if (-not (Test-Path $irPath)) { Fail-M27C "expected IR was not generated: $irPath" }

    $irText = Get-Content $irPath -Raw
    foreach ($marker in @("DX12_CAMERA", "DX12_CAMERA_USE", "DX12_CAMERA_PROJECTION", "DX12_CAMERA_TRANSFORM", "DX12_OBJECT_TRANSFORM", "DX12_DRAW_OBJECT")) {
        if (-not $irText.Contains($marker)) { Fail-M27C "compiled IR does not contain $marker. Rebuild the driver from M27 source." }
    }
    foreach ($marker in @("projection=perspective", "property=rotation", "property=fov_y_degrees", "property=near_plane", "property=far_plane")) {
        if (-not $irText.Contains($marker)) { Fail-M27C "compiled IR missing perspective camera marker: $marker" }
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $lowerer = Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1"
    if (-not (Test-Path $lowerer)) { Fail-M27C "lowerer missing: $lowerer" }

    if ([string]::IsNullOrWhiteSpace($Renderer)) {
        & $lowerer -IrPath $irPath -OutDir $OutDir -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    } else {
        & $lowerer -IrPath $irPath -OutDir $OutDir -Renderer $Renderer -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    }

    $manifestPath = Join-Path $OutDir "dx12_clear_manifest.generated.txt"
    $configPath = Join-Path $OutDir "dx12_clear_config.generated.h"
    if (-not (Test-Path $manifestPath)) { Fail-M27C "manifest was not generated: $manifestPath" }
    if (-not (Test-Path $configPath)) { Fail-M27C "config header was not generated: $configPath" }

    $manifest = Get-Content $manifestPath -Raw
    $config = Get-Content $configPath -Raw
    foreach ($marker in @("M27_DEPTH_BUFFER|True", "M27_CAMERA_PROJECTION|perspective", "M27_PERSPECTIVE_CAMERA|True", "M27_CAMERA_ROTATION|", "M27_CAMERA_FOV|", "M27_CAMERA_NEAR|", "M27_CAMERA_FAR|")) {
        if (-not $manifest.Contains($marker)) { Fail-M27C "manifest missing marker: $marker" }
    }
    foreach ($marker in @("ARQEN_M27_DEPTH_BUFFER_ENABLED 1", 'ARQEN_M27_CAMERA_PROJECTION "perspective"', "ARQEN_M27_PERSPECTIVE_CAMERA_ENABLED 1", "ARQEN_M27_PERSPECTIVE_CAMERA_DATA")) {
        if (-not $config.Contains($marker)) { Fail-M27C "config missing marker: $marker" }
    }

    if ($BuildNative -or $Run) {
        $builder = Join-Path $RepoRoot "Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1"
        if (-not (Test-Path $builder)) { Fail-M27C "native build helper missing: $builder" }
        if ([string]::IsNullOrWhiteSpace($Renderer)) {
            & $builder -IrPath $irPath -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m27c_dx12_perspective_depth_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        } else {
            & $builder -IrPath $irPath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m27c_dx12_perspective_depth_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        }
    }

    if (-not $Quiet) {
        Write-Host "PASS|m27c_dx12_perspective_depth_scene|source=$SourcePath|out=$OutDir|keep_open=$([bool]$KeepOpen)|fps=$TargetFps"
    }
} finally {
    Pop-Location
}
