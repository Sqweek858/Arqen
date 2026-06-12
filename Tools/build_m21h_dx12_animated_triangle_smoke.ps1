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
if ($FrameCount -lt 1) { throw "M21H frame count must be positive." }
if ($TargetFps -lt 1) { throw "M21H target fps must be positive." }

$builder = Join-Path $RepoRoot "Tools\build_m21d_dx12_triangle_smoke.ps1"
if (-not (Test-Path $builder)) {
    throw "M21H requires M21D wrapper: $builder"
}

$outDir = if ([string]::IsNullOrWhiteSpace($OutDir)) { Join-Path $RepoRoot "Build\M21H" } else { $OutDir }
if ([string]::IsNullOrWhiteSpace($Renderer)) {
    & $builder -SourcePath $SourcePath -RepoRoot $RepoRoot -OutDir $outDir -FrameCount $FrameCount -TargetFps $TargetFps -HoldMilliseconds $HoldMilliseconds -KeepOpen:$KeepOpen -BuildNative:$BuildNative -Run:$Run -Quiet:$Quiet
} else {
    & $builder -SourcePath $SourcePath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $outDir -FrameCount $FrameCount -TargetFps $TargetFps -HoldMilliseconds $HoldMilliseconds -KeepOpen:$KeepOpen -BuildNative:$BuildNative -Run:$Run -Quiet:$Quiet
}

if (-not $Quiet) {
    Write-Host "PASS|m21h_dx12_animated_triangle_smoke|out=$outDir|frames=$FrameCount|fps=$TargetFps"
}
