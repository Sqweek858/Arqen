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

function Fail-M28A {
    param([string]$Message)
    throw "M27D/M28A DX12 window style + box scene failed: $Message"
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_window_style_box_scene_m28a.arq"
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $RepoRoot "Build\M28A"
}
if (-not (Test-Path $SourcePath)) { Fail-M28A "source not found: $SourcePath" }
if ($FrameCount -lt 1) { Fail-M28A "FrameCount must be positive. Use -KeepOpen for an indefinite window." }
if ($TargetFps -lt 1) { Fail-M28A "TargetFps must be positive." }
if ($HoldMilliseconds -lt 1) { Fail-M28A "HoldMilliseconds must be positive." }

$driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
if (-not (Test-Path $driver)) { Fail-M28A "compiler driver not found: $driver" }

Push-Location $RepoRoot
try {
    & $driver $SourcePath *> $null
    if ($LASTEXITCODE -ne 0) { Fail-M28A "compiler failed for $SourcePath with exit $LASTEXITCODE. Rebuild the driver with .\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail if the exe is stale." }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $irPath = Join-Path $RepoRoot ("Build\IR\{0}.arqir" -f $stem)
    if (-not (Test-Path $irPath)) { Fail-M28A "expected IR was not generated: $irPath" }

    $irText = Get-Content $irPath -Raw
    foreach ($marker in @("DX12_OBJECT_PRIMITIVE", "DX12_OBJECT", "DX12_DRAW_OBJECT", "DX12_OBJECT_TRANSFORM", "DX12_CAMERA_PROJECTION", "DX12_CAMERA_TRANSFORM")) {
        if (-not $irText.Contains($marker)) { Fail-M28A "compiled IR does not contain $marker. Rebuild the driver from M27D/M28A source." }
    }
    foreach ($marker in @("kind=box", "object=CubeA", "object=CubeB", "op=window_style_title_bar_color", "op=window_style_title_text_color", "projection=perspective")) {
        if (-not $irText.Contains($marker)) { Fail-M28A "compiled IR missing M27D/M28A marker: $marker" }
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $lowerer = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
    if (-not (Test-Path $lowerer)) { Fail-M28A "lowerer missing: $lowerer" }

    if ([string]::IsNullOrWhiteSpace($Renderer)) {
        & $lowerer -IrPath $irPath -OutDir $OutDir -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    } else {
        & $lowerer -IrPath $irPath -OutDir $OutDir -Renderer $Renderer -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    }

    $manifestPath = Join-Path $OutDir "dx12_clear_manifest.generated.txt"
    $configPath = Join-Path $OutDir "dx12_clear_config.generated.h"
    if (-not (Test-Path $manifestPath)) { Fail-M28A "manifest was not generated: $manifestPath" }
    if (-not (Test-Path $configPath)) { Fail-M28A "config header was not generated: $configPath" }

    $manifest = Get-Content $manifestPath -Raw
    $config = Get-Content $configPath -Raw
    foreach ($marker in @("M27D_NATIVE_WINDOW_STYLE|True", "M27D_TITLE_BAR_COLOR|#000000", "M27D_TITLE_TEXT_COLOR|#FFFFFF", "M28_BOX_PRIMITIVE|True", "M28_BOX_PRIMITIVE_COUNT|2", "OBJECT_PRIMITIVE|object=CubeA|kind=box", "OBJECT_PRIMITIVE|object=CubeB|kind=box", "M27_PERSPECTIVE_CAMERA|True")) {
        if (-not $manifest.Contains($marker)) { Fail-M28A "manifest missing marker: $marker" }
    }
    foreach ($marker in @("ARQEN_M27D_TITLE_BAR_ENABLED 1", "ARQEN_M27D_TITLE_TEXT_ENABLED 1", 'ARQEN_M27D_TITLE_BAR_COLOR "#000000"', 'ARQEN_M27D_TITLE_TEXT_COLOR "#FFFFFF"', "ARQEN_M28_BOX_PRIMITIVE_ENABLED 1", "ARQEN_M28_BOX_PRIMITIVE_COUNT 2", "ARQEN_M27_PERSPECTIVE_CAMERA_ENABLED 1")) {
        if (-not $config.Contains($marker)) { Fail-M28A "config missing marker: $marker" }
    }

    if ($BuildNative -or $Run) {
        $builder = Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1"
        if (-not (Test-Path $builder)) { Fail-M28A "native build helper missing: $builder" }
        if ([string]::IsNullOrWhiteSpace($Renderer)) {
            & $builder -IrPath $irPath -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m28a_dx12_window_style_box_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        } else {
            & $builder -IrPath $irPath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m28a_dx12_window_style_box_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        }
    }

    if (-not $Quiet) {
        Write-Host "PASS|m28a_dx12_window_style_box_scene|source=$SourcePath|out=$OutDir|keep_open=$([bool]$KeepOpen)|fps=$TargetFps"
    }
} finally {
    Pop-Location
}
