param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (git rev-parse --show-toplevel).Trim() }
$outPath = Join-Path $RepoRoot "Build\Generated\m29c_dx12_object_selector_rotate_validation.txt"
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

$models = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Core\Models.cs")
$parser = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Dx12.cs")
$parserCore = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Core.cs")
$astEmit = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Frontend\AstEmit.cs")
$irEmit = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Frontend\IrEmit.cs")
$strictIr = Read-All (Join-Path $RepoRoot "Tools\M10GDriver\Backend\IrModel.cs")
$lowerer = Read-All (Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1")
$runtimeHeader = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.h")
$runtimeCpp = Read-All (Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp")
$nativeBuilder = Read-All (Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1")
$wrapper = Read-All (Join-Path $RepoRoot "Tools\Build\DX12\build_m29c_dx12_object_selector_rotate_scene.ps1")
$toolMap = Read-All (Join-Path $RepoRoot "Docs\Info\TOOLS.md")
$milestones = Read-All (Join-Path $RepoRoot "Docs\MILESTONES.md")
$docs = Read-All (Join-Path $RepoRoot "Docs\Milestones\\M26_M30.md")
$handoff = Read-All (Join-Path $RepoRoot "Docs\Milestones\\M26_M30.md")
$sampleReadme = Read-All (Join-Path $RepoRoot "Samples\README.md")
$spec = Read-All (Join-Path $RepoRoot "Tests\CommandTests\misc\dx12.command.txt")
$irContract = Read-All (Join-Path $RepoRoot "Docs\Reference\IR\ARQIR_V0_CONTRACT.md")
$expected = Read-All (Join-Path $RepoRoot "Tests\CommandTests\dx12\expected.txt")
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_object_selector_rotate_scene_m29c.arq"
$sample = Read-All $samplePath

Emit-Check "m29c_models_ast_ir" ($models.Contains('Dx12ObjectSelector') -and $models.Contains('Dx12ObjectSelectionBinding') -and $models.Contains('Dx12SelectedObjectRotateBinding') -and $astEmit.Contains('DX12_OBJECT_SELECTOR') -and $irEmit.Contains('DX12_SELECTED_OBJECT_ROTATE') -and $strictIr.Contains('DX12_OBJECT_SELECT_BINDING')) "M29C selector/rotate metadata model/AST/IR/strict IR present"
Emit-Check "m29c_parser_syntax" ($parserCore.Contains('ParseDx12ObjectSelectorDefinitionStatement') -and $parser.Contains('define object selector') -and $parser.Contains('select object using') -and $parser.Contains('ExpectWord("using"') -and $parser.Contains('rotate selected object around') -and $parser.Contains('supports only axis y')) "parser recognizes selector/use/select/rotate syntax with strict M29C axis limits and parses using as a normal word token"
Emit-Check "m29c_command_tests" ($expected.Contains('valid_dx12_object_selector_rotate_metadata.arq') -and $expected.Contains('invalid_dx12_selector_unknown_renderer.arq') -and $expected.Contains('invalid_dx12_select_with_unknown_selector.arq') -and $expected.Contains('invalid_dx12_rotate_selected_without_selector.arq') -and $expected.Contains('invalid_dx12_rotate_selected_bad_axis.arq') -and $expected.Contains('invalid_dx12_selector_duplicate_name.arq')) "M29C positive and negative command tests are listed"
Emit-Check "m29c_sample_exists" ((Test-Path $samplePath) -and $sample.Contains('define object selector called "PrimarySelector"') -and $sample.Contains('when mouse button "Left" is pressed select object using "PrimarySelector"') -and $sample.Contains('when key "R" is held rotate selected object around y by mouse x sensitivity 0.35')) "official M29C object selector rotate sample present"
Emit-Check "m29c_lowerer_markers" ($lowerer.Contains('DX12_OBJECT_SELECTOR') -and $lowerer.Contains('M29C_OBJECT_SELECTOR') -and $lowerer.Contains('ARQEN_M29C_OBJECT_SELECTOR_ENABLED') -and $lowerer.Contains('ARQEN_M29C_SELECTED_OBJECT_ROTATE_BINDING_DATA') -and $lowerer.Contains('@($matchingDrawObjects).Count')) "lowerer validates selector contract and emits M29C manifest/config markers"
Emit-Check "m29c_runtime_selector_rotate" ($runtimeHeader.Contains('ArqenDx12SelectedObjectRotateBinding') -and $runtimeCpp.Contains('SelectObjectAtCursor') -and $runtimeCpp.Contains('ProjectDrawCallBounds') -and $runtimeCpp.Contains('RotateSelectedObject') -and $runtimeCpp.Contains('selectedObjectIndex_') -and $runtimeCpp.Contains('dynamicObjectTransforms_') -and $runtimeCpp.Contains('(std::numeric_limits<float>::max)()')) "runtime supports LMB projected-bounds picking, selected object Y rotation around transform center, and avoids Windows max macro collision"
Emit-Check "m29c_selection_qol" ($runtimeCpp.Contains('selectedObjectIndex_ = bestIndex') -and $runtimeCpp.Contains('ApplySelectedObjectFeedback') -and $runtimeCpp.Contains('HasInputForeground') -and $runtimeCpp.Contains('ResetInputTransientState')) "selection deselects on empty click, gives selected-object tint feedback, and ignores input while not foreground"
Emit-Check "m29c_native_builder" ($nativeBuilder.Contains('selectedObjectRotateBindings') -and $nativeBuilder.Contains('ARQEN_M29C_OBJECT_SELECT_BUTTON') -and $nativeBuilder.Contains('ARQEN_M29C_OBJECT_SELECTOR_ENABLED')) "native builder forwards M29C selector/rotate data into runtime desc"
Emit-Check "m29c_wrapper" ($wrapper.Contains('dx12_object_selector_rotate_scene_m29c.arq') -and $wrapper.Contains('M29C_OBJECT_SELECTOR|True') -and $wrapper.Contains('m29c_dx12_object_selector_rotate_scene.exe')) "M29C wrapper validates compile/lower/native-build markers"
Emit-Check "m29c_docs_spec_toolmap" ($docs.Contains('M29C') -and $docs.Contains('object selector') -and $docs.Contains('R held') -and $docs.Contains('Click in empty space deselects') -and $docs.Contains('foreground window') -and $handoff.Contains('build_m29c_dx12_object_selector_rotate_scene.ps1') -and $toolMap.Contains('validate_m29c_dx12_object_selector_rotate.ps1') -and $milestones.Contains('M29C') -and $sampleReadme.Contains('dx12_object_selector_rotate_scene_m29c.arq') -and $spec.Contains('M29C_OBJECT_SELECTOR') -and $irContract.Contains('DX12_OBJECT_SELECTOR')) "docs/spec/tool map/sample README/IR contract document M29C contracts"
Emit-Check "m29c_future_scope_blocked" ($docs.Contains('No screen gizmo') -and $docs.Contains('No outline handles') -and $docs.Contains('No multi-select') -and $docs.Contains('No undo') -and $docs.Contains('No mesh import')) "M29C explicitly avoids full editor/gizmo families"

$wrapperPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m29c_dx12_object_selector_rotate_scene.ps1"
if (Test-Path $wrapperPath) {
    try {
        & $wrapperPath -RepoRoot $RepoRoot -SourcePath $samplePath -OutDir (Join-Path $RepoRoot "Build\M29C") -FrameCount 90 -TargetFps 30 -HoldMilliseconds 3000 -Quiet
        $manifestPath = Join-Path $RepoRoot "Build\M29C\dx12_clear_manifest.generated.txt"
        $configPath = Join-Path $RepoRoot "Build\M29C\dx12_clear_config.generated.h"
        $manifest = Read-All $manifestPath
        $config = Read-All $configPath
        Emit-Check "m29c_wrapper_compiles_lowers_scene" ($manifest.Contains('M29C_OBJECT_SELECTOR|True') -and $manifest.Contains('M29C_SELECT_BINDINGS|1') -and $manifest.Contains('M29C_ROTATE_BINDINGS|1') -and $config.Contains('ARQEN_M29C_OBJECT_SELECTOR_ENABLED 1') -and $config.Contains('ARQEN_M29C_SELECTED_OBJECT_ROTATE_BINDING_COUNT 1')) "M29C wrapper compiles/lowers official sample with selector/rotate markers"
    } catch {
        Emit-Check "m29c_wrapper_compiles_lowers_scene" $false $_.Exception.Message
    }
} else { Emit-Check "m29c_wrapper_compiles_lowers_scene" $false "M29C wrapper missing" }

[System.IO.File]::WriteAllLines($outPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "OUT|$outPath"
if ($failed) { exit 1 }
