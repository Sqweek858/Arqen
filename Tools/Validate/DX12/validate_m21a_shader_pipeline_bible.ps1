param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m21a_shader_pipeline_bible_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Emit-Check { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

$miniBiblePath = Join-Path $RepoRoot "Docs\Milestones\\M21_M25.md"
$handoffPath = Join-Path $RepoRoot "Docs\Milestones\\M21_M25.md"
$specPath = Join-Path $RepoRoot "Tests\CommandTests\misc\dx12.command.txt"
$commandRegistryPath = Join-Path $RepoRoot "Docs\Language\LANGUAGE.md"
$dx12DocPath = Join-Path $RepoRoot "Docs\Reference\Backends\DX12_BACKEND_CONTRACT.md"
$runtimeDocPath = Join-Path $RepoRoot "Docs\Reference\Runtime\RUNTIME_CONTRACT.md"
$irDocPath = Join-Path $RepoRoot "Docs\Reference\IR\ARQIR_V0_CONTRACT.md"
$capPath = Join-Path $RepoRoot "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt"

$miniBible = Read-TextSafe $miniBiblePath
$handoff = Read-TextSafe $handoffPath
$spec = Read-TextSafe $specPath
$registry = Read-TextSafe $commandRegistryPath
$dx12Doc = Read-TextSafe $dx12DocPath
$runtimeDoc = Read-TextSafe $runtimeDocPath
$irDoc = Read-TextSafe $irDocPath
$cap = Read-TextSafe $capPath

Emit-Check "m21a_mini_bible_exists" ((Test-Path $miniBiblePath) -and $miniBible.Contains('define shader called') -and $miniBible.Contains('define dx12 pipeline called') -and $miniBible.Contains('use pipeline')) "M21 shader/pipeline mini bible present"
Emit-Check "m21a_handoff_exists" ((Test-Path $handoffPath) -and $handoff.Contains('DX12_SHADER') -and $handoff.Contains('DX12_PIPELINE_BIND')) "M21 handoff present"
Emit-Check "m21a_spec_records_syntax" ($spec -match 'M21A_SHADER_PIPELINE_BIBLE' -and $spec -match 'M21B_SHADER_SYNTAX' -and $spec -match 'M21B_PIPELINE_BIND_SYNTAX') "dx12 command spec records M21 shader/pipeline syntax"
Emit-Check "m21a_registry_records_boundary" ($registry -match 'M21A/M21B DX12 shader/pipeline metadata' -and $registry -match 'No HLSL compilation') "command registry records metadata boundary"
Emit-Check "m21a_contract_docs" ($dx12Doc -match 'DX12_SHADER' -and $runtimeDoc -match 'DX12_PIPELINE_BIND' -and $irDoc -match 'DX12_PIPELINE') "DX12/runtime/IR contracts document M21 metadata"
Emit-Check "m21a_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
