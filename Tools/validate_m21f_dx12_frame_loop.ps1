param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m21f_dx12_frame_loop_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Emit-Check { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

$lowererPath = Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1"
$m21dWrapperPath = Join-Path $RepoRoot "Tools\build_m21d_dx12_triangle_smoke.ps1"
$m21fWrapperPath = Join-Path $RepoRoot "Tools\build_m21f_dx12_triangle_loop_smoke.ps1"
$builderPath = Join-Path $RepoRoot "Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1"
$headerPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.h"
$cppPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp"
$docsPath = Join-Path $RepoRoot "Docs\M21E_M21F_STANDALONE_FRAME_LOOP.md"
$toolMapPath = Join-Path $RepoRoot "Docs\TOOL_MAP.md"
$capPath = Join-Path $RepoRoot "Backends\WindowsX64PE\Config\capabilities_v0.txt"

$lowerer = Read-TextSafe $lowererPath
$m21dWrapper = Read-TextSafe $m21dWrapperPath
$m21fWrapper = Read-TextSafe $m21fWrapperPath
$builder = Read-TextSafe $builderPath
$header = Read-TextSafe $headerPath
$cpp = Read-TextSafe $cppPath
$docs = Read-TextSafe $docsPath
$toolMap = Read-TextSafe $toolMapPath
$cap = Read-TextSafe $capPath

$lowererHasFrameLoopMode = (
    $lowerer.Contains('FRAME_LOOP_MODE|fixed_frame_count') -or
    $lowerer.Contains('FRAME_LOOP_MODE|$m22FrameMode') -or
    $lowerer.Contains('FRAME_LOOP_MODE|{0}')
)
Emit-Check "m21f_lowerer_accepts_frame_loop_knobs" ($lowerer.Contains('[int]$FrameCount') -and $lowerer.Contains('[int]$TargetFps') -and $lowerer.Contains('ARQEN_M21F_FRAME_COUNT') -and $lowererHasFrameLoopMode) "lowerer emits frame loop config"
Emit-Check "m21f_builder_passes_frame_loop_knobs" ($builder.Contains('[int]$FrameCount') -and $builder.Contains('[int]$TargetFps') -and $builder.Contains('ArqenDx12TriangleWindowRunFrames') -and $builder.Contains('ARQEN_M21F_FRAME_LOOP_ENABLED')) "native builder uses frame loop export"
Emit-Check "m21f_native_exports_frame_loop" ($header.Contains('ArqenDx12TriangleWindowRunFrames') -and $header.Contains('ArqenDx12ClearWindowRunFrames') -and ($cpp.Contains('for (UINT frame = 0; frame < frameCount; ++frame)') -or $cpp.Contains('for (UINT frame = 0; infinite || frame < frameCount; ++frame)')) -and $cpp.Contains('SleepToTargetFrame')) "native bridge has persistent loop exports"
Emit-Check "m21f_wrapper_exists" ((Test-Path $m21fWrapperPath) -and $m21fWrapper.Contains('-FrameCount') -and $m21fWrapper.Contains('-TargetFps') -and $m21fWrapper.Contains('Build\M21F')) "M21F wrapper present"
Emit-Check "m21d_wrapper_extended" ($m21dWrapper.Contains('[int]$FrameCount') -and $m21dWrapper.Contains('[int]$TargetFps') -and $m21dWrapper.Contains('-OutDir')) "M21D wrapper supports loop knobs"

$wrapperOk = $false
$wrapperNote = "not run"
try {
    & $m21fWrapperPath -RepoRoot $RepoRoot -FrameCount 12 -TargetFps 30 -Quiet *> $null
    $wrapperOk = ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
    $wrapperNote = "exit=$LASTEXITCODE"
} catch {
    $wrapperOk = $false
    $wrapperNote = $_.Exception.Message
}
Emit-Check "m21f_wrapper_compiles_lowers_loop_sample" $wrapperOk $wrapperNote

$configPath = Join-Path $RepoRoot "Build\M21F\dx12_clear_config.generated.h"
$manifestPath = Join-Path $RepoRoot "Build\M21F\dx12_clear_manifest.generated.txt"
$config = Read-TextSafe $configPath
$manifest = Read-TextSafe $manifestPath
Emit-Check "m21f_manifest_frame_loop_markers" ($manifest.Contains('FRAME_LOOP_MODE|fixed_frame_count') -and $manifest.Contains('FRAME_COUNT|12') -and $manifest.Contains('TARGET_FPS|30')) "manifest contains requested frame loop markers"
Emit-Check "m21f_config_frame_loop_markers" ($config.Contains('ARQEN_M21F_FRAME_LOOP_ENABLED 1') -and $config.Contains('ARQEN_M21F_FRAME_COUNT 12') -and $config.Contains('ARQEN_M21F_TARGET_FPS 30')) "config contains requested frame loop macros"
Emit-Check "m21f_docs_tooling" (($docs -match '(?i)fixed-frame.*loop') -and ($docs -match 'build_m21f_dx12_triangle_loop_smoke\.ps1') -and ($toolMap -match 'validate_m21f_dx12_frame_loop\.ps1')) "docs/tool map document M21F"
Emit-Check "m21f_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
