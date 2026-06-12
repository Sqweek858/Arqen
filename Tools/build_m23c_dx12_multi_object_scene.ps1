param(
    [string]$SourcePath = "",
    [string]$Renderer = "",
    [string]$RepoRoot = "",
    [Alias("Frames")]
    [int]$FrameCount = 600,
    [Alias("Fps")]
    [int]$TargetFps = 60,
    [Alias("Hold")]
    [int]$HoldMilliseconds = 10000,
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

function Fail-M23C {
    param([string]$Message)
    throw "M23C DX12 multi-object scene failed: $Message"
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_multi_object_scene_m23c.arq"
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $RepoRoot "Build\M23C"
}
if (-not (Test-Path $SourcePath)) { Fail-M23C "source not found: $SourcePath" }
if ($FrameCount -lt 1) { Fail-M23C "FrameCount must be positive. Use -KeepOpen for an indefinite window." }
if ($TargetFps -lt 1) { Fail-M23C "TargetFps must be positive." }
if ($HoldMilliseconds -lt 1) { Fail-M23C "HoldMilliseconds must be positive." }

$driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
if (-not (Test-Path $driver)) { Fail-M23C "compiler driver not found: $driver" }

Push-Location $RepoRoot
try {
    & $driver $SourcePath *> $null
    if ($LASTEXITCODE -ne 0) { Fail-M23C "compiler failed for $SourcePath with exit $LASTEXITCODE. Rebuild the driver with .\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -Case m23 if the exe is stale." }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $irPath = Join-Path $RepoRoot ("Build\IR\{0}.arqir" -f $stem)
    if (-not (Test-Path $irPath)) { Fail-M23C "expected IR was not generated: $irPath" }

    $irText = Get-Content $irPath -Raw
    foreach ($marker in @("DX12_CLEAR_READY", "DX12_FRAME", "DX12_SHADER", "DX12_PIPELINE", "DX12_VERTEX_BUFFER", "DX12_OBJECT", "DX12_OBJECT_BIND", "DX12_DRAW_OBJECT")) {
        if (-not $irText.Contains($marker)) { Fail-M23C "compiled IR does not contain $marker. This usually means the driver was not rebuilt from the M23 parser source." }
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $lowerer = Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1"
    if (-not (Test-Path $lowerer)) { Fail-M23C "M20E1/M21/M22/M23 lowerer missing: $lowerer" }

    if ([string]::IsNullOrWhiteSpace($Renderer)) {
        & $lowerer -IrPath $irPath -OutDir $OutDir -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    } else {
        & $lowerer -IrPath $irPath -OutDir $OutDir -Renderer $Renderer -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    }

    $manifestPath = Join-Path $OutDir "dx12_clear_manifest.generated.txt"
    $configPath = Join-Path $OutDir "dx12_clear_config.generated.h"
    if (-not (Test-Path $manifestPath)) { Fail-M23C "manifest was not generated: $manifestPath" }
    if (-not (Test-Path $configPath)) { Fail-M23C "config header was not generated: $configPath" }

    $manifest = Get-Content $manifestPath -Raw
    $config = Get-Content $configPath -Raw
    foreach ($marker in @("M23_SCENE_OBJECTS|", "M23_OBJECT_BINDINGS|", "M23_DRAW_CALLS|", "M23_OBJECT_MODE|True", "M23_MULTI_DRAW|True", "TRIANGLE_MODE|native_m23_scene_multi_draw")) {
        if (-not $manifest.Contains($marker)) { Fail-M23C "manifest missing marker: $marker" }
    }
    foreach ($marker in @("ARQEN_M23_OBJECT_METADATA 1", "ARQEN_M23_OBJECT_MODE 1", "ARQEN_M23_MULTI_DRAW_ENABLED 1", "ARQEN_M23_DRAW_CALL_COUNT", "ARQEN_M23_DRAW_CALL_DATA")) {
        if (-not $config.Contains($marker)) { Fail-M23C "config missing marker: $marker" }
    }

    $drawLine = ($manifest -split "`r?`n" | Where-Object { $_ -like "M23_DRAW_CALLS|*" } | Select-Object -First 1)
    $drawCount = [int]($drawLine.Split('|')[1])
    if ($drawCount -lt 2) { Fail-M23C "expected at least two M23 draw calls, got $drawCount." }

    if ($KeepOpen) {
        if (-not $manifest.Contains("M22_KEEP_OPEN|True")) { Fail-M23C "keep-open manifest marker missing." }
        if (-not $config.Contains("ARQEN_M22_KEEP_OPEN 1")) { Fail-M23C "keep-open config marker missing." }
        if (-not $config.Contains("ARQEN_M21F_FRAME_COUNT 0")) { Fail-M23C "keep-open frame count macro must be zero/infinite." }
    }

    if ($BuildNative -or $Run) {
        $builder = Join-Path $RepoRoot "Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1"
        if (-not (Test-Path $builder)) { Fail-M23C "native build helper missing: $builder" }
        if ([string]::IsNullOrWhiteSpace($Renderer)) {
            & $builder -IrPath $irPath -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m23c_dx12_multi_object_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        } else {
            & $builder -IrPath $irPath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m23c_dx12_multi_object_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        }
    }

    if (-not $Quiet) {
        Write-Host "PASS|m23c_dx12_multi_object_scene|source=$SourcePath|out=$OutDir|draw_calls=$drawCount|frames=$(if ($KeepOpen) { 0 } else { $FrameCount })|fps=$TargetFps|keep_open=$([bool]$KeepOpen)"
    }
} finally {
    Pop-Location
}
