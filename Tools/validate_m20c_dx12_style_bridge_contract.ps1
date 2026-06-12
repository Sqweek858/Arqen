param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m20c_dx12_style_bridge_contract_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return "" }
    return Get-Content $Path -Raw
}

function Emit-Check {
    param(
        [string]$Name,
        [bool]$Pass,
        [string]$Note = ""
    )

    $prefix = if ($Pass) { "PASS" } else { "FAIL" }
    $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null
    if (-not $Pass) { $script:failed = $true }
}

$modelsPath = Join-Path $RepoRoot "Tools\M10GDriver\Core\Models.cs"
$corePath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Core.cs"
$styleParserPath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Style.cs"
$astPath = Join-Path $RepoRoot "Tools\M10GDriver\Frontend\AstEmit.cs"
$irEmitPath = Join-Path $RepoRoot "Tools\M10GDriver\Frontend\IrEmit.cs"
$irModelPath = Join-Path $RepoRoot "Tools\M10GDriver\Backend\IrModel.cs"
$expectedPath = Join-Path $RepoRoot "Tests\CommandTests\dx12\expected.txt"
$specPath = Join-Path $RepoRoot "Specs\Commands\dx12.command.txt"
$miniBiblePath = Join-Path $RepoRoot "Docs\M20_DX12_MINI_BIBLE.md"
$m20Path = Join-Path $RepoRoot "Docs\M20_HANDOFF.md"
$dx12ContractPath = Join-Path $RepoRoot "Backends\DX12\DX12_BACKEND_CONTRACT.md"
$irDocPath = Join-Path $RepoRoot "IR\ARQIR_V0_CONTRACT.md"
$runtimeDocPath = Join-Path $RepoRoot "Runtime\RUNTIME_CONTRACT.md"
$capPath = Join-Path $RepoRoot "Backends\WindowsX64PE\Config\capabilities_v0.txt"

$models = Read-TextSafe $modelsPath
$core = Read-TextSafe $corePath
$styleParser = Read-TextSafe $styleParserPath
$ast = Read-TextSafe $astPath
$irEmit = Read-TextSafe $irEmitPath
$irModel = Read-TextSafe $irModelPath
$expected = Read-TextSafe $expectedPath
$spec = Read-TextSafe $specPath
$miniBible = Read-TextSafe $miniBiblePath
$m20 = Read-TextSafe $m20Path
$dx12Contract = Read-TextSafe $dx12ContractPath
$irDoc = Read-TextSafe $irDocPath
$runtimeDoc = Read-TextSafe $runtimeDocPath
$cap = Read-TextSafe $capPath

Emit-Check "m20c_dx12_clear_style_model" ($models -match 'record Dx12RendererClearStyle' -and $core -match '_dx12RendererClearStyles') "clear style model/list present"
Emit-Check "m20c_dx12_direct_style_bridge" ($styleParser -match 'RegisterDx12RendererStyleProperty' -and $styleParser -match 'style\.background_color') "direct renderer style bridge present"
Emit-Check "m20c_dx12_preset_style_bridge" ($styleParser -match 'RegisterDx12RendererStylePresetApplication' -and $styleParser -match 'style_preset\.\{styleTok\.Value\}\.background_color') "preset renderer style bridge present"
Emit-Check "m20c_dx12_style_semantics" ($styleParser -match 'S265' -and $styleParser -match 'S266' -and $styleParser -match 'S267' -and $styleParser -match 'only background color') "renderer style semantic guards present"
Emit-Check "m20c_dx12_ast_clear_style" ($ast -match 'DX12_CLEAR_STYLE' -and $ast -match 'Dx12RendererClearStyles') "AST emits clear style metadata"
Emit-Check "m20c_dx12_ir_clear_style" ($irEmit -match 'DX12_CLEAR_STYLE' -and $irEmit -match 'Dx12ClearStyleIrLine') "IR emits clear style metadata"
Emit-Check "m20c_dx12_strict_ir_clear_style" ($irModel -match 'case "DX12_CLEAR_STYLE"' -and $irModel -match 'Malformed DX12_CLEAR_STYLE') "strict IR accepts clear style metadata"
Emit-Check "m20c_dx12_spec_clear_style" ($spec -match 'DX12_CLEAR_STYLE' -and $spec -match 'M20C_STYLE_BRIDGE') "dx12 command spec documents style bridge"
Emit-Check "m20c_dx12_docs_clear_style" ($miniBible -match 'M20C style-derived clear metadata' -and $m20 -match 'M20C DX12 style bridge') "M20C docs present"
Emit-Check "m20c_dx12_backend_boundary" ($dx12Contract -match 'DX12_CLEAR_STYLE' -and $runtimeDoc -match 'DX12_CLEAR_STYLE') "backend/runtime docs keep metadata boundary"
Emit-Check "m20c_dx12_ir_doc" ($irDoc -match 'DX12_CLEAR_STYLE' -and $irDoc -match 'style-derived clear') "IR doc mentions clear style metadata"

$validCount = 0
$invalidCount = 0
if (Test-Path $expectedPath) {
    $entries = @(Get-Content $expectedPath | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") })
    $validCount = @($entries | Where-Object { $_ -like "valid_dx12*" }).Count
    $invalidCount = @($entries | Where-Object { $_ -like "invalid_dx12*" }).Count
}
Emit-Check "m20c_dx12_valid_test_count" ($validCount -ge 6) "valid=$validCount"
Emit-Check "m20c_dx12_invalid_test_count" ($invalidCount -ge 10) "invalid=$invalidCount"
Emit-Check "m20c_dx12_new_semantic_tests" ($expected -match 'invalid_dx12_renderer_style_state' -and $expected -match 'invalid_dx12_renderer_style_unsupported_property' -and $expected -match 'invalid_dx12_renderer_style_duplicate_clear_sources') "style bridge invalid cases present"
Emit-Check "m20c_dx12_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 action families still unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
