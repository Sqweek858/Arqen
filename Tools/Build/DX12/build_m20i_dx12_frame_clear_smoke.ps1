param(
    [string]$SourcePath = "",
    [string]$Renderer = "",
    [string]$RepoRoot = "",
    [int]$HoldMilliseconds = 1600,
    [switch]$BuildNative,
    [switch]$Run,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Fail-M20I {
    param([string]$Message)
    throw "M20I DX12 frame clear smoke failed: $Message"
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_frame_clear_smoke_m20h.arq"
}
if (-not (Test-Path $SourcePath)) { Fail-M20I "source not found: $SourcePath" }
if ($HoldMilliseconds -lt 1) { Fail-M20I "HoldMilliseconds must be positive." }

$driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
if (-not (Test-Path $driver)) { Fail-M20I "compiler driver not found: $driver" }

Push-Location $RepoRoot
try {
    & $driver $SourcePath *> $null
    if ($LASTEXITCODE -ne 0) { Fail-M20I "compiler failed for $SourcePath with exit $LASTEXITCODE" }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $irPath = Join-Path $RepoRoot ("Build\IR\{0}.arqir" -f $stem)
    if (-not (Test-Path $irPath)) { Fail-M20I "expected IR was not generated: $irPath" }

    $irText = Get-Content $irPath -Raw
    if (-not $irText.Contains("DX12_CLEAR_READY")) { Fail-M20I "compiled IR does not contain DX12_CLEAR_READY." }
    if (-not $irText.Contains("DX12_FRAME")) { Fail-M20I "compiled IR does not contain DX12_FRAME." }

    $outDir = Join-Path $RepoRoot "Build\M20I"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    $lowerer = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
    if (-not (Test-Path $lowerer)) { Fail-M20I "M20E1/M20H lowerer missing: $lowerer" }

    if ([string]::IsNullOrWhiteSpace($Renderer)) {
        & $lowerer -IrPath $irPath -OutDir $outDir -RequireFrame -HoldMilliseconds $HoldMilliseconds -Quiet
    } else {
        & $lowerer -IrPath $irPath -OutDir $outDir -Renderer $Renderer -RequireFrame -HoldMilliseconds $HoldMilliseconds -Quiet
    }

    $manifest = Join-Path $outDir "dx12_clear_manifest.generated.txt"
    $config = Join-Path $outDir "dx12_clear_config.generated.h"
    if (-not (Test-Path $manifest)) { Fail-M20I "manifest was not generated: $manifest" }
    if (-not (Test-Path $config)) { Fail-M20I "config header was not generated: $config" }

    $manifestText = Get-Content $manifest -Raw
    foreach ($marker in @("RENDERER|MainRenderer", "WINDOW|MainWindow", "TITLE|Arqen M20H DX12 Frame Clear", "WIDTH|1280", "HEIGHT|720", "COLOR_HEX|#101820", "FRAME_MODE|oneshot_clear_frame", "FRAME_SEQUENCE|begin,clear,end,present")) {
        if (-not $manifestText.Contains($marker)) { Fail-M20I "manifest missing marker: $marker" }
    }

    if ($BuildNative -or $Run) {
        $builder = Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1"
        if (-not (Test-Path $builder)) { Fail-M20I "native build helper missing: $builder" }
        $nativeOut = Join-Path $RepoRoot "Build\M20I"
        if ([string]::IsNullOrWhiteSpace($Renderer)) {
            & $builder -IrPath $irPath -RepoRoot $RepoRoot -OutDir $nativeOut -ExeName "m20i_dx12_frame_clear_from_ir.exe" -RequireFrame -HoldMilliseconds $HoldMilliseconds -Run:$Run
        } else {
            & $builder -IrPath $irPath -Renderer $Renderer -RepoRoot $RepoRoot -OutDir $nativeOut -ExeName "m20i_dx12_frame_clear_from_ir.exe" -RequireFrame -HoldMilliseconds $HoldMilliseconds -Run:$Run
        }
    }

    if (-not $Quiet) {
        Write-Host "PASS|m20i_dx12_frame_clear_smoke|ir=$irPath|manifest=$manifest|config=$config"
    }
} finally {
    Pop-Location
}
