param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m21e_dx12_standalone_runtime_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Emit-Check { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

$builderPath = Join-Path $RepoRoot "Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1"
$headerPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.h"
$cppPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp"
$lowererPath = Join-Path $RepoRoot "Tools\lower_m20e1_dx12_clear_from_ir.ps1"
$wrapperPath = Join-Path $RepoRoot "Tools\build_m21d_dx12_triangle_smoke.ps1"
$docsPath = Join-Path $RepoRoot "Docs\M21E_M21F_STANDALONE_FRAME_LOOP.md"
$toolMapPath = Join-Path $RepoRoot "Docs\TOOL_MAP.md"
$capPath = Join-Path $RepoRoot "Backends\WindowsX64PE\Config\capabilities_v0.txt"

$builder = Read-TextSafe $builderPath
$header = Read-TextSafe $headerPath
$cpp = Read-TextSafe $cppPath
$lowerer = Read-TextSafe $lowererPath
$wrapper = Read-TextSafe $wrapperPath
$docs = Read-TextSafe $docsPath
$toolMap = Read-TextSafe $toolMapPath
$cap = Read-TextSafe $capPath

Emit-Check "m21e_builder_exists" ((Test-Path $builderPath) -and $builder.Contains('GetExeDirectory') -and $builder.Contains('ResolveShaderPath')) "native builder generates standalone helpers"
Emit-Check "m21e_shader_copy_fallback" ($builder.Contains('Build\EXE') -and $builder.Contains('Shaders') -and $builder.Contains('Copy-Item') -and $builder.Contains('ARQEN_M21B_VERTEX_SHADER_PATH')) "builder copies shader sources and generated exe can fall back"
Emit-Check "m21e_runtime_diagnostics" ($builder.Contains('arqen_dx12_runtime.log') -and $builder.Contains('MessageBoxA') -and $builder.Contains('AppendResultLog') -and $builder.Contains('WM_ERASEBKGND')) "generated source logs runtime failures and suppresses white erase"
Emit-Check "m21e_bridge_frame_desc_fields" ($header.Contains('uint32_t frameCount') -and $header.Contains('uint32_t targetFps') -and $cpp.Contains('EffectiveFrameCount')) "native desc carries frame loop knobs"
Emit-Check "m21e_lowerer_config_markers" ($lowerer.Contains('ARQEN_M21E_STANDALONE_EXE') -and $lowerer.Contains('ARQEN_M21E_SHADER_FALLBACK_ENABLED') -and $lowerer.Contains('SHADER_FALLBACK|exe_dir_shaders')) "lowerer emits standalone markers"

$wrapperOk = $false
$wrapperNote = "not run"
try {
    & $wrapperPath -RepoRoot $RepoRoot -Quiet *> $null
    $wrapperOk = ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
    $wrapperNote = "exit=$LASTEXITCODE"
} catch {
    $wrapperOk = $false
    $wrapperNote = $_.Exception.Message
}
Emit-Check "m21e_wrapper_still_lowers_triangle_sample" $wrapperOk $wrapperNote

$configPath = Join-Path $RepoRoot "Build\M21D\dx12_clear_config.generated.h"
$manifestPath = Join-Path $RepoRoot "Build\M21D\dx12_clear_manifest.generated.txt"
$config = Read-TextSafe $configPath
$manifest = Read-TextSafe $manifestPath
Emit-Check "m21e_generated_config_markers" ($config.Contains('ARQEN_M21E_STANDALONE_EXE 1') -and $config.Contains('ARQEN_M21E_SHADER_FALLBACK_ENABLED 1')) "config contains standalone markers"
Emit-Check "m21e_generated_manifest_markers" ($manifest.Contains('STANDALONE_EXE|True') -and $manifest.Contains('SHADER_FALLBACK|exe_dir_shaders')) "manifest contains standalone markers"
Emit-Check "m21e_docs_tooling" ($docs.Contains('arqen_dx12_runtime.log') -and $docs.Contains('shader source fallback') -and $toolMap.Contains('validate_m21e_dx12_standalone_runtime.ps1')) "docs/tool map document M21E"
Emit-Check "m21e_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
