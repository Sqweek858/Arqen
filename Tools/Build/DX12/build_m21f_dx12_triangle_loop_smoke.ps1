param(
    [string]$SourcePath = "",
    [string]$Renderer = "",
    [string]$RepoRoot = "",
    [int]$FrameCount = 180,
    [int]$TargetFps = 60,
    [int]$HoldMilliseconds = 3000,
    [switch]$BuildNative,
    [switch]$Run,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_first_triangle_m21d.arq"
}
if ($FrameCount -lt 1) { throw "M21F frame count must be positive." }
if ($TargetFps -lt 1) { throw "M21F target fps must be positive." }

$builder = Join-Path $RepoRoot "Tools\Build\DX12\build_m21d_dx12_triangle_smoke.ps1"
if (-not (Test-Path $builder)) {
    throw "M21F requires M21D wrapper: $builder"
}

$outDir = Join-Path $RepoRoot "Build\M21F"
if ([string]::IsNullOrWhiteSpace($Renderer)) {
    & $builder -SourcePath $SourcePath -RepoRoot $RepoRoot -OutDir $outDir -FrameCount $FrameCount -TargetFps $TargetFps -HoldMilliseconds $HoldMilliseconds -BuildNative:$BuildNative -Run:$Run -Quiet:$Quiet
} else {
    & $builder -SourcePath $SourcePath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $outDir -FrameCount $FrameCount -TargetFps $TargetFps -HoldMilliseconds $HoldMilliseconds -BuildNative:$BuildNative -Run:$Run -Quiet:$Quiet
}

if (-not $Quiet) {
    Write-Host "PASS|m21f_dx12_triangle_loop_smoke|out=$outDir|frames=$FrameCount|fps=$TargetFps"
}
