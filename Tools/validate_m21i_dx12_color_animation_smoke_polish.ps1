param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m21i_dx12_color_animation_smoke_polish_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Emit-Check { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

$wrapperPath = Join-Path $RepoRoot "Tools\build_m21i_dx12_color_animation_smoke_polish.ps1"
$m21hWrapperPath = Join-Path $RepoRoot "Tools\build_m21h_dx12_animated_triangle_smoke.ps1"
$lowererPath = Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1"
$docsPath = Join-Path $RepoRoot "Docs\M21G_M21H_CONSTANT_COLOR_ANIMATION.md"
$toolMapPath = Join-Path $RepoRoot "Docs\TOOL_MAP.md"
$capPath = Join-Path $RepoRoot "Backends\WindowsX64PE\Config\capabilities_v0.txt"

$wrapper = Read-TextSafe $wrapperPath
$m21hWrapper = Read-TextSafe $m21hWrapperPath
$lowerer = Read-TextSafe $lowererPath
$docs = Read-TextSafe $docsPath
$toolMap = Read-TextSafe $toolMapPath
$cap = Read-TextSafe $capPath

Emit-Check "m21i_wrapper_exists" ((Test-Path $wrapperPath) -and $wrapper.Contains('Build\M21I') -and $wrapper.Contains('build_m21h_dx12_animated_triangle_smoke.ps1')) "M21I wrapper delegates to M21H path"
Emit-Check "m21i_wrapper_runtime_knobs" ($wrapper.Contains('Alias("Frames")') -and $wrapper.Contains('Alias("Fps")') -and $wrapper.Contains('Alias("RunNative")') -and $wrapper.Contains('$OutDir')) "wrapper exposes friendly runtime knobs"
Emit-Check "m21i_m21h_outdir_reusable" ($m21hWrapper.Contains('[string]$OutDir') -and $m21hWrapper.Contains('Build\M21H')) "M21H wrapper remains defaulted but reusable"
Emit-Check "m21i_lowerer_manifest_markers" ($lowerer.Contains('M21I_SMOKE_POLISH|True') -and $lowerer.Contains('M21I_RUNTIME_KNOBS|frames=') -and $lowerer.Contains('M21I_COLOR_TICK|every_frames=')) "lowerer emits M21I manifest markers"
Emit-Check "m21i_lowerer_config_markers" ($lowerer.Contains('ARQEN_M21I_SMOKE_POLISH') -and $lowerer.Contains('ARQEN_M21I_RUNTIME_KNOBS_ENABLED') -and $lowerer.Contains('ARQEN_M21I_FRAME_COUNT')) "lowerer emits M21I config macros"

$wrapperOk = $false
$wrapperNote = "not run"
try {
    & $wrapperPath -RepoRoot $RepoRoot -FrameCount 36 -TargetFps 24 -HoldMilliseconds 1500 -Quiet *> $null
    $wrapperOk = ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
    $wrapperNote = "exit=$LASTEXITCODE"
} catch {
    $wrapperOk = $false
    $wrapperNote = $_.Exception.Message
}
Emit-Check "m21i_wrapper_compiles_lowers_polished_sample" $wrapperOk $wrapperNote

$configPath = Join-Path $RepoRoot "Build\M21I\dx12_clear_config.generated.h"
$manifestPath = Join-Path $RepoRoot "Build\M21I\dx12_clear_manifest.generated.txt"
$config = Read-TextSafe $configPath
$manifest = Read-TextSafe $manifestPath
Emit-Check "m21i_manifest_runtime_knobs" ($manifest.Contains('M21I_SMOKE_POLISH|True') -and $manifest.Contains('M21I_RUNTIME_KNOBS|frames=36|fps=24|hold_ms=1500') -and $manifest.Contains('M21I_COLOR_TICK|every_frames=12|keys=4')) "manifest contains runtime knob markers"
Emit-Check "m21i_config_runtime_knobs" ($config.Contains('ARQEN_M21I_SMOKE_POLISH 1') -and $config.Contains('ARQEN_M21I_FRAME_COUNT 36') -and $config.Contains('ARQEN_M21I_TARGET_FPS 24') -and $config.Contains('ARQEN_M21I_COLOR_KEY_COUNT 4')) "config contains runtime knob macros"
Emit-Check "m21i_docs_tooling" ($docs -match 'M21I' -and $docs -match 'smoke polish' -and $toolMap -match 'build_m21i_dx12_color_animation_smoke_polish\.ps1' -and $toolMap -match 'validate_m21i_dx12_color_animation_smoke_polish\.ps1') "docs/tool map document M21I"
Emit-Check "m21i_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
