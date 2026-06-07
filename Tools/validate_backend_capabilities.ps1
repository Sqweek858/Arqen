$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "CommandAutomationCommon.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "backend_capability_validation.txt"
$capPath = Join-Path $root "Backends\WindowsX64PE\Config\capabilities_v0.txt"
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
    "window_create", "window_set_title", "window_set_resolution", "window_set_resizable", "window_show", "window_run", "window_close",
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

$moduleText = Get-Content (Join-Path $root "Tools\BackendCommon\WindowsX64PE.psm1") -Raw
Add-Result "artifact_check_window" ($moduleText.Contains("CreateWindowExW") -and $moduleText.Contains("artifact missing window import")) "window PE artifacts recognized"
Add-Result "artifact_check_stdout_file" ($moduleText.Contains("GetStdHandle") -and $moduleText.Contains("stdout/file import")) "stdout/file PE artifacts recognized"

Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
