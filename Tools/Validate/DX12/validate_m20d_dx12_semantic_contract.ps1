param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m20d_dx12_semantic_contract_validation.txt"
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

$corePath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Core.cs"
$dx12ParserPath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Dx12.cs"
$symbolsPath = Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.SymbolsFlow.cs"
$expectedPath = Join-Path $RepoRoot "Tests\CommandTests\dx12\expected.txt"
$specPath = Join-Path $RepoRoot "Tests\CommandTests\misc\dx12.command.txt"
$miniBiblePath = Join-Path $RepoRoot "Docs\Milestones\\M16_M20.md"
$m20Path = Join-Path $RepoRoot "Docs\Milestones\\M16_M20.md"
$capPath = Join-Path $RepoRoot "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt"

$core = Read-TextSafe $corePath
$dx12Parser = Read-TextSafe $dx12ParserPath
$symbols = Read-TextSafe $symbolsPath
$expected = Read-TextSafe $expectedPath
$spec = Read-TextSafe $specPath
$miniBible = Read-TextSafe $miniBiblePath
$m20 = Read-TextSafe $m20Path
$cap = Read-TextSafe $capPath

Emit-Check "m20d_dx12_symbol_conflict_before_renderer" ($dx12Parser -match 'SymbolExists\(nameTok\.Value\)' -and $dx12Parser -match 'conflicts with an existing object name') "renderer definition rejects existing symbols/windows/UI objects"
Emit-Check "m20d_dx12_symbol_conflict_after_renderer" ($symbols -match '_dx12RendererNames\.Contains\(nameTok\.Value\)' -and $symbols -match 'conflicts with an existing DX12 renderer name') "later variable definitions reject renderer names"
Emit-Check "m20d_dx12_parent_semantics_still_strict" ($dx12Parser -match 'Unknown DX12 renderer' -and $dx12Parser -match 'Window .* is not defined' -and $dx12Parser -match 'already has a parent window') "parent semantics preserved"
Emit-Check "m20d_dx12_docs_semantic_hardening" ($spec -match 'M20D_SEMANTIC_RULE' -and $miniBible -match 'M20D semantic hardening' -and $m20 -match 'M20D DX12 semantic hardening') "M20D docs/spec present"

$validCount = 0
$invalidCount = 0
if (Test-Path $expectedPath) {
    $entries = @(Get-Content $expectedPath | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") })
    $validCount = @($entries | Where-Object { $_ -like "valid_dx12*" }).Count
    $invalidCount = @($entries | Where-Object { $_ -like "invalid_dx12*" }).Count
}
Emit-Check "m20d_dx12_valid_test_count" ($validCount -ge 10) "valid=$validCount"
Emit-Check "m20d_dx12_invalid_test_count" ($invalidCount -ge 18) "invalid=$invalidCount"
Emit-Check "m20d_dx12_conflict_tests" ($expected -match 'invalid_dx12_renderer_conflicts_variable_before' -and $expected -match 'invalid_dx12_variable_conflicts_renderer_after' -and $expected -match 'invalid_dx12_parent_to_button_instead_of_window') "conflict/parent invalid cases present"
Emit-Check "m20d_dx12_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families still unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
