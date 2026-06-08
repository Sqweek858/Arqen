$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "CommandAutomationCommon.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "m19a_runtime_loop_contract_validation.txt"
$runtimeContract = Join-Path $root "Runtime\RUNTIME_CONTRACT.md"
$dx12Contract = Join-Path $root "Backends\DX12\DX12_BACKEND_CONTRACT.md"
$handoffDoc = Join-Path $root "Docs\M19_HANDOFF.md"
$capPath = Join-Path $root "Backends\WindowsX64PE\Config\capabilities_v0.txt"
$runnerPath = Join-Path $root "Tools\run_test_slice.ps1"

$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) { $lines.Add("PASS|$Name|$Detail") | Out-Null } else { $script:failed = $true; $lines.Add("FAIL|$Name|$Detail") | Out-Null }
}

function Read-TextOrEmpty {
    param([string]$Path)
    if (Test-Path $Path) { return Get-Content $Path -Raw }
    return ""
}

function Read-Capabilities {
    param([string]$Path)
    $map = @{}
    if (-not (Test-Path $Path)) { return $map }
    foreach ($raw in Get-Content $Path) {
        $line = $raw.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        $parts = $line.Split([char]'|', 2)
        if ($parts.Length -eq 2) { $map[$parts[0]] = $parts[1] }
    }
    return $map
}

$runtimeText = Read-TextOrEmpty $runtimeContract
$dx12Text = Read-TextOrEmpty $dx12Contract
$handoffText = Read-TextOrEmpty $handoffDoc
$runnerText = Read-TextOrEmpty $runnerPath
$cap = Read-Capabilities $capPath

Add-Result "m19a_runtime_contract_exists" (Test-Path $runtimeContract) "runtime contract present"
Add-Result "m19a_runtime_loop_boundary" ($runtimeText.Contains('M19A runtime loop boundary') -and $runtimeText.Contains('message pump')) "loop ownership documented"
Add-Result "m19a_no_hidden_frame_simulation" ($runtimeText.Contains('No hidden frame simulation rule') -and $runtimeText.Contains('must not be faked')) "delta/frame timing remains real-runtime only"
Add-Result "m19a_event_execution_rule" ($runtimeText.Contains('Event execution rule') -and $runtimeText.Contains('visible ARQIR action')) "events stay capability-visible"
Add-Result "m19a_window_handoff_rule" ($runtimeText.Contains('Window handoff rule') -and $runtimeText.Contains('window handle')) "window handoff documented"
Add-Result "m19a_handoff_doc_exists" (Test-Path $handoffDoc) "M19 handoff checklist present"
Add-Result "m19a_handoff_has_design_and_dx12" ($handoffText.Contains('M19B Style / Design Foundation') -and $handoffText.Contains('M19D DX12 Skeleton')) "next slices are named"
Add-Result "m19a_dx12_skeleton_entry_criteria" ($dx12Text.Contains('M19D skeleton entry criteria') -and $dx12Text.Contains('clear-color')) "first DX12 skeleton is bounded"

foreach ($op in @('dx12', 'shader', 'render_pass', 'frame_update')) {
    Add-Result "m19a_reserved_still_unsupported_$op" ($cap.ContainsKey($op) -and $cap[$op] -eq 'unsupported') "reserved action remains unsupported"
}

foreach ($op in @('window_create', 'window_set_title', 'window_set_resolution', 'window_set_resizable', 'window_show', 'window_run', 'window_close', 'event_window_closed', 'event_key_pressed', 'event_end')) {
    Add-Result "m19a_current_runtime_supported_$op" ($cap.ContainsKey($op) -and $cap[$op] -eq 'supported') "current runtime action stays supported"
}

Add-Result "m19a_test_slice_alias" ($runnerText.Contains('"m19a"') -and $runnerText.Contains('m19a_runtime_loop')) "selective runner exposes M19A check"

Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
