param(
    [string]$SourcePath = "",
    [string]$Renderer = "",
    [string]$RepoRoot = "",
    [switch]$BuildNative,
    [switch]$Run,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Fail-M20F {
    param([string]$Message)
    throw "M20F DX12 clear smoke failed: $Message"
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $RepoRoot "Samples\DX12\dx12_clear_smoke_m20f.arq"
}

if (-not (Test-Path $SourcePath)) { Fail-M20F "source not found: $SourcePath" }

$driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
if (-not (Test-Path $driver)) { Fail-M20F "compiler driver not found: $driver" }

Push-Location $RepoRoot
try {
    & $driver $SourcePath *> $null
    if ($LASTEXITCODE -ne 0) { Fail-M20F "compiler failed for $SourcePath with exit $LASTEXITCODE" }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $irPath = Join-Path $RepoRoot ("Build\IR\{0}.arqir" -f $stem)
    if (-not (Test-Path $irPath)) { Fail-M20F "expected IR was not generated: $irPath" }

    $irText = Get-Content $irPath -Raw
    if (-not $irText.Contains("DX12_CLEAR_READY")) { Fail-M20F "compiled IR does not contain DX12_CLEAR_READY." }

    $outDir = Join-Path $RepoRoot "Build\M20F"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    $lowerer = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
    if (-not (Test-Path $lowerer)) { Fail-M20F "M20E1 lowerer missing: $lowerer" }

    if ([string]::IsNullOrWhiteSpace($Renderer)) {
        & $lowerer -IrPath $irPath -OutDir $outDir -Quiet
    } else {
        & $lowerer -IrPath $irPath -OutDir $outDir -Renderer $Renderer -Quiet
    }

    $manifest = Join-Path $outDir "dx12_clear_manifest.generated.txt"
    $config = Join-Path $outDir "dx12_clear_config.generated.h"
    if (-not (Test-Path $manifest)) { Fail-M20F "manifest was not generated: $manifest" }
    if (-not (Test-Path $config)) { Fail-M20F "config header was not generated: $config" }

    $manifestText = Get-Content $manifest -Raw
    foreach ($marker in @("RENDERER|MainRenderer", "WINDOW|MainWindow", "TITLE|Arqen M20F DX12 Clear", "WIDTH|1280", "HEIGHT|720", "COLOR_HEX|#101820")) {
        if (-not $manifestText.Contains($marker)) { Fail-M20F "manifest missing marker: $marker" }
    }

    if ($BuildNative -or $Run) {
        $builder = Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1"
        if (-not (Test-Path $builder)) { Fail-M20F "native build helper missing: $builder" }
        if ([string]::IsNullOrWhiteSpace($Renderer)) {
            & $builder -IrPath $irPath -RepoRoot $RepoRoot -Run:$Run
        } else {
            & $builder -IrPath $irPath -Renderer $Renderer -RepoRoot $RepoRoot -Run:$Run
        }
    }

    if (-not $Quiet) {
        Write-Host "PASS|m20f_dx12_clear_smoke|ir=$irPath|manifest=$manifest|config=$config"
    }
} finally {
    Pop-Location
}
