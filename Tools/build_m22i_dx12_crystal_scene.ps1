param(
    [string]$SourcePath = "",
    [string]$Renderer = "",
    [string]$RepoRoot = "",
    [Alias("Frames")]
    [int]$FrameCount = 480,
    [Alias("Fps")]
    [int]$TargetFps = 60,
    [Alias("Hold")]
    [int]$HoldMilliseconds = 8000,
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

function Fail-M22I {
    param([string]$Message)
    throw "M22I DX12 crystal scene failed: $Message"
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_crystal_scene_m22i.arq"
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $RepoRoot "Build\M22I"
}
if (-not (Test-Path $SourcePath)) { Fail-M22I "source not found: $SourcePath" }
if ($FrameCount -lt 1) { Fail-M22I "FrameCount must be positive. Use -KeepOpen for an indefinite window." }
if ($TargetFps -lt 1) { Fail-M22I "TargetFps must be positive." }
if ($HoldMilliseconds -lt 1) { Fail-M22I "HoldMilliseconds must be positive." }

$driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
if (-not (Test-Path $driver)) { Fail-M22I "compiler driver not found: $driver" }

Push-Location $RepoRoot
try {
    & $driver $SourcePath *> $null
    if ($LASTEXITCODE -ne 0) { Fail-M22I "compiler failed for $SourcePath with exit $LASTEXITCODE" }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $irPath = Join-Path $RepoRoot ("Build\IR\{0}.arqir" -f $stem)
    if (-not (Test-Path $irPath)) { Fail-M22I "expected IR was not generated: $irPath" }

    $irText = Get-Content $irPath -Raw
    foreach ($marker in @("DX12_CLEAR_READY", "DX12_FRAME", "DX12_SHADER", "DX12_PIPELINE", "DX12_PIPELINE_BIND", "DX12_VERTEX_BUFFER", "DX12_VERTEX_BUFFER_BIND", "DX12_DRAW", "DX12_CONSTANT_BUFFER", "DX12_ANIMATE_COLOR")) {
        if (-not $irText.Contains($marker)) { Fail-M22I "compiled IR does not contain $marker." }
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $lowerer = Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1"
    if (-not (Test-Path $lowerer)) { Fail-M22I "M20E1/M21/M22 lowerer missing: $lowerer" }

    if ([string]::IsNullOrWhiteSpace($Renderer)) {
        & $lowerer -IrPath $irPath -OutDir $OutDir -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    } else {
        & $lowerer -IrPath $irPath -OutDir $OutDir -Renderer $Renderer -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    }

    $manifestPath = Join-Path $OutDir "dx12_clear_manifest.generated.txt"
    $configPath = Join-Path $OutDir "dx12_clear_config.generated.h"
    if (-not (Test-Path $manifestPath)) { Fail-M22I "manifest was not generated: $manifestPath" }
    if (-not (Test-Path $configPath)) { Fail-M22I "config header was not generated: $configPath" }

    $manifest = Get-Content $manifestPath -Raw
    $config = Get-Content $configPath -Raw
    $vertexLine = ($manifest -split "`r?`n" | Where-Object { $_ -like "VERTEX_COUNT|*" } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($vertexLine)) { Fail-M22I "manifest missing VERTEX_COUNT." }
    $vertexCount = [int]($vertexLine.Split('|')[1])
    if ($vertexCount -lt 60) { Fail-M22I "M22 crystal scene expects at least 60 generated vertices, got $vertexCount." }
    foreach ($marker in @("M22_MINI_SCENE|True", "M22_VERTEX_CLUSTER|vertices=", "TRIANGLE_MODE|native_triangle_smoke", "COLOR_ANIMATION|True")) {
        if (-not $manifest.Contains($marker)) { Fail-M22I "manifest missing marker: $marker" }
    }
    foreach ($marker in @("ARQEN_M22_MINI_SCENE 1", "ARQEN_M22_VERTEX_CLUSTER_COUNT", "ARQEN_M21C_VERTEX_DATA", "ARQEN_M21H_COLOR_ANIMATION_ENABLED 1")) {
        if (-not $config.Contains($marker)) { Fail-M22I "config missing marker: $marker" }
    }
    if ($KeepOpen) {
        if (-not $manifest.Contains("M22_KEEP_OPEN|True")) { Fail-M22I "keep-open manifest marker missing." }
        if (-not $config.Contains("ARQEN_M22_KEEP_OPEN 1")) { Fail-M22I "keep-open config marker missing." }
        if (-not $config.Contains("ARQEN_M21F_FRAME_COUNT 0")) { Fail-M22I "keep-open frame count macro must be zero/infinite." }
    }

    if ($BuildNative -or $Run) {
        $builder = Join-Path $RepoRoot "Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1"
        if (-not (Test-Path $builder)) { Fail-M22I "native build helper missing: $builder" }
        if ([string]::IsNullOrWhiteSpace($Renderer)) {
            & $builder -IrPath $irPath -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m22i_dx12_crystal_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        } else {
            & $builder -IrPath $irPath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $OutDir -ExeName "m22i_dx12_crystal_scene.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        }
    }

    if (-not $Quiet) {
        Write-Host "PASS|m22i_dx12_crystal_scene|source=$SourcePath|out=$OutDir|vertices=$vertexCount|frames=$(if ($KeepOpen) { 0 } else { $FrameCount })|fps=$TargetFps|keep_open=$([bool]$KeepOpen)"
    }
} finally {
    Pop-Location
}
