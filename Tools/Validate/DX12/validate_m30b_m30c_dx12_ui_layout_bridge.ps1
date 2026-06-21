param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (git rev-parse --show-toplevel).Trim() }
$outPath = Join-Path $RepoRoot "Build\Generated\m30b_m30c_dx12_ui_layout_bridge_validation.txt"
New-Item -ItemType Directory -Force -Path (Split-Path $outPath -Parent) | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false
function Read-All([string]$Path) { if (-not (Test-Path $Path)) { return "" }; return Get-Content $Path -Raw }
function Emit-Check([string]$Name, [bool]$Ok, [string]$Message) {
    $status = if ($Ok) { "PASS" } else { "FAIL" }
    $script:lines.Add("$status|$Name|$Message") | Out-Null
    Write-Host "$status|$Name|$Message"
    if (-not $Ok) { $script:failed = $true }
}

$lowerer = Read-All (Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1")
$wrapper = Read-All (Join-Path $RepoRoot "Tools\Build\DX12\build_m30b_dx12_ui_layout_bridge_scene.ps1")
$toolMap = Read-All (Join-Path $RepoRoot "Docs\Info\TOOLS.md")
$milestones = Read-All (Join-Path $RepoRoot "Docs\MILESTONES.md")
$docs = Read-All (Join-Path $RepoRoot "Docs\Milestones\\M26_M30.md")
$handoff = Read-All (Join-Path $RepoRoot "Docs\Milestones\\M26_M30.md")
$sampleReadme = Read-All (Join-Path $RepoRoot "Samples\README.md")
$spec = Read-All (Join-Path $RepoRoot "Tests\CommandTests\misc\dx12.command.txt")
$irContract = Read-All (Join-Path $RepoRoot "Docs\Reference\IR\ARQIR_V0_CONTRACT.md")
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_ui_layout_bridge_scene_m30b.arq"
$sample = Read-All $samplePath

Emit-Check "m30b_text_layout_hygiene" ($lowerer.Contains('New-UiTextVertices') -and $lowerer.Contains('New-UiRectVerticesClipped') -and $lowerer.Contains('Get-UiTextScale') -and $lowerer.Contains('Get-UiTextAdvance') -and $lowerer.Contains('M30B_TEXT_CLIPPING') -and $lowerer.Contains('M30B_BUTTON_TEXT_CENTERING')) "lowerer clips text/control geometry, respects style size, and centers button text"
Emit-Check "m30b_z_index_draw_order" ($lowerer.Contains('Sort-Object ZIndex, Index') -and $lowerer.Contains("'z index'")) "lowerer uses z index metadata for stable UI draw order"
Emit-Check "m30c_parent_clip_bridge" ($lowerer.Contains('UI_PARENT') -and $lowerer.Contains('UI_DOCK') -and $lowerer.Contains('Get-ResolvedUiRect') -and $lowerer.Contains('Get-ResolvedUiClip') -and $lowerer.Contains("'clip children'") -and $lowerer.Contains("'overflow'")) "lowerer resolves parent-relative/docked UI rects and clips children through panel clip metadata"
Emit-Check "m30d_click_event_bridge_partial" ($lowerer.Contains('$clickedTargets') -and $lowerer.Contains('UI_EVENT') -and $lowerer.Contains('Resolve-UiAction') -and $lowerer.Contains('M30D_UI_CLICK_EVENT_BRIDGE')) "lowerer routes clickable controls from existing UI_EVENT metadata; generic event-body execution remains future scope"
Emit-Check "m30b_sample_uses_existing_contracts" ($sample.Contains('parent "PanelTitle" to "InspectorPanel"') -and $sample.Contains('clip children: true') -and $sample.Contains('overflow: hidden') -and $sample.Contains('z index: 10') -and $sample.Contains('size: 20 px') -and $sample.Contains('TOGGLE ANIM')) "official M30B/M30C sample uses existing parent/style/layout contracts without new syntax"
Emit-Check "m30b_wrapper" ($wrapper.Contains('dx12_ui_layout_bridge_scene_m30b.arq') -and $wrapper.Contains('M30B_UI_LAYOUT_HYGIENE|True') -and $wrapper.Contains('M30C_PARENT_RELATIVE_LAYOUT|True')) "M30B wrapper validates compile/lower markers for layout bridge sample"
Emit-Check "m30b_docs_spec_toolmap" ($docs.Contains('M30B') -and $docs.Contains('text clipping') -and $docs.Contains('parent-relative') -and $docs.Contains('M30D') -and $handoff.Contains('build_m30b_dx12_ui_layout_bridge_scene.ps1') -and $toolMap.Contains('validate_m30b_m30c_dx12_ui_layout_bridge.ps1') -and $milestones.Contains('M30B') -and $sampleReadme.Contains('dx12_ui_layout_bridge_scene_m30b.arq') -and $spec.Contains('M30B_UI_LAYOUT_HYGIENE') -and $irContract.Contains('M30C_UI_PARENT_CLIP_BRIDGE')) "docs/spec/tool map/sample README/IR contract document M30B/M30C bridge and partial M30D boundary"
Emit-Check "m30b_future_scope_blocked" ($docs.Contains('No docking editor') -and $docs.Contains('No generic event body execution') -and $docs.Contains('No flex/grid solver') -and $docs.Contains('No font loading')) "M30B/M30C explicitly avoids larger UI/editor families"

$wrapperPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m30b_dx12_ui_layout_bridge_scene.ps1"
if (Test-Path $wrapperPath) {
    try {
        & $wrapperPath -RepoRoot $RepoRoot -SourcePath $samplePath -OutDir (Join-Path $RepoRoot "Build\M30B") -FrameCount 90 -TargetFps 30 -HoldMilliseconds 3000 -Quiet
        $manifestPath = Join-Path $RepoRoot "Build\M30B\dx12_clear_manifest.generated.txt"
        $configPath = Join-Path $RepoRoot "Build\M30B\dx12_clear_config.generated.h"
        $manifest = Read-All $manifestPath
        $config = Read-All $configPath
        Emit-Check "m30b_wrapper_compiles_lowers_scene" ($manifest.Contains('M30B_UI_LAYOUT_HYGIENE|True') -and $manifest.Contains('M30B_TEXT_CLIPPING|True') -and $manifest.Contains('M30C_UI_PARENT_CLIP_BRIDGE|True') -and $manifest.Contains('M30C_PARENT_RELATIVE_LAYOUT|True') -and $config.Contains('ARQEN_M30B_TEXT_CLIPPING 1') -and $config.Contains('ARQEN_M30C_UI_PARENT_CLIP_BRIDGE 1')) "M30B wrapper compiles/lowers official sample with UI layout/clip markers"
    } catch {
        Emit-Check "m30b_wrapper_compiles_lowers_scene" $false $_.Exception.Message
    }
} else { Emit-Check "m30b_wrapper_compiles_lowers_scene" $false "M30B wrapper missing" }

[System.IO.File]::WriteAllLines($outPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "OUT|$outPath"
if ($failed) { exit 1 }
