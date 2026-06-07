$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "CommandAutomationCommon.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "backend_contract_docs_validation.txt"
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) { $lines.Add("PASS|$Name|$Detail") | Out-Null } else { $script:failed = $true; $lines.Add("FAIL|$Name|$Detail") | Out-Null }
}

$backendDocPath = Join-Path $root "Docs\BACKEND_CONTRACT.md"
$irDocPath = Join-Path $root "IR\ARQIR_V0_CONTRACT.md"
$dx12DocPath = Join-Path $root "Backends\DX12\DX12_BACKEND_CONTRACT.md"
$runtimeDocPath = Join-Path $root "Runtime\RUNTIME_CONTRACT.md"

$backendDoc = if (Test-Path $backendDocPath) { Get-Content $backendDocPath -Raw } else { "" }
$irDoc = if (Test-Path $irDocPath) { Get-Content $irDocPath -Raw } else { "" }
$dx12Doc = if (Test-Path $dx12DocPath) { Get-Content $dx12DocPath -Raw } else { "" }
$runtimeDoc = if (Test-Path $runtimeDocPath) { Get-Content $runtimeDocPath -Raw } else { "" }

Add-Result "backend_contract_exists" (Test-Path $backendDocPath) "backend contract doc present"
Add-Result "backend_contract_window_current" ($backendDoc.Contains('window_create') -and $backendDoc.Contains('CreateWindowExW')) "backend doc includes current window runtime"
Add-Result "backend_contract_file_current" ($backendDoc.Contains('file_write') -and $backendDoc.Contains('CreateFileW')) "backend doc includes current file runtime"
Add-Result "backend_contract_dx12_reserved" ($backendDoc.Contains('dx12') -and $backendDoc.Contains('frame_update')) "backend doc reserves DX12 actions"
Add-Result "ir_contract_exists" (Test-Path $irDocPath) "ARQIR v0 contract doc present"
Add-Result "ir_contract_action_capability_rule" ($irDoc.Contains('Every action') -and $irDoc.Contains('backend capability table')) "IR doc requires capability validation"
Add-Result "dx12_contract_exists" (Test-Path $dx12DocPath) "DX12 contract doc present"
Add-Result "dx12_contract_no_fake_support" ($dx12Doc.Contains('No fake support rule')) "DX12 doc forbids fake supported state"
Add-Result "runtime_contract_exists" (Test-Path $runtimeDocPath) "runtime contract doc present"
Add-Result "runtime_contract_timing_reserved" ($runtimeDoc.Contains('delta time') -and $runtimeDoc.Contains('frame count')) "runtime doc reserves timing"

Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
