param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m21d_dx12_triangle_smoke_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Emit-Check { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

$wrapperPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m21d_dx12_triangle_smoke.ps1"
$lowererPath = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
$builderPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1"
$headerPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.h"
$cppPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp"
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_first_triangle_m21d.arq"
$vsPath = Join-Path $RepoRoot "Samples\DX12\Shaders\triangle_vs.hlsl"
$psPath = Join-Path $RepoRoot "Samples\DX12\Shaders\triangle_ps.hlsl"
$docsPath = Join-Path $RepoRoot "Docs\Milestones\\M21_M25.md"
$toolMapPath = Join-Path $RepoRoot "Docs\Info\TOOLS.md"
$capPath = Join-Path $RepoRoot "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt"

$wrapper = Read-TextSafe $wrapperPath
$lowerer = Read-TextSafe $lowererPath
$builder = Read-TextSafe $builderPath
$header = Read-TextSafe $headerPath
$cpp = Read-TextSafe $cppPath
$sample = Read-TextSafe $samplePath
$vs = Read-TextSafe $vsPath
$ps = Read-TextSafe $psPath
$docs = Read-TextSafe $docsPath
$toolMap = Read-TextSafe $toolMapPath
$cap = Read-TextSafe $capPath

Emit-Check "m21d_sample_exists" ((Test-Path $samplePath) -and $sample.Contains('draw 3 vertices with renderer "MainRenderer"')) "first triangle sample present"
Emit-Check "m21d_shader_files_exist" ((Test-Path $vsPath) -and (Test-Path $psPath) -and $vs.Contains('VSMain') -and $ps.Contains('PSMain')) "HLSL shader files present"
Emit-Check "m21d_wrapper_exists" ((Test-Path $wrapperPath) -and $wrapper.Contains('-RequireTriangle') -and $wrapper.Contains('DX12_DRAW')) "triangle smoke wrapper present"
Emit-Check "m21d_lowerer_consumes_triangle_metadata" ($lowerer.Contains('[switch]$RequireTriangle') -and $lowerer.Contains('DX12_VERTEX_BUFFER') -and $lowerer.Contains('DX12_DRAW') -and $lowerer.Contains('ARQEN_M21C_VERTEX_DATA')) "lowerer consumes vertex/draw metadata"
Emit-Check "m21d_native_builder_triangle_mode" ($builder.Contains('[switch]$RequireTriangle') -and $builder.Contains('ARQEN_M21D_TRIANGLE_ENABLED') -and $builder.Contains('ArqenDx12TriangleWindowOnce') -and $builder.Contains('d3dcompiler.lib')) "native builder can compile triangle smoke"
Emit-Check "m21d_native_bridge_triangle_path" ($header.Contains('ArqenDx12TriangleWindowDesc') -and $cpp.Contains('D3DCompileFromFile') -and $cpp.Contains('CreateGraphicsPipelineState') -and $cpp.Contains('DrawInstanced')) "native bridge has shader/PSO/draw path"

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
Emit-Check "m21d_wrapper_compiles_lowers_triangle_sample" $wrapperOk $wrapperNote

$manifestPath = Join-Path $RepoRoot "Build\M21D\dx12_clear_manifest.generated.txt"
$configPath = Join-Path $RepoRoot "Build\M21D\dx12_clear_config.generated.h"
$manifest = Read-TextSafe $manifestPath
$config = Read-TextSafe $configPath
Emit-Check "m21d_manifest_triangle_markers" ($manifest.Contains('TRIANGLE_MODE|native_triangle_smoke') -and $manifest.Contains('SHADER|TriangleShader') -and $manifest.Contains('VERTEX_BUFFER|TriangleVertices') -and $manifest.Contains('DRAW_VERTICES|3')) "manifest contains triangle markers"
Emit-Check "m21d_config_triangle_markers" ($config.Contains('ARQEN_M21D_TRIANGLE_ENABLED 1') -and $config.Contains('ARQEN_M21C_VERTEX_DATA') -and $config.Contains('ARQEN_M21C_DRAW_VERTEX_COUNT 3')) "config contains triangle macros"
Emit-Check "m21d_docs_present" ($docs -match 'DrawInstanced' -and $docs -match 'optional native') "M21D docs present"
Emit-Check "m21d_tool_map" ($toolMap -match 'build_m21d_dx12_triangle_smoke\.ps1' -and $toolMap -match 'validate_m21d_dx12_triangle_smoke\.ps1') "tool map documents M21D tools"
Emit-Check "m21d_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
