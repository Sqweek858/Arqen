param(
    [string]$SourcePath = "",
    [string]$Renderer = "",
    [string]$RepoRoot = "",
    [Alias("Frames")]
    [int]$FrameCount = 240,
    [Alias("Fps")]
    [int]$TargetFps = 60,
    [Alias("Hold")]
    [int]$HoldMilliseconds = 4000,
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

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_animated_triangle_m21h.arq"
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $RepoRoot "Build\M21I"
}
if ($FrameCount -lt 1) { throw "M21I frame count must be positive." }
$expectedFrameCount = if ($KeepOpen) { 0 } else { $FrameCount }
if ($TargetFps -lt 1) { throw "M21I target fps must be positive." }
if ($HoldMilliseconds -lt 1) { throw "M21I hold milliseconds must be positive." }

$builder = Join-Path $RepoRoot "Tools\build_m21h_dx12_animated_triangle_smoke.ps1"
if (-not (Test-Path $builder)) {
    throw "M21I requires M21H wrapper: $builder"
}

if ([string]::IsNullOrWhiteSpace($Renderer)) {
    & $builder -SourcePath $SourcePath -RepoRoot $RepoRoot -OutDir $OutDir -FrameCount $FrameCount -TargetFps $TargetFps -HoldMilliseconds $HoldMilliseconds -KeepOpen:$KeepOpen -BuildNative:$BuildNative -Run:$Run -Quiet:$Quiet
} else {
    & $builder -SourcePath $SourcePath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $OutDir -FrameCount $FrameCount -TargetFps $TargetFps -HoldMilliseconds $HoldMilliseconds -KeepOpen:$KeepOpen -BuildNative:$BuildNative -Run:$Run -Quiet:$Quiet
}

$manifestPath = Join-Path $OutDir "dx12_clear_manifest.generated.txt"
$configPath = Join-Path $OutDir "dx12_clear_config.generated.h"
if (-not (Test-Path $manifestPath)) { throw "M21I expected manifest was not generated: $manifestPath" }
if (-not (Test-Path $configPath)) { throw "M21I expected config was not generated: $configPath" }

$manifest = Get-Content $manifestPath -Raw
$config = Get-Content $configPath -Raw
foreach ($marker in @("M21I_SMOKE_POLISH|True", "M21I_RUNTIME_KNOBS|frames=$expectedFrameCount|fps=$TargetFps|hold_ms=$HoldMilliseconds", "COLOR_ANIMATION|True", "M21J_ANIMATION_HARDENING|selected_tint_only|single_pipeline_binding")) {
    if (-not $manifest.Contains($marker)) { throw "M21I manifest missing marker: $marker" }
}
foreach ($marker in @("ARQEN_M21I_SMOKE_POLISH 1", "ARQEN_M21I_RUNTIME_KNOBS_ENABLED 1", "ARQEN_M21I_FRAME_COUNT $expectedFrameCount", "ARQEN_M21I_TARGET_FPS $TargetFps", "ARQEN_M21J_ANIMATION_HARDENING 1")) {
    if (-not $config.Contains($marker)) { throw "M21I config missing marker: $marker" }
}

if (-not $Quiet) {
    Write-Host "PASS|m21i_dx12_color_animation_smoke_polish|out=$OutDir|frames=$FrameCount|fps=$TargetFps|hold=$HoldMilliseconds"
}
