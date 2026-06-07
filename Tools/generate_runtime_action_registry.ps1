$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "CommandAutomationCommon.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "runtime_action_registry.txt"
$summaryPath = Join-Path $generated "runtime_action_summary.txt"
$programPath = Join-Path $root "Tools\M10GDriver\Program.cs"
$capabilitiesPath = Join-Path $root "Backends\WindowsX64PE\Config\capabilities_v0.txt"

$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Add-Line {
    param([string]$Line)
    $lines.Add($Line) | Out-Null
}

function Add-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) {
        Add-Line "PASS|$Name|$Detail"
    } else {
        $script:failed = $true
        Add-Line "FAIL|$Name|$Detail"
    }
}

$source = Get-Content $programPath -Raw
$actions = [ordered]@{}

function Add-Action {
    param([string]$Op, [string]$Source)
    if ([string]::IsNullOrWhiteSpace($Op)) { return }
    if (-not $actions.Contains($Op)) {
        $actions[$Op] = New-Object System.Collections.Generic.List[string]
    }
    if (-not $actions[$Op].Contains($Source)) {
        $actions[$Op].Add($Source) | Out-Null
    }
}

foreach ($m in [regex]::Matches($source, 'new\s+RuntimeAction\("([a-zA-Z0-9_]+)"')) {
    Add-Action $m.Groups[1].Value "RuntimeAction"
}
foreach ($m in [regex]::Matches($source, 'IrActionLine\([^\r\n]+?,\s*"([a-zA-Z0-9_]+)"')) {
    Add-Action $m.Groups[1].Value "IrActionLine"
}
foreach ($op in @("show_message", "print_stdout", "exit")) {
    Add-Action $op "baseline_ir"
}

$cap = @{}
foreach ($raw in Get-Content $capabilitiesPath) {
    $line = $raw.Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
    $parts = $line.Split([char]'|', 2)
    if ($parts.Length -eq 2) {
        $cap[$parts[0]] = $parts[1]
    }
}

Add-Line "RUNTIME_ACTION_REGISTRY|generated"
$missing = 0
$unsupported = 0
foreach ($op in ($actions.Keys | Sort-Object)) {
    $state = if ($cap.ContainsKey($op)) { $cap[$op] } else { "missing" }
    if ($state -eq "missing") { $missing += 1 }
    if ($state -eq "unsupported") { $unsupported += 1 }
    Add-Line "ACTION|$op|capability=$state|sources=$($actions[$op] -join ',')"
}

$required = @("show_message", "print_stdout", "exit", "file_write", "file_append", "file_load", "print_runtime_slot", "command_arg_count", "command_arg_index", "window_create", "window_run", "window_close", "event_window_closed", "event_key_pressed", "event_end")
foreach ($op in $required) {
    Add-Check "runtime_action_$op" ($actions.Contains($op)) "required emitted/runtime action present"
}
Add-Check "runtime_actions_have_capabilities" ($missing -eq 0 -and $unsupported -eq 0) "missing=$missing unsupported=$unsupported"
Add-Check "runtime_action_count_min" ($actions.Count -ge 18) "count=$($actions.Count)"

Add-Line "SUMMARY|actions=$($actions.Count)|missingCapabilities=$missing|unsupportedCapabilities=$unsupported"
Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8
Set-Content -Path $summaryPath -Value @("ACTIONS|$($actions.Count)", "MISSING_CAPABILITIES|$missing", "UNSUPPORTED_CAPABILITIES|$unsupported") -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
