param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m21h_dx12_color_animation_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Emit-Check { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

$wrapperPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m21h_dx12_animated_triangle_smoke.ps1"
$lowererPath = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
$builderPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1"
$cppPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp"
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_animated_triangle_m21h.arq"
$psPath = Join-Path $RepoRoot "Samples\DX12\Shaders\triangle_tint_ps.hlsl"
$docsPath = Join-Path $RepoRoot "Docs\Milestones\\M21_M25.md"
$toolMapPath = Join-Path $RepoRoot "Docs\Info\TOOLS.md"
$capPath = Join-Path $RepoRoot "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt"

$wrapper = Read-TextSafe $wrapperPath
$lowerer = Read-TextSafe $lowererPath
$builder = Read-TextSafe $builderPath
$cpp = Read-TextSafe $cppPath
$sample = Read-TextSafe $samplePath
$ps = Read-TextSafe $psPath
$docs = Read-TextSafe $docsPath
$toolMap = Read-TextSafe $toolMapPath
$cap = Read-TextSafe $capPath

Emit-Check "m21h_sample_exists" ((Test-Path $samplePath) -and $sample.Contains('animate color "TriangleParams.tint"')) "animated triangle sample present"
Emit-Check "m21h_tint_shader_exists" ((Test-Path $psPath) -and $ps.Contains('cbuffer TriangleParams') -and $ps.Contains('Tint')) "tint pixel shader present"
Emit-Check "m21h_parser_ir_markers" ($lowerer.Contains('DX12_COLOR_SEQUENCE') -and $lowerer.Contains('DX12_ANIMATE_COLOR') -and $lowerer.Contains('ARQEN_M21H_COLOR_DATA')) "lowerer consumes animation metadata"
Emit-Check "m21h_native_animation_path" ($cpp.Contains('animationColors_') -and $cpp.Contains('(frameNumber / every) % animationColorCount_') -and $cpp.Contains('UpdateTintBuffer(frameNumber)')) "native bridge updates tint by frame"
Emit-Check "m21h_wrapper_exists" ((Test-Path $wrapperPath) -and $wrapper.Contains('Build\M21H') -and $wrapper.Contains('dx12_animated_triangle_m21h.arq')) "M21H wrapper present"
Emit-Check "m21h_builder_passes_generated_animation_arrays" ($builder.Contains('ARQEN_M21H_COLOR_DATA') -and $builder.Contains('animationColorCount') -and $builder.Contains('animationEveryFrames')) "native builder passes animation arrays"

$wrapperOk = $false
$wrapperNote = "not run"
try {
    & $wrapperPath -RepoRoot $RepoRoot -FrameCount 24 -TargetFps 30 -Quiet *> $null
    $wrapperOk = ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
    $wrapperNote = "exit=$LASTEXITCODE"
} catch {
    $wrapperOk = $false
    $wrapperNote = $_.Exception.Message
}
Emit-Check "m21h_wrapper_compiles_lowers_animated_sample" $wrapperOk $wrapperNote

$configPath = Join-Path $RepoRoot "Build\M21H\dx12_clear_config.generated.h"
$manifestPath = Join-Path $RepoRoot "Build\M21H\dx12_clear_manifest.generated.txt"
$config = Read-TextSafe $configPath
$manifest = Read-TextSafe $manifestPath
Emit-Check "m21h_manifest_animation_markers" ($manifest.Contains('COLOR_ANIMATION|True') -and $manifest.Contains('COLOR_SEQUENCE|TriangleColors') -and $manifest.Contains('COLOR_EVERY_FRAMES|12') -and $manifest.Contains('COLOR_KEY_COUNT|4')) "manifest contains animation markers"
Emit-Check "m21h_config_animation_markers" ($config.Contains('ARQEN_M21G_TINT_ENABLED 1') -and $config.Contains('ARQEN_M21H_COLOR_ANIMATION_ENABLED 1') -and $config.Contains('ARQEN_M21H_COLOR_EVERY_FRAMES 12') -and $config.Contains('ARQEN_M21H_COLOR_COUNT 4')) "config contains animation macros"
Emit-Check "m21h_docs_tooling" ($docs -match 'color sequence' -and $docs -match 'animated triangle' -and $toolMap -match 'validate_m21h_dx12_color_animation\.ps1') "docs/tool map document M21H"
Emit-Check "m21h_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
