$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
Import-Module (Join-Path $RepoRoot "Tools\Common\CommandAutomationCommon.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "backend_capability_validation.txt"
$capPath = Join-Path $root "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt"
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) {
        $lines.Add("PASS|$Name|$Detail") | Out-Null
    } else {
        $script:failed = $true
        $lines.Add("FAIL|$Name|$Detail") | Out-Null
    }
}

$cap = @{}
foreach ($raw in Get-Content $capPath) {
    $line = $raw.Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
    $parts = $line.Split([char]"|", 2)
    if ($parts.Length -ne 2) {
        Add-Result "malformed_line" $false $line
        continue
    }
    if ($cap.ContainsKey($parts[0])) {
        Add-Result "duplicate_$($parts[0])" $false "duplicate capability key"
    }
    $cap[$parts[0]] = $parts[1]
}

$supported = @(
    "show_message", "print_stdout", "print_runtime_slot",
    "file_write", "file_append", "file_load",
    "command_arg_count", "command_arg_index",
    "runtime_int_set", "runtime_int_add", "runtime_int_sub",
    "runtime_bool_set", "runtime_bool_not_set", "runtime_bool_toggle",
    "runtime_string_set", "runtime_string_concat", "runtime_string_substring",
    "runtime_int_parse",
    "runtime_if_int", "runtime_if_bool", "runtime_if_string", "runtime_else", "runtime_if_end",
    "runtime_while_int", "runtime_break", "runtime_continue", "runtime_while_end",
    "function_call", "function_call_assign", "function_return", "function_return_int", "function_return_bool", "function_return_string",
    "window_create", "window_set_title", "window_set_resolution", "window_set_resizable", "window_style_title_bar_color", "window_style_title_text_color", "window_show", "window_run", "window_close",
    "event_window_closed", "event_key_pressed", "event_end",
    "exit"
)
$unsupported = @("branch", "loop", "function", "ui_element", "dx12", "shader", "render_pass", "frame_update")

foreach ($op in $supported) {
    Add-Result "supported_$op" ($cap.ContainsKey($op) -and $cap[$op] -eq "supported") "must match backend/runtime implementation"
}
foreach ($op in $unsupported) {
    Add-Result "unsupported_$op" ($cap.ContainsKey($op) -and $cap[$op] -eq "unsupported") "reserved or not emitted by current backend"
}

$moduleText = Get-Content (Join-Path $root "Tools\Common\WindowsX64PE.psm1") -Raw
Add-Result "artifact_check_window" ($moduleText.Contains("CreateWindowExW") -and $moduleText.Contains("artifact missing window import")) "window PE artifacts recognized"
Add-Result "artifact_check_stdout_file" ($moduleText.Contains("GetStdHandle") -and $moduleText.Contains("stdout/file import")) "stdout/file PE artifacts recognized"

Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
