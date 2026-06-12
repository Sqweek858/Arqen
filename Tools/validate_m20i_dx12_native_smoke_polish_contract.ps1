param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m20i_dx12_native_smoke_polish_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Emit-Check { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_frame_clear_smoke_m20h.arq"
$toolPath = Join-Path $RepoRoot "Tools\build_m20i_dx12_frame_clear_smoke.ps1"
$builderPath = Join-Path $RepoRoot "Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1"
$lowererPath = Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1"
$docPath = Join-Path $RepoRoot "Docs\M20I_DX12_NATIVE_SMOKE_POLISH.md"
$runtimeReadmePath = Join-Path $RepoRoot "Backends\DX12\Runtime\README.md"
$toolMapPath = Join-Path $RepoRoot "Docs\TOOL_MAP.md"
$capPath = Join-Path $RepoRoot "Backends\WindowsX64PE\Config\capabilities_v0.txt"

$sample = Read-TextSafe $samplePath
$tool = Read-TextSafe $toolPath
$builder = Read-TextSafe $builderPath
$lowerer = Read-TextSafe $lowererPath
$doc = Read-TextSafe $docPath
$runtimeReadme = Read-TextSafe $runtimeReadmePath
$toolMap = Read-TextSafe $toolMapPath
$cap = Read-TextSafe $capPath

Emit-Check "m20i_sample_exists" ((Test-Path $samplePath) -and $sample.Contains('begin frame of "MainRenderer"') -and $sample.Contains('present frame of "MainRenderer"')) "frame clear smoke sample present"
Emit-Check "m20i_tool_exists" (Test-Path $toolPath) "build_m20i_dx12_frame_clear_smoke.ps1 present"
Emit-Check "m20i_tool_uses_compiler_lowerer_requireframe" ($tool -match 'arqc_m10g\.exe' -and $tool -match 'lower_m20e1_dx12_clear_from_ir\.ps1' -and $tool -match '-RequireFrame' -and $tool -match '\[int\]\$HoldMilliseconds') "tool compiles then lowers with frame requirement"
Emit-Check "m20i_native_builder_polished" ($builder -match '\[switch\]\$RequireFrame' -and $builder -match '\[int\]\$HoldMilliseconds' -and $builder -match '-HoldMilliseconds\s+\$HoldMilliseconds' -and $builder -match '\$ExeName') "native builder accepts frame/hold/exe options"
Emit-Check "m20i_lowerer_generates_runtime_knobs" ($lowerer -match 'ARQEN_M20I_HOLD_MS' -and $lowerer -match 'ARQEN_M20I_ENABLE_DIAGNOSTICS' -and $lowerer -match 'FRAME_MODE') "lowerer emits frame/smoke config knobs"

$wrapperOk = $false
$wrapperNote = "not run"
try {
    & $toolPath -RepoRoot $RepoRoot -Quiet
    $wrapperOk = ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
    $wrapperNote = "wrapper produced Build\\M20I manifest/config"
} catch {
    $wrapperOk = $false
    $wrapperNote = $_.Exception.Message
}
Emit-Check "m20i_wrapper_compiles_lowers_frame_sample" $wrapperOk $wrapperNote

$manifest = Join-Path $RepoRoot "Build\M20I\dx12_clear_manifest.generated.txt"
$config = Join-Path $RepoRoot "Build\M20I\dx12_clear_config.generated.h"
$manifestText = Read-TextSafe $manifest
$configText = Read-TextSafe $config
Emit-Check "m20i_manifest_frame_markers" ($manifestText -match 'FRAME_MODE\|oneshot_clear_frame' -and $manifestText -match 'FRAME_SEQUENCE\|begin,clear,end,present' -and $manifestText -match 'HOLD_MS\|1600') "manifest frame/smoke markers present"
Emit-Check "m20i_config_frame_markers" ($configText -match 'ARQEN_M20H_FRAME_SEQUENCE "begin,clear,end,present"' -and $configText -match 'ARQEN_M20I_HOLD_MS 1600') "config frame/smoke markers present"
$m20iDocOk = (Test-Path $docPath) -and ($doc -match '(?i)M20I') -and ($doc -match '(?i)optional\s+native') -and ($runtimeReadme -match '(?i)M20I')
Emit-Check "m20i_docs_present" $m20iDocOk "M20I docs present"
Emit-Check "m20i_tool_map" ($toolMap -match 'build_m20i_dx12_frame_clear_smoke\.ps1' -and $toolMap -match 'validate_m20i_dx12_native_smoke_polish_contract\.ps1') "tool map documents M20I tools"
Emit-Check "m20i_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
