param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (git rev-parse --show-toplevel).Trim() }
$outPath = Join-Path $RepoRoot "Build\Generated\m30d_m31a_m31b_dx12_ui_controls_validation.txt"
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

function Get-RegexMatches([string]$Text, [string]$Pattern) {
    return [regex]::Matches($Text, $Pattern)
}
function Get-SampleUiDefinitionMap([string]$Text) {
    $map = @{}
    foreach ($m in (Get-RegexMatches $Text 'define (shape|text|button|checkbox|slider|input field|dropdown) called "([^\"]+)"')) {
        $map[$m.Groups[2].Value] = $m.Groups[1].Value
    }
    return $map
}
function Get-SampleUiParentMap([string]$Text, [ref]$DuplicateParentFound) {
    $map = @{}
    foreach ($m in (Get-RegexMatches $Text 'parent "([^\"]+)" to "([^\"]+)"')) {
        $child = $m.Groups[1].Value
        if ($map.ContainsKey($child)) { $DuplicateParentFound.Value = $true }
        $map[$child] = $m.Groups[2].Value
    }
    return $map
}
function Test-Parent([hashtable]$Map, [string]$Child, [string]$Parent) {
    return ($Map.ContainsKey($Child) -and $Map[$Child] -eq $Parent)
}

$lowerer = Read-All (Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1")
$runtime = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp")
$nativeBuilder = Read-All (Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1")
$wrapper = Read-All (Join-Path $RepoRoot "Tools\Build\DX12\build_m31a_dx12_ui_controls_scene.ps1")
$toolMap = Read-All (Join-Path $RepoRoot "Docs\Info\TOOLS.md")
$milestones = Read-All (Join-Path $RepoRoot "Docs\MILESTONES.md")
$docs = Read-All (Join-Path $RepoRoot "Docs\Milestones\\M31_M35.md")
$handoff = Read-All (Join-Path $RepoRoot "Docs\Milestones\\M31_M35.md")
$sampleReadme = Read-All (Join-Path $RepoRoot "Samples\README.md")
$spec = Read-All (Join-Path $RepoRoot "Tests\CommandTests\misc\dx12.command.txt")
$irContract = Read-All (Join-Path $RepoRoot "Docs\Reference\IR\ARQIR_V0_CONTRACT.md")
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_ui_controls_fancy_scene_m31a.arq"
$sample = Read-All $samplePath


$sampleUiDefs = Get-SampleUiDefinitionMap $sample
$duplicateSampleParent = $false
$sampleUiParents = Get-SampleUiParentMap $sample ([ref]$duplicateSampleParent)
$sampleRootUi = "InspectorPanel"
$sampleNonRootUi = @($sampleUiDefs.Keys | Where-Object { $_ -ne $sampleRootUi })
$unparentedSampleUi = @($sampleNonRootUi | Where-Object { -not $sampleUiParents.ContainsKey($_) })
$unknownSampleParents = @($sampleUiParents.GetEnumerator() | Where-Object { -not $sampleUiDefs.ContainsKey($_.Value) })
$mainM31Controls = @('AnimationSwitch','LightSwitch','ExposureSlider','ObjectNameInput','QualityDropdown','AnimationButton','DisabledButton')
$mainM31ControlsParentedToPanel = (@($mainM31Controls | Where-Object { -not (Test-Parent $sampleUiParents $_ 'InspectorPanel') }).Count -eq 0)
$buttonLabelParentsOk = ((Test-Parent $sampleUiParents 'AnimationButtonLabel' 'AnimationButton') -and (Test-Parent $sampleUiParents 'DisabledButtonLabel' 'DisabledButton'))
$buttonLabelsUseSmartLayout = ($buttonLabelParentsOk -and (-not $sample.Contains('with layout for "AnimationButtonLabel"')) -and (-not $sample.Contains('with layout for "DisabledButtonLabel"')))
$buttonContentDelegatedToLabels = ((-not $sample.Contains('set content of "AnimationButton"')) -and (-not $sample.Contains('set content of "DisabledButton"')) -and $sample.Contains('set content of "AnimationButtonLabel"') -and $sample.Contains('set content of "DisabledButtonLabel"'))
$buttonLabelsHaveOwnPadding = ($sample.Contains('with style for "AnimationButtonLabel"') -and $sample.Contains('with style for "DisabledButtonLabel"') -and $sample.Contains('padding: 4 px'))

Emit-Check "m31a_text_layout_hygiene" ($lowerer.Contains('New-UiTextVertices') -and $lowerer.Contains('New-UiRectVerticesClipped') -and $lowerer.Contains('Get-UiTextScale') -and $lowerer.Contains('M30B_TEXT_CLIPPING') -and $lowerer.Contains('M30B_BUTTON_TEXT_CENTERING')) "lowerer keeps M30B text clipping/centering while adding M31 controls"
Emit-Check "m30d_event_body_actions" ($lowerer.Contains('M30D_UI_EVENT_BODY_ACTIONS') -and $lowerer.Contains('Resolve-UiAction') -and $lowerer.Contains('EventBody') -and $lowerer.Contains('toggle fake light') -and $sample.Contains('print string "toggle animation"')) "M30D maps clicked event bodies to known runtime actions instead of target-name heuristics"
Emit-Check "m31a_control_expansion" ($lowerer.Contains('ARQEN_DX12_UI_CONTROL_SLIDER') -and $lowerer.Contains('ARQEN_DX12_UI_CONTROL_INPUT_FIELD') -and $lowerer.Contains('ARQEN_DX12_UI_CONTROL_DROPDOWN') -and $lowerer.Contains('_slider_knob') -and $lowerer.Contains("`$ui.Type -eq 'slider' -and `$valueMap.ContainsKey") -and $runtime.Contains('UpdateSliderValueFromCursor')) "M31A lowers slider/input/dropdown controls and runtime tracks value/focus/closed-state controls without parsing text input values as numbers"
Emit-Check "m31c_computed_layout_rects" ($lowerer.Contains('New-UiContentRect') -and $lowerer.Contains('Get-UiAlignedTextOrigin') -and $lowerer.Contains('M31C_UI_COMPUTED_LAYOUT_RECTS') -and $lowerer.Contains("if (`$value -eq 'middle') { return 'center' }") -and $sample.Contains('parent "AnimationButtonLabel" to "AnimationButton"') -and $sample.Contains('text align: center') -and $sample.Contains('vertical align: middle') -and $runtime.Contains('trackWidth > 1.0f ? control.trackX')) "M31C unifies computed UI rects, canonical middle vertical alignment, parented control labels, slider track hit mapping, and text alignment without new syntax"
Emit-Check "m31c_ui_parent_containment" ($lowerer.Contains('M31C_UI_PARENT_CONTAINMENT') -and $lowerer.Contains("`$parentClipsChildren = -not") -and $lowerer.Contains("overflow' 'hidden'") -and $lowerer.Contains("clip children' 'true'") -and $lowerer.Contains('$parentContentClip = Get-EffectiveUiContentRect $parentName $parentRect') -and $lowerer.Contains('$textClip = Join-UiClipRect $ownClip $textRect') -and $lowerer.Contains('$right - $tx') -and $lowerer.Contains('$bottom - $ty') -and $buttonLabelsHaveOwnPadding) "parent now means local content-space containment: child layouts resolve inside parent content rect, text padding is honored, and child text is clipped inside the parent/control by default"
Emit-Check "m31c_text_padding_defaults" ($lowerer.Contains('M31C_UI_TEXT_PADDING_DEFAULTS') -and $lowerer.Contains('function Get-UiTypeDefaultPadding') -and $lowerer.Contains("if (`$Type -eq 'text' -or `$Type -eq 'shape') { return 0.0 }") -and $lowerer.Contains("Get-EffectiveUiStyleNumber `$Target 'font size'") -and (-not $lowerer.Contains("Get-MapNumber `$styleMap `$ui.Name 'padding' (Get-MapNumber `$layoutMap `$ui.Name 'padding' 8.0)"))) "standalone text no longer receives the old 8px control padding by default, so 16-18px labels render as text instead of clipped dash fragments; font size is accepted as a style alias"
Emit-Check "m31c_ui_style_box_model" ($lowerer.Contains('M31C_UI_STYLE_BOX_MODEL') -and $lowerer.Contains('function Get-EffectiveUiStyleValue') -and $lowerer.Contains('function Get-EffectiveUiContentRect') -and $lowerer.Contains("`$contentRect = Get-EffectiveUiContentRect `$ui.Name `$rect") -and $lowerer.Contains("`$parentContentRect = Get-EffectiveUiContentRect `$parentName `$parentRect") -and $lowerer.Contains("`$borderSize = Get-EffectiveUiBorderSize `$ui.Name") -and $lowerer.Contains("`$inset = (Get-EffectiveUiPadding `$Target) + (Get-EffectiveUiBorderSize `$Target)")) "M31C routes style defaults/state/padding/border through one box-model resolver so parent content rects and control text use the same content-space math"
Emit-Check "m31c_ui_parent_topology" ($sampleUiDefs.ContainsKey($sampleRootUi) -and (-not $duplicateSampleParent) -and $unparentedSampleUi.Count -eq 0 -and $unknownSampleParents.Count -eq 0 -and $mainM31ControlsParentedToPanel) "M31 official sample parents every non-root UI object exactly once, keeps main controls under InspectorPanel, and avoids orphan/unknown parent layout regressions"
Emit-Check "m31c_button_label_smart_parent" ($buttonLabelParentsOk -and $buttonLabelsUseSmartLayout -and $buttonContentDelegatedToLabels -and $buttonLabelsHaveOwnPadding -and $sample.Contains('text align: center') -and $sample.Contains('vertical align: middle')) "button text is delegated to text children parented to their buttons, with no explicit label rects so M31C smart-parent centering owns the layout"
Emit-Check "m31c_lowerer_smart_parent_text" ($lowerer.Contains("`$childType -eq 'text' -and `$parentType -in `$uiControlTypes -and -not `$hasExplicitRect") -and $lowerer.Contains("`$rect = New-UiClipRect `$parentContentRect.X `$parentContentRect.Y `$parentContentRect.W `$parentContentRect.H") -and $lowerer.Contains('$smartParentText') -and $lowerer.Contains('$textRect = $contentRect') -and $lowerer.Contains("Get-EffectiveUiVerticalAlign `$ui.Name 'center'")) "lowerer resolves text children of controls into the parent content rect and centers them without author-side pixel math"
Emit-Check "m31c_slider_runtime_visuals" ($runtime.Contains('ApplyUiSliderDynamicGeometry') -and $runtime.Contains('ArqenDx12UiControlRoleSliderFill') -and $runtime.Contains('ArqenDx12UiControlRoleSliderKnob') -and $runtime.Contains('(std::numeric_limits<float>::max)()') -and (-not $runtime.Contains('std::numeric_limits<float>::max();')) -and $lowerer.Contains('sliderFillTransformIndex') -and $lowerer.Contains('sliderKnobTransformIndex') -and $lowerer.Contains('M31C_UI_SLIDER_RUNTIME_VISUALS')) "M31C gives slider fill/knob dedicated runtime roles so drag updates are visible and avoids Windows min/max macro collisions"
Emit-Check "m31c_stable_client_pixel_space" ($lowerer.Contains('M31C_UI_STABLE_CLIENT_PIXEL_SPACE') -and $nativeBuilder.Contains('M31C_UI_STABLE_CLIENT_PIXEL_SPACE') -and $nativeBuilder.Contains('EnableArqenDpiAwareness') -and $nativeBuilder.Contains('ArqenFixedClientWindowStyle') -and $nativeBuilder.Contains('ArqenOuterWindowSizeForClient') -and $nativeBuilder.Contains('~WS_THICKFRAME') -and $nativeBuilder.Contains('~WS_MAXIMIZEBOX') -and $nativeBuilder.Contains('GetClientRect(hwnd, &clientRect)') -and $runtime.Contains('ClientCursorToLogicalUiPoint') -and $runtime.Contains('authoredWidth') -and $runtime.Contains('authoredHeight')) "M31C keeps generated DX12 UI in one authored client-pixel coordinate space: fixed exact client window, DPI awareness, no resize/maximize drift, and scaled mouse input for hover/click/slider"
Emit-Check "m31c_sample_visual_redesign" ($sample.Contains('define text called "SliderHintText"') -and $sample.Contains('DRAG THE CYAN KNOB - RUNTIME VISUAL') -and $sample.Contains('width: 610 px') -and $sample.Contains('ANIMATE CENTERED') -and $sample.Contains('LOCKED CENTER')) "official M31 sample visibly showcases centered parent labels and a wide draggable slider"
Emit-Check "m31a_hover_pressed_focus_states" ($runtime.Contains('hoveredUiControlIndex_') -and $runtime.Contains('pressedUiControlIndex_') -and $runtime.Contains('focusedUiControlIndex_') -and $runtime.Contains('control.enabled == 0u')) "runtime supports hover/pressed/focus/disabled feedback for UI controls"
Emit-Check "m31b_resource_metadata_bridge" ($lowerer.Contains('UI_RESOURCE') -and $lowerer.Contains('UI_RESOURCE_USE') -and $sample.Contains('define font called') -and $sample.Contains('define texture called') -and $sample.Contains('set font of') -and $sample.Contains('set texture of')) "M31B bridges existing font/texture resource metadata as runtime markers without full font/texture engine yet"
Emit-Check "m31a_sample_uses_existing_contracts" ($sample.Contains('define slider called "ExposureSlider"') -and $sample.Contains('define input field called "ObjectNameInput"') -and $sample.Contains('define dropdown called "QualityDropdown"') -and $sample.Contains('set enabled of "DisabledButton" to false') -and $sample.Contains('when clicked "AnimationButton"') -and $sample.Contains('print string "toggle animation"') -and $sample.Contains('vertical align: middle') -and (-not $sample.Contains('vertical align: center'))) "official M31 sample uses existing UI/style/layout/final/resource contracts and canonical style enum values without new syntax"
Emit-Check "m31a_wrapper" ($wrapper.Contains('dx12_ui_controls_fancy_scene_m31a.arq') -and $wrapper.Contains('M31A_UI_CONTROLS_EXPANSION|True') -and $wrapper.Contains('M31C_UI_PARENT_CONTAINMENT|True') -and $wrapper.Contains('M31C_UI_TEXT_PADDING_DEFAULTS|True') -and $wrapper.Contains('M31C_UI_STYLE_BOX_MODEL|True') -and $wrapper.Contains('M31C_UI_SLIDER_RUNTIME_VISUALS|True') -and $wrapper.Contains('M31C_UI_STABLE_CLIENT_PIXEL_SPACE|True') -and $wrapper.Contains('M31B_UI_RESOURCE_METADATA_BRIDGE|True')) "M31 wrapper validates compile/lower markers for control expansion, runtime slider visuals, and resource metadata"
Emit-Check "m31a_docs_spec_toolmap" ($docs.Contains('M31A') -and $docs.Contains('slider') -and $docs.Contains('input field') -and $docs.Contains('dropdown') -and $docs.Contains('event body') -and $docs.Contains('M31C_UI_PARENT_CONTAINMENT') -and $docs.Contains('M31C_UI_TEXT_PADDING_DEFAULTS') -and $docs.Contains('M31C_UI_STYLE_BOX_MODEL') -and $docs.Contains('M31C_UI_SLIDER_RUNTIME_VISUALS') -and $docs.Contains('M31C_UI_STABLE_CLIENT_PIXEL_SPACE') -and $handoff.Contains('build_m31a_dx12_ui_controls_scene.ps1') -and $toolMap.Contains('M31C_UI_PARENT_CONTAINMENT') -and $toolMap.Contains('M31C_UI_TEXT_PADDING_DEFAULTS') -and $toolMap.Contains('M31C_UI_STYLE_BOX_MODEL') -and $toolMap.Contains('M31C_UI_SLIDER_RUNTIME_VISUALS') -and $toolMap.Contains('M31C_UI_STABLE_CLIENT_PIXEL_SPACE') -and $toolMap.Contains('validate_m30d_m31a_m31b_dx12_ui_controls.ps1') -and $milestones.Contains('M31A') -and $sampleReadme.Contains('dx12_ui_controls_fancy_scene_m31a.arq') -and $sampleReadme.Contains('M31C_UI_PARENT_CONTAINMENT') -and $sampleReadme.Contains('M31C_UI_TEXT_PADDING_DEFAULTS') -and $sampleReadme.Contains('M31C_UI_STYLE_BOX_MODEL') -and $sampleReadme.Contains('M31C_UI_SLIDER_RUNTIME_VISUALS') -and $sampleReadme.Contains('M31C_UI_STABLE_CLIENT_PIXEL_SPACE') -and $spec.Contains('M31A_UI_CONTROLS_EXPANSION') -and $spec.Contains('M31C_UI_PARENT_CONTAINMENT') -and $spec.Contains('M31C_UI_TEXT_PADDING_DEFAULTS') -and $spec.Contains('M31C_UI_STYLE_BOX_MODEL') -and $spec.Contains('M31C_UI_SLIDER_RUNTIME_VISUALS') -and $spec.Contains('M31C_UI_STABLE_CLIENT_PIXEL_SPACE') -and $irContract.Contains('M31B_UI_RESOURCE_METADATA_BRIDGE') -and $irContract.Contains('M31C_UI_PARENT_CONTAINMENT') -and $irContract.Contains('M31C_UI_TEXT_PADDING_DEFAULTS') -and $irContract.Contains('M31C_UI_STYLE_BOX_MODEL') -and $irContract.Contains('M31C_UI_SLIDER_RUNTIME_VISUALS') -and $irContract.Contains('M31C_UI_STABLE_CLIENT_PIXEL_SPACE')) "docs/spec/tool map/sample README/IR contract document M30D/M31A/M31B UI runtime subset"
Emit-Check "m31a_future_scope_blocked" ($docs.Contains('No full font engine') -and $docs.Contains('No texture sampling UI') -and $docs.Contains('No dropdown popup') -and $docs.Contains('No editable text input')) "M31 explicitly avoids larger UI/editor/resource families"

$runtime = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp")
$wrapperPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m31a_dx12_ui_controls_scene.ps1"
if (Test-Path $wrapperPath) {
    try {
        & $wrapperPath -RepoRoot $RepoRoot -SourcePath $samplePath -OutDir (Join-Path $RepoRoot "Build\M31A") -FrameCount 90 -TargetFps 30 -HoldMilliseconds 3000 -Quiet
        $manifestPath = Join-Path $RepoRoot "Build\M31A\dx12_clear_manifest.generated.txt"
        $configPath = Join-Path $RepoRoot "Build\M31A\dx12_clear_config.generated.h"
        $manifest = Read-All $manifestPath
        $config = Read-All $configPath
        Emit-Check "m31a_wrapper_compiles_lowers_scene" ($manifest.Contains('M30B_UI_LAYOUT_HYGIENE|True') -and $manifest.Contains('M30D_UI_EVENT_BODY_ACTIONS|True') -and $manifest.Contains('M31A_UI_CONTROLS_EXPANSION|True') -and $manifest.Contains('M31B_UI_RESOURCE_METADATA_BRIDGE|True') -and $manifest.Contains('M31C_UI_COMPUTED_LAYOUT_RECTS|True') -and $manifest.Contains('M31C_UI_PARENT_CONTAINMENT|True') -and $manifest.Contains('M31C_UI_TEXT_PADDING_DEFAULTS|True') -and $manifest.Contains('M31C_UI_STYLE_BOX_MODEL|True') -and $manifest.Contains('M31C_UI_SLIDER_RUNTIME_VISUALS|True') -and $manifest.Contains('M31C_UI_STABLE_CLIENT_PIXEL_SPACE|True') -and $config.Contains('ARQEN_M30D_UI_EVENT_BODY_ACTIONS 1') -and $config.Contains('ARQEN_M31A_UI_CONTROLS_EXPANSION 1') -and $config.Contains('ARQEN_M31C_UI_COMPUTED_LAYOUT_RECTS 1') -and $config.Contains('ARQEN_M31C_UI_PARENT_CONTAINMENT 1') -and $config.Contains('ARQEN_M31C_UI_TEXT_PADDING_DEFAULTS 1') -and $config.Contains('ARQEN_M31C_UI_STYLE_BOX_MODEL 1') -and $config.Contains('ARQEN_M31C_UI_SLIDER_RUNTIME_VISUALS 1') -and $config.Contains('ARQEN_M31C_UI_STABLE_CLIENT_PIXEL_SPACE 1') -and $config.Contains('ARQEN_DX12_UI_CONTROL_SLIDER') -and $manifest.Contains('object=AnimationButtonLabel') -and $manifest.Contains('object=DisabledButtonLabel') -and $config.Contains('2415919') -and $config.Contains('2684354')) "M30D/M31A/M31B wrapper compiles/lowers official sample with event/control/resource markers and dedicated slider visual draw-call roles"
    } catch {
        Emit-Check "m31a_wrapper_compiles_lowers_scene" $false $_.Exception.Message
    }
} else { Emit-Check "m31a_wrapper_compiles_lowers_scene" $false "M30D/M31A/M31B wrapper missing" }

[System.IO.File]::WriteAllLines($outPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "OUT|$outPath"
if ($failed) { exit 1 }
