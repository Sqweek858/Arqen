param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m22_dx12_mini_scene_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Emit-Check { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

$docsPath = Join-Path $RepoRoot "Docs\Milestones\\M21_M25.md"
$handoffPath = Join-Path $RepoRoot "Docs\Milestones\\M21_M25.md"
$toolMapPath = Join-Path $RepoRoot "Docs\Info\TOOLS.md"
$specPath = Join-Path $RepoRoot "Tests\CommandTests\misc\dx12.command.txt"
$sampleAPath = Join-Path $RepoRoot "Samples\DX12\dx12_crystal_cluster_m22a.arq"
$sampleIPath = Join-Path $RepoRoot "Samples\DX12\dx12_crystal_scene_m22i.arq"
$generatorPath = Join-Path $RepoRoot "Tools\Scaffold\new_m22b_dx12_crystal_cluster_sample.ps1"
$wrapperPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m22i_dx12_crystal_scene.ps1"
$lowererPath = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
$nativeHelperPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1"
$runtimeCppPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp"
$capPath = Join-Path $RepoRoot "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt"

$docs = Read-TextSafe $docsPath
$handoff = Read-TextSafe $handoffPath
$toolMap = Read-TextSafe $toolMapPath
$spec = Read-TextSafe $specPath
$sampleA = Read-TextSafe $sampleAPath
$sampleI = Read-TextSafe $sampleIPath
$generator = Read-TextSafe $generatorPath
$wrapper = Read-TextSafe $wrapperPath
$lowerer = Read-TextSafe $lowererPath
$nativeHelper = Read-TextSafe $nativeHelperPath
$runtimeCpp = Read-TextSafe $runtimeCppPath
$cap = Read-TextSafe $capPath

Emit-Check "m22a_bible_docs" ((Test-Path $docsPath) -and $docs.Contains("M22A") -and $docs.Contains("M22I") -and $docs.Contains("mini scene")) "M22 A-I bible present"
Emit-Check "m22b_generator_tool" ((Test-Path $generatorPath) -and $generator.Contains("ShardCount") -and $generator.Contains("M22B generated crystal cluster") -and $generator.Contains('draw $($vertices.Count) vertices')) "generator creates existing DX12-syntax crystal samples"
Emit-Check "m22c_samples_present" ((Test-Path $sampleAPath) -and (Test-Path $sampleIPath) -and $sampleA.Contains("draw 60 vertices") -and $sampleI.Contains("draw 108 vertices")) "M22A/M22I samples present with larger vertex buffers"
Emit-Check "m22d_wrapper_present" ((Test-Path $wrapperPath) -and $wrapper.Contains('M22I DX12 crystal scene failed') -and $wrapper.Contains("M22 crystal scene expects at least 60") -and $wrapper.Contains("m22i_dx12_crystal_scene.exe")) "M22I wrapper compiles, lowers, optionally builds/runs native"
Emit-Check "m22e_keep_open_lowerer" ($lowerer.Contains('[switch]$KeepOpen') -and $lowerer.Contains('keep_open_until_close') -and $lowerer.Contains('M22_KEEP_OPEN|') -and $lowerer.Contains('ARQEN_M22_KEEP_OPEN')) "lowerer emits keep-open markers and frameCount=0/infinite config"
Emit-Check "m22f_keep_open_runtime" ($runtimeCpp.Contains('IsInfiniteFrameCount') -and $runtimeCpp.Contains('infinite || frame < frameCount') -and $nativeHelper.Contains('WM_KEYDOWN') -and $nativeHelper.Contains('VK_ESCAPE') -and $nativeHelper.Contains("wparam == 'Q'")) "native runtime can keep window open until close, Escape, or Q"
Emit-Check "m22g_manifest_config_markers" ($lowerer.Contains('M22_MINI_SCENE|True') -and $lowerer.Contains('M22_VERTEX_CLUSTER|vertices=') -and $lowerer.Contains('ARQEN_M22_VERTEX_CLUSTER_COUNT')) "generated manifest/config expose M22 scene markers"
Emit-Check "m22h_docs_tool_map_spec" ($handoff.Contains("M22I") -and $toolMap.Contains('build_m22i_dx12_crystal_scene.ps1') -and $toolMap.Contains('validate_m22_dx12_mini_scene_contract.ps1') -and $spec.Contains('M22_MINI_SCENE')) "handoff/tool map/spec document M22"

$buildOk = $false
$buildNote = "not run"
try {
    & $wrapperPath -RepoRoot $RepoRoot -SourcePath $sampleIPath -OutDir (Join-Path $RepoRoot "Build\M22I") -FrameCount 48 -TargetFps 24 -HoldMilliseconds 2000 -Quiet
    $manifestPath = Join-Path $RepoRoot "Build\M22I\dx12_clear_manifest.generated.txt"
    $configPath = Join-Path $RepoRoot "Build\M22I\dx12_clear_config.generated.h"
    $manifest = Read-TextSafe $manifestPath
    $config = Read-TextSafe $configPath
    $buildOk = ($manifest.Contains('M22_MINI_SCENE|True') -and $manifest.Contains('VERTEX_COUNT|108') -and $manifest.Contains('DRAW_VERTICES|108') -and $manifest.Contains('M22_KEEP_OPEN|False') -and $config.Contains('ARQEN_M22_VERTEX_CLUSTER_COUNT 108') -and $config.Contains('ARQEN_M21F_FRAME_COUNT 48'))
    $buildNote = "manifest/config checked"
} catch {
    $buildOk = $false
    $buildNote = $_.Exception.Message
}
Emit-Check "m22i_wrapper_compiles_lowers_scene" $buildOk $buildNote

$keepOpenOk = $false
$keepOpenNote = "not run"
try {
    & $wrapperPath -RepoRoot $RepoRoot -SourcePath $sampleIPath -OutDir (Join-Path $RepoRoot "Build\M22I_KeepOpen") -FrameCount 48 -TargetFps 24 -HoldMilliseconds 2000 -KeepOpen -Quiet
    $manifestPath = Join-Path $RepoRoot "Build\M22I_KeepOpen\dx12_clear_manifest.generated.txt"
    $configPath = Join-Path $RepoRoot "Build\M22I_KeepOpen\dx12_clear_config.generated.h"
    $manifest = Read-TextSafe $manifestPath
    $config = Read-TextSafe $configPath
    $keepOpenOk = ($manifest.Contains('M22_KEEP_OPEN|True') -and $manifest.Contains('FRAME_LOOP_MODE|keep_open_until_close') -and $config.Contains('ARQEN_M22_KEEP_OPEN 1') -and $config.Contains('ARQEN_M21F_FRAME_COUNT 0'))
    $keepOpenNote = "keep-open manifest/config checked"
} catch {
    $keepOpenOk = $false
    $keepOpenNote = $_.Exception.Message
}
Emit-Check "m22i_keep_open_lowering" $keepOpenOk $keepOpenNote

Emit-Check "m22_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported in main backend"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
