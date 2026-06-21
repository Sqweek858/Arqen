param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m20e0_dx12_clear_readiness_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return "" }
    return Get-Content $Path -Raw
}

function Emit-Check {
    param([string]$Name, [bool]$Pass, [string]$Note = "")
    $prefix = if ($Pass) { "PASS" } else { "FAIL" }
    $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null
    if (-not $Pass) { $script:failed = $true }
}

$modelsPath = Join-Path $RepoRoot "Tools\M10GDriver\Core\Models.cs"
$corePath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Core.cs"
$dx12ParserPath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Dx12.cs"
$astPath = Join-Path $RepoRoot "Tools\M10GDriver\Frontend\AstEmit.cs"
$irEmitPath = Join-Path $RepoRoot "Tools\M10GDriver\Frontend\IrEmit.cs"
$irModelPath = Join-Path $RepoRoot "Tools\M10GDriver\Backend\IrModel.cs"
$expectedPath = Join-Path $RepoRoot "Tests\CommandTests\dx12\expected.txt"
$specPath = Join-Path $RepoRoot "Tests\CommandTests\misc\dx12.command.txt"
$m20Path = Join-Path $RepoRoot "Docs\Milestones\\M16_M20.md"
$miniBiblePath = Join-Path $RepoRoot "Docs\Milestones\\M16_M20.md"
$irDocPath = Join-Path $RepoRoot "Docs\Reference\IR\ARQIR_V0_CONTRACT.md"
$runtimeDocPath = Join-Path $RepoRoot "Docs\Reference\Runtime\RUNTIME_CONTRACT.md"
$dx12ContractPath = Join-Path $RepoRoot "Docs\Reference\Backends\DX12_BACKEND_CONTRACT.md"
$capPath = Join-Path $RepoRoot "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt"

$models = Read-TextSafe $modelsPath
$core = Read-TextSafe $corePath
$dx12Parser = Read-TextSafe $dx12ParserPath
$ast = Read-TextSafe $astPath
$irEmit = Read-TextSafe $irEmitPath
$irModel = Read-TextSafe $irModelPath
$expected = Read-TextSafe $expectedPath
$spec = Read-TextSafe $specPath
$m20 = Read-TextSafe $m20Path
$miniBible = Read-TextSafe $miniBiblePath
$irDoc = Read-TextSafe $irDocPath
$runtimeDoc = Read-TextSafe $runtimeDocPath
$dx12Contract = Read-TextSafe $dx12ContractPath
$cap = Read-TextSafe $capPath

Emit-Check "m20e0_dx12_clear_ready_model" ($models -match 'record Dx12RendererClearReady' -and $core -match '_dx12RendererClearReadies') "clear-ready model/list present"
Emit-Check "m20e0_dx12_clear_ready_finalizer" ($dx12Parser -match 'FinalizeDx12RendererClearReadiness' -and $dx12Parser -match '_dx12RendererWindowByName\.TryGetValue') "ready derived from parent+clear style"
Emit-Check "m20e0_dx12_clear_ready_ast" ($ast -match 'DX12_CLEAR_READY' -and $ast -match 'Dx12RendererClearReadies') "AST emits readiness metadata"
Emit-Check "m20e0_dx12_clear_ready_ir" ($irEmit -match 'DX12_CLEAR_READY' -and $irEmit -match 'Dx12ClearReadyIrLine') "IR emits readiness metadata"
Emit-Check "m20e0_dx12_clear_ready_strict_ir" ($irModel -match 'case "DX12_CLEAR_READY"' -and $irModel -match 'Malformed DX12_CLEAR_READY') "strict IR accepts readiness metadata"
Emit-Check "m20e0_dx12_clear_ready_docs" ($spec -match 'M20E0_READY_GATE' -and $m20 -match 'M20E0 DX12 clear-readiness metadata gate' -and $miniBible -match 'M20E0 clear-readiness metadata') "M20E0 docs/spec present"
Emit-Check "m20e0_dx12_clear_ready_contract_docs" ($irDoc -match 'DX12_CLEAR_READY' -and $runtimeDoc -match 'DX12_CLEAR_READY' -and $dx12Contract -match 'DX12_CLEAR_READY') "IR/runtime/backend docs include readiness metadata"
Emit-Check "m20e0_dx12_clear_ready_tests" ($expected -match 'valid_dx12_clear_ready_direct_style' -and $expected -match 'valid_dx12_clear_ready_preset_style' -and $expected -match 'valid_dx12_style_without_parent_metadata_only') "readiness command tests present"
Emit-Check "m20e0_dx12_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families still unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
