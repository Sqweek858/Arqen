param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m20g_dx12_frame_syntax_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Emit-Check { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

$modelsPath = Join-Path $RepoRoot "Tools\M10GDriver\Core\Models.cs"
$corePath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Core.cs"
$dx12ParserPath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Dx12.cs"
$astPath = Join-Path $RepoRoot "Tools\M10GDriver\Frontend\AstEmit.cs"
$irEmitPath = Join-Path $RepoRoot "Tools\M10GDriver\Frontend\IrEmit.cs"
$irModelPath = Join-Path $RepoRoot "Tools\M10GDriver\Backend\IrModel.cs"
$expectedPath = Join-Path $RepoRoot "Tests\CommandTests\dx12\expected.txt"
$samplePath = Join-Path $RepoRoot "Samples\DX12\dx12_frame_metadata_m20g.arq"
$specPath = Join-Path $RepoRoot "Specs\Commands\dx12.command.txt"
$m20Path = Join-Path $RepoRoot "Docs\M20_HANDOFF.md"
$miniBiblePath = Join-Path $RepoRoot "Docs\M20_DX12_MINI_BIBLE.md"
$irDocPath = Join-Path $RepoRoot "IR\ARQIR_V0_CONTRACT.md"
$runtimeDocPath = Join-Path $RepoRoot "Runtime\RUNTIME_CONTRACT.md"
$dx12DocPath = Join-Path $RepoRoot "Backends\DX12\DX12_BACKEND_CONTRACT.md"
$capPath = Join-Path $RepoRoot "Backends\WindowsX64PE\Config\capabilities_v0.txt"

$models = Read-TextSafe $modelsPath
$core = Read-TextSafe $corePath
$dx12Parser = Read-TextSafe $dx12ParserPath
$ast = Read-TextSafe $astPath
$irEmit = Read-TextSafe $irEmitPath
$irModel = Read-TextSafe $irModelPath
$expected = Read-TextSafe $expectedPath
$sample = Read-TextSafe $samplePath
$spec = Read-TextSafe $specPath
$m20 = Read-TextSafe $m20Path
$miniBible = Read-TextSafe $miniBiblePath
$irDoc = Read-TextSafe $irDocPath
$runtimeDoc = Read-TextSafe $runtimeDocPath
$dx12Doc = Read-TextSafe $dx12DocPath
$cap = Read-TextSafe $capPath

Emit-Check "m20g_frame_model" ($models -match 'record Dx12FrameCommand' -and $core -match '_dx12FrameCommands') "frame command model/list present"
Emit-Check "m20g_frame_parser_rules" ($core -match 'ParseDx12FrameBeginStatement' -and $core -match 'ParseDx12RendererClearStatement' -and $core -match 'ParseDx12FrameEndStatement' -and $core -match 'ParseDx12FramePresentStatement') "parser rules wired"
Emit-Check "m20g_frame_parser_semantics" ($dx12Parser -match 'EnsureDx12FrameRendererReady' -and $dx12Parser -match 'clear renderer' -and $dx12Parser -match 'must be parented to a window') "frame semantics present"
Emit-Check "m20g_frame_ast_ir" ($ast -match 'DX12_FRAME' -and $irEmit -match 'Dx12FrameIrLine' -and $irModel -match 'case "DX12_FRAME"') "AST/IR/strict IR accepts frame metadata"
Emit-Check "m20g_frame_sample" ((Test-Path $samplePath) -and $sample -match 'begin frame of "MainRenderer"' -and $sample -match 'present frame of "MainRenderer"') "M20G sample present"

$validCount = 0
$invalidCount = 0
if (Test-Path $expectedPath) {
    $entries = @(Get-Content $expectedPath | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") })
    $validCount = @($entries | Where-Object { $_ -like "valid_dx12_frame*" }).Count
    $invalidCount = @($entries | Where-Object { $_ -like "invalid_dx12_frame*" }).Count
}
Emit-Check "m20g_frame_valid_test_count" ($validCount -ge 4) "valid=$validCount"
Emit-Check "m20g_frame_invalid_test_count" ($invalidCount -ge 9) "invalid=$invalidCount"
Emit-Check "m20g_frame_expected_errors" ($expected -match 'invalid_dx12_frame_clear_outside_begin' -and $expected -match 'invalid_dx12_frame_present_twice') "frame invalid cases present"
Emit-Check "m20g_docs" ($spec -match 'M20G_FRAME_SYNTAX' -and $m20 -match 'M20G DX12 frame metadata syntax' -and $miniBible -match 'M20G frame metadata syntax') "M20G docs/spec present"
Emit-Check "m20g_contract_docs" ($irDoc -match 'DX12_FRAME' -and $runtimeDoc -match 'DX12_FRAME' -and $dx12Doc -match 'DX12_FRAME') "IR/runtime/DX12 contracts mention frame metadata"
Emit-Check "m20g_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
