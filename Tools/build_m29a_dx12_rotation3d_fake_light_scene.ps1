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
function Fail-M29A { param([string]$Message) throw "M29A DX12 rotation3d fake light scene failed: $Message" }

if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (git rev-parse --show-toplevel).Trim() }
if ([string]::IsNullOrWhiteSpace($SourcePath)) { $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_rotation3d_fake_light_scene_m29a.arq" }
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $RepoRoot "Build\M29A" }
if (-not (Test-Path $SourcePath)) { Fail-M29A "source not found: $SourcePath" }
if ($FrameCount -lt 1) { Fail-M29A "FrameCount must be positive. Use -KeepOpen for an indefinite window." }
if ($TargetFps -lt 1) { Fail-M29A "TargetFps must be positive." }
if ($HoldMilliseconds -lt 1) { Fail-M29A "HoldMilliseconds must be positive." }

$driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
if (-not (Test-Path $driver)) { Fail-M29A "compiler driver not found: $driver" }

Push-Location $RepoRoot
try {
    & $driver $SourcePath *> $null
    if ($LASTEXITCODE -ne 0) { Fail-M29A "compiler failed for $SourcePath with exit $LASTEXITCODE. Rebuild the driver with .\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail if the exe is stale." }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $irPath = Join-Path $RepoRoot ("Build\IR\{0}.arqir" -f $stem)
    if (-not (Test-Path $irPath)) { Fail-M29A "expected IR was not generated: $irPath" }

    $irText = Get-Content $irPath -Raw
    foreach ($marker in @("DX12_OBJECT_TRANSFORM", "property=rotation", "DX12_DIRECTIONAL_LIGHT", "DX12_LIGHT_USE", "DX12_LIGHT_PROPERTY", "DX12_OBJECT_PRIMITIVE", "DX12_CAMERA_PROJECTION")) {
        if (-not $irText.Contains($marker)) { Fail-M29A "compiled IR does not contain $marker. Rebuild the driver from M28C/M29A source." }
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $lowerer = Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1"
    if (-not (Test-Path $lowerer)) { Fail-M29A "lowerer missing: $lowerer" }

    if ([string]::IsNullOrWhiteSpace($Renderer)) {
        & $lowerer -IrPath $irPath -OutDir $OutDir -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    } else {
        & $lowerer -IrPath $irPath -OutDir $OutDir -Renderer $Renderer -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    }

    $manifestPath = Join-Path $OutDir "dx12_clear_manifest.generated.txt"
    $configPath = Join-Path $OutDir "dx12_clear_config.generated.h"
    if (-not (Test-Path $manifestPath)) { Fail-M29A "manifest was not generated: $manifestPath" }
    if (-not (Test-Path $configPath)) { Fail-M29A "config header was not generated: $configPath" }

    $manifest = Get-Content $manifestPath -Raw
    $config = Get-Content $configPath -Raw
    foreach ($marker in @("M28C_OBJECT_ROTATION_3D|True", "M29_FAKE_LIGHTING|True", "M29_DIRECTIONAL_LIGHT|KeyLight", "M28_BOX_PRIMITIVE|True", "M27_PERSPECTIVE_CAMERA|True")) {
        if (-not $manifest.Contains($marker)) { Fail-M29A "manifest missing marker: $marker" }
    }
    foreach ($marker in @("ARQEN_M28C_OBJECT_ROTATION_3D 1", "ARQEN_M29_FAKE_LIGHTING_ENABLED 1", "ARQEN_M29_DIRECTIONAL_LIGHT_DATA", "ARQEN_M27_PERSPECTIVE_CAMERA_ENABLED 1")) {
        if (-not $config.Contains($marker)) { Fail-M29A "config missing marker: $marker" }
    }

    if ($BuildNative -or $Run) {
        $builder = Join-Path $RepoRoot "Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1"
        if (-not (Test-Path $builder)) { Fail-M29A "native build helper missing: $builder" }
        if ([string]::IsNullOrWhiteSpace($Renderer)) {
            & $builder -IrPath $irPath -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m29a_dx12_rotation3d_fake_light_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        } else {
            & $builder -IrPath $irPath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m29a_dx12_rotation3d_fake_light_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        }
    }

    if (-not $Quiet) { Write-Host "PASS|m29a_dx12_rotation3d_fake_light_scene|source=$SourcePath|out=$OutDir|keep_open=$([bool]$KeepOpen)|fps=$TargetFps" }
} finally {
    Pop-Location
}
