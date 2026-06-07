$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "CommandAutomationCommon.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "dx12_readiness_validation.txt"
$capPath = Join-Path $root "Backends\WindowsX64PE\Config\capabilities_v0.txt"
$dx12Contract = Join-Path $root "Backends\DX12\DX12_BACKEND_CONTRACT.md"
$runtimeContract = Join-Path $root "Runtime\RUNTIME_CONTRACT.md"
$irContract = Join-Path $root "Docs\M18B_DX12_READY_GATE.md"
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) { $lines.Add("PASS|$Name|$Detail") | Out-Null } else { $script:failed = $true; $lines.Add("FAIL|$Name|$Detail") | Out-Null }
}

$cap = @{}
foreach ($raw in Get-Content $capPath) {
    $line = $raw.Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
    $parts = $line.Split([char]'|', 2)
    if ($parts.Length -eq 2) { $cap[$parts[0]] = $parts[1] }
}

foreach ($op in @('window_create', 'window_show', 'window_run', 'event_window_closed', 'event_key_pressed', 'event_end', 'exit')) {
    Add-Result "window_runtime_supported_$op" ($cap.ContainsKey($op) -and $cap[$op] -eq 'supported') "current window runtime action is supported"
}
foreach ($op in @('dx12', 'shader', 'render_pass', 'frame_update')) {
    Add-Result "dx12_reserved_unsupported_$op" ($cap.ContainsKey($op) -and $cap[$op] -eq 'unsupported') "reserved until DX12 backend lands"
}

$dx12Text = if (Test-Path $dx12Contract) { Get-Content $dx12Contract -Raw } else { '' }
$runtimeText = if (Test-Path $runtimeContract) { Get-Content $runtimeContract -Raw } else { '' }
$gateText = if (Test-Path $irContract) { Get-Content $irContract -Raw } else { '' }

Add-Result "dx12_contract_doc" (Test-Path $dx12Contract) "DX12 backend contract exists"
Add-Result "dx12_contract_mentions_swapchain" ($dx12Text.Contains('swapchain') -and $dx12Text.Contains('command list') -and $dx12Text.Contains('descriptor')) "DX12 contract contains required backend concepts"
Add-Result "runtime_contract_doc" (Test-Path $runtimeContract) "runtime contract exists"
Add-Result "runtime_contract_mentions_frame" ($runtimeText.Contains('frame_update') -and $runtimeText.Contains('delta time') -and $runtimeText.Contains('elapsed time')) "runtime contract reserves frame timing concepts"
Add-Result "m18b_gate_doc" (Test-Path $irContract) "M18B readiness gate document exists"
Add-Result "m18b_gate_is_not_fake_dx12" ($gateText.Contains('DX12 remains unsupported') -and $gateText.Contains('ready to start')) "gate distinguishes readiness from implementation"

Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
