param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m21j_dx12_color_animation_metadata_hardening_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Emit-Check { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

$parserPath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Dx12.cs"
$lowererPath = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
$fixtureDir = Join-Path $RepoRoot "Tests\DX12Lowering\M21J"
$invalidOrphanPath = Join-Path $fixtureDir "invalid_orphan_animation_target.arqir"
$invalidMultiBindPath = Join-Path $fixtureDir "invalid_multi_pipeline_constant_buffer_bind.arqir"
$docsPath = Join-Path $RepoRoot "Docs\Milestones\\M21_M25.md"
$specPath = Join-Path $RepoRoot "Tests\CommandTests\misc\dx12.command.txt"
$toolMapPath = Join-Path $RepoRoot "Docs\Info\TOOLS.md"
$capPath = Join-Path $RepoRoot "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt"

$parser = Read-TextSafe $parserPath
$lowerer = Read-TextSafe $lowererPath
$invalidOrphan = Read-TextSafe $invalidOrphanPath
$invalidMultiBind = Read-TextSafe $invalidMultiBindPath
$docs = Read-TextSafe $docsPath
$spec = Read-TextSafe $specPath
$toolMap = Read-TextSafe $toolMapPath
$cap = Read-TextSafe $capPath

Emit-Check "m21j_parser_binding_guard" ($parser.Contains('boundPipelineCount') -and $parser.Contains('S307') -and $parser.Contains('must be bound to a pipeline before animate color')) "parser source has M21J binding guard"
Emit-Check "m21j_lowerer_selected_tint_guard" ($lowerer.Contains('selected renderer tint constant buffer') -and $lowerer.Contains('bound to exactly one pipeline') -and $lowerer.Contains('M21J_ANIMATION_HARDENING')) "lowerer rejects ambiguous/non-selected animation targets"
Emit-Check "m21j_lowering_fixtures_present" ((Test-Path $invalidOrphanPath) -and (Test-Path $invalidMultiBindPath) -and $invalidOrphan.Contains('DX12_ANIMATE_COLOR|target=GhostParams.tint') -and $invalidMultiBind.Contains('DX12_CONSTANT_BUFFER_BIND|buffer=TriangleParams|pipeline=OtherPipeline')) "M21J invalid lowering fixtures present"

$orphanOk = $false
$orphanNote = "not run"
try {
    & $lowererPath -IrPath $invalidOrphanPath -OutDir (Join-Path $RepoRoot "Build\M21J\InvalidOrphan") -RequireFrame -RequireTriangle -Quiet *> $null
    $orphanOk = $false
    $orphanNote = "unexpected success"
} catch {
    $orphanNote = $_.Exception.Message
    $orphanOk = ($orphanNote -match 'selected renderer tint constant buffer')
}
Emit-Check "m21j_rejects_orphan_animation_target" $orphanOk $orphanNote

$multiBindOk = $false
$multiBindNote = "not run"
try {
    & $lowererPath -IrPath $invalidMultiBindPath -OutDir (Join-Path $RepoRoot "Build\M21J\InvalidMultiBind") -RequireFrame -RequireTriangle -Quiet *> $null
    $multiBindOk = $false
    $multiBindNote = "unexpected success"
} catch {
    $multiBindNote = $_.Exception.Message
    $multiBindOk = ($multiBindNote -match 'bound to exactly one pipeline')
}
Emit-Check "m21j_rejects_multi_pipeline_constant_buffer" $multiBindOk $multiBindNote
Emit-Check "m21j_docs_spec" ($docs -match 'M21J' -and $docs -match 'metadata hardening' -and $spec -match 'M21J_HARDENING' -and $toolMap -match 'validate_m21j_dx12_color_animation_metadata_hardening\.ps1') "docs/spec/tool map document M21J"
Emit-Check "m21j_config_manifest_markers" ($lowerer.Contains('M21J_ANIMATION_HARDENING|selected_tint_only|single_pipeline_binding') -and $lowerer.Contains('ARQEN_M21J_ANIMATION_HARDENING')) "generated outputs expose hardening marker"
Emit-Check "m21j_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
