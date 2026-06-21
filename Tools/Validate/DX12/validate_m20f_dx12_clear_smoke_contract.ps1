param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m20f_dx12_clear_smoke_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Emit-Check { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_clear_smoke_m20f.arq"
$toolPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m20f_dx12_clear_smoke.ps1"
$lowererPath = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
$nativeBuilderPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1"
$m20Path = Join-Path $RepoRoot "Docs\Milestones\\M16_M20.md"
$miniBiblePath = Join-Path $RepoRoot "Docs\Milestones\\M16_M20.md"
$smokeDocPath = Join-Path $RepoRoot "Docs\Milestones\\M16_M20.md"
$toolMapPath = Join-Path $RepoRoot "Docs\Info\TOOLS.md"
$capPath = Join-Path $RepoRoot "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt"

$sample = Read-TextSafe $samplePath
$tool = Read-TextSafe $toolPath
$nativeBuilder = Read-TextSafe $nativeBuilderPath
$m20 = Read-TextSafe $m20Path
$miniBible = Read-TextSafe $miniBiblePath
$smokeDoc = Read-TextSafe $smokeDocPath
$toolMap = Read-TextSafe $toolMapPath
$cap = Read-TextSafe $capPath

Emit-Check "m20f_sample_exists" (Test-Path $samplePath) "dx12_clear_smoke_m20f.arq present"
Emit-Check "m20f_sample_uses_public_syntax" ($sample -match 'define dx12 renderer called "MainRenderer"' -and $sample -match 'parent renderer "MainRenderer" to window "MainWindow"' -and $sample -match 'background color: color "#101820"') "sample uses renderer/parent/style"
Emit-Check "m20f_tool_exists" (Test-Path $toolPath) "build_m20f_dx12_clear_smoke.ps1 present"
Emit-Check "m20f_tool_uses_compiler_and_lowerer" ($tool -match 'arqc_m10g\.exe' -and $tool -match 'lower_m20e1_dx12_clear_from_ir\.ps1' -and $tool -match 'DX12_CLEAR_READY') "tool compiles then lowers"
Emit-Check "m20f_tool_native_optional" ($tool -match '\[switch\]\$BuildNative' -and $tool -match '\[switch\]\$Run' -and $tool -match 'if \(\$BuildNative -or \$Run\)') "native build/run gated behind switches"
Emit-Check "m20f_native_builder_invokes_lowerer_explicitly" ($nativeBuilder -match '-IrPath \$IrPath -OutDir \$outDir' -and $nativeBuilder -notmatch '\@args') "native builder avoids PowerShell automatic args trap"
Emit-Check "m20f_docs_present" ((Test-Path $smokeDocPath) -and $m20 -match 'M20F DX12 clear smoke path' -and $miniBible -match 'M20F clear smoke path') "M20F docs present"
Emit-Check "m20f_tool_map" ($toolMap -match 'build_m20f_dx12_clear_smoke\.ps1' -and $toolMap -match 'validate_m20f_dx12_clear_smoke_contract\.ps1') "tool map documents M20F tools"

$wrapperOk = $false
$wrapperNote = "not run"
try {
    & $toolPath -RepoRoot $RepoRoot -Quiet
    $wrapperOk = ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
    $wrapperNote = "wrapper produced Build\\M20F manifest/config"
} catch {
    $wrapperOk = $false
    $wrapperNote = $_.Exception.Message
}
Emit-Check "m20f_wrapper_compiles_and_lowers_sample" $wrapperOk $wrapperNote

$manifest = Join-Path $RepoRoot "Build\M20F\dx12_clear_manifest.generated.txt"
$config = Join-Path $RepoRoot "Build\M20F\dx12_clear_config.generated.h"
$manifestText = Read-TextSafe $manifest
$configText = Read-TextSafe $config
Emit-Check "m20f_manifest_markers" ($manifestText -match 'RENDERER\|MainRenderer' -and $manifestText -match 'WINDOW\|MainWindow' -and $manifestText -match 'COLOR_HEX\|#101820') "manifest markers present"
Emit-Check "m20f_config_markers" ($configText -match 'ARQEN_M20E1_WINDOW_WIDTH 1280' -and $configText -match 'ARQEN_M20E1_CLEAR_HEX "#101820"') "config markers present"
Emit-Check "m20f_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
