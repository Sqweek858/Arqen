param(
    [string]$SourcePath = "",
    [string]$Renderer = "",
    [string]$RepoRoot = "",
    [int]$HoldMilliseconds = 2000,
    [int]$FrameCount = 0,
    [int]$TargetFps = 60,
    [Alias("Interactive")]
    [switch]$KeepOpen,
    [string]$OutDir = "",
    [switch]$BuildNative,
    [switch]$Run,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Fail-M21D {
    param([string]$Message)
    throw "M21D DX12 triangle smoke failed: $Message"
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_first_triangle_m21d.arq"
}
if (-not (Test-Path $SourcePath)) { Fail-M21D "source not found: $SourcePath" }
if ($HoldMilliseconds -lt 1) { Fail-M21D "HoldMilliseconds must be positive." }
if ($FrameCount -lt 0) { Fail-M21D "FrameCount must be zero/auto or positive." }
if ($TargetFps -lt 1) { Fail-M21D "TargetFps must be positive." }

$driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
if (-not (Test-Path $driver)) { Fail-M21D "compiler driver not found: $driver" }

Push-Location $RepoRoot
try {
    & $driver $SourcePath *> $null
    if ($LASTEXITCODE -ne 0) { Fail-M21D "compiler failed for $SourcePath with exit $LASTEXITCODE" }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $irPath = Join-Path $RepoRoot ("Build\IR\{0}.arqir" -f $stem)
    if (-not (Test-Path $irPath)) { Fail-M21D "expected IR was not generated: $irPath" }

    $irText = Get-Content $irPath -Raw
    foreach ($marker in @("DX12_CLEAR_READY", "DX12_FRAME", "DX12_SHADER", "DX12_PIPELINE", "DX12_PIPELINE_BIND", "DX12_VERTEX_BUFFER", "DX12_VERTEX_BUFFER_BIND", "DX12_DRAW")) {
        if (-not $irText.Contains($marker)) { Fail-M21D "compiled IR does not contain $marker." }
    }

    if ([string]::IsNullOrWhiteSpace($OutDir)) {
        $outDir = Join-Path $RepoRoot "Build\M21D"
    } else {
        $outDir = $OutDir
    }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    $lowerer = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
    if (-not (Test-Path $lowerer)) { Fail-M21D "M20E1/M20H/M21D lowerer missing: $lowerer" }

    if ([string]::IsNullOrWhiteSpace($Renderer)) {
        & $lowerer -IrPath $irPath -OutDir $outDir -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    } else {
        & $lowerer -IrPath $irPath -OutDir $outDir -Renderer $Renderer -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Quiet
    }

    $manifest = Join-Path $outDir "dx12_clear_manifest.generated.txt"
    $config = Join-Path $outDir "dx12_clear_config.generated.h"
    if (-not (Test-Path $manifest)) { Fail-M21D "manifest was not generated: $manifest" }
    if (-not (Test-Path $config)) { Fail-M21D "config header was not generated: $config" }

    $manifestText = Get-Content $manifest -Raw
    foreach ($marker in @("TRIANGLE_MODE|native_triangle_smoke", "SHADER|TriangleShader", "PIPELINE|TrianglePipeline", "TOPOLOGY|triangle_list", "VERTEX_BUFFER|TriangleVertices", "VERTEX_COUNT|3", "DRAW_VERTICES|3", "FRAME_SEQUENCE|begin,clear,end,present")) {
        if (-not $manifestText.Contains($marker)) { Fail-M21D "manifest missing marker: $marker" }
    }

    $configText = Get-Content $config -Raw
    foreach ($marker in @("ARQEN_M21D_TRIANGLE_ENABLED 1", "ARQEN_M21B_VERTEX_SHADER_PATH", "ARQEN_M21B_PIXEL_SHADER_PATH", "ARQEN_M21C_VERTEX_DATA", "ARQEN_M21C_DRAW_VERTEX_COUNT 3")) {
        if (-not $configText.Contains($marker)) { Fail-M21D "config missing marker: $marker" }
    }

    if ($BuildNative -or $Run) {
        $builder = Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1"
        if (-not (Test-Path $builder)) { Fail-M21D "native build helper missing: $builder" }
        $nativeOut = $outDir
        if ([string]::IsNullOrWhiteSpace($Renderer)) {
            & $builder -IrPath $irPath -RepoRoot $RepoRoot -OutDir $nativeOut -ExeName "m21d_dx12_triangle_smoke.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        } else {
            & $builder -IrPath $irPath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $nativeOut -ExeName "m21d_dx12_triangle_smoke.exe" -RequireFrame -RequireTriangle -HoldMilliseconds $HoldMilliseconds -FrameCount $FrameCount -TargetFps $TargetFps -KeepOpen:$KeepOpen -Run:$Run
        }
    }

    if (-not $Quiet) {
        Write-Host "PASS|m21d_dx12_triangle_smoke|ir=$irPath|manifest=$manifest|config=$config"
    }
} finally {
    Pop-Location
}
