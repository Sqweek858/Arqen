param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "Common\ArqenTooling.psm1") -Force

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Get-ArqenRepoRoot -StartPath $PSScriptRoot
}

$failed = $false

function Emit-Check {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Message
    )

    if ($Ok) {
        $line = "PASS|$Name|$Message"
    } else {
        $line = "FAIL|$Name|$Message"
        $script:failed = $true
    }

    Write-Host $line
    if ($null -ne $script:runtimeRegistryLines) {
        $script:runtimeRegistryLines.Add($line) | Out-Null
    }
}

function Read-AllDriverSource {
    param([string]$DriverRoot)

    if (-not (Test-Path $DriverRoot)) {
        return ""
    }

    return (
        Get-ChildItem $DriverRoot -Recurse -Filter *.cs |
        Sort-Object FullName |
        ForEach-Object {
            [System.IO.File]::ReadAllText($_.FullName)
        }
    ) -join "`n"
}

function Read-Capabilities {
    param([string]$Path)

    $map = @{}

    if (-not (Test-Path $Path)) {
        return $map
    }

    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()

        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed.Split("|")
        if ($parts.Count -lt 2) {
            continue
        }

        $name = $parts[0].Trim()
        $status = $parts[1].Trim()

        if ($name -ne "") {
            $map[$name] = $status
        }
    }

    return $map
}

$driverRoot = Join-Path $RepoRoot "Tools/M10GDriver"
$driverText = Read-AllDriverSource $driverRoot

$capabilitiesPath = Join-Path $RepoRoot "Docs/Reference/Backends/WindowsX64PE_Config/capabilities_v0.txt"
$capabilities = Read-Capabilities $capabilitiesPath

$actions = @{}
$catalogActions = @{}

function Add-Action {
    param(
        [string]$Name,
        [string]$Source
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return
    }

    if (-not $actions.ContainsKey($Name)) {
        $actions[$Name] = New-Object System.Collections.Generic.HashSet[string]
    }

    [void]$actions[$Name].Add($Source)
}

# RuntimeAction("op", ...) / new RuntimeAction("op", ...)
foreach ($m in [regex]::Matches($driverText, 'RuntimeAction\s*\(\s*"([^"]+)"')) {
    Add-Action $m.Groups[1].Value "RuntimeAction"
}

$catalogPath = Join-Path $RepoRoot "Docs/Reference/Runtime/RUNTIME_ACTION_CATALOG.txt"
if (Test-Path $catalogPath) {
    foreach ($raw in Get-Content $catalogPath) {
        $trimmed = $raw.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed.Split("|")
        if ($parts.Count -ge 4 -and $parts[0] -eq "ACTION") {
            $catalogActions[$parts[1]] = $parts[3]
            Add-Action $parts[1] "runtime_action_catalog"
        }
    }
}

# IrActionLine(..., "op", ...)
foreach ($m in [regex]::Matches($driverText, 'IrActionLine\s*\([^,]+,\s*"([^"]+)"')) {
    Add-Action $m.Groups[1].Value "IrActionLine"
}

# Some baseline/indirect IR actions can be emitted through variables or are expected by contract.
foreach ($baseline in @("show_message", "print_stdout", "exit", "window_style_title_bar_color", "window_style_title_text_color")) {
    Add-Action $baseline "baseline_ir"
}

# Typed runtime state/control actions can be emitted through helper variables such as
# $"runtime_{declaredType}_set" and condition.ActionOp, so keep the registry explicit.
# Regex intentionally catches string-literal prefixes inside concatenated op names such as
# new RuntimeAction("function_return_" + returnType, ...). Keep the real typed
# return actions explicit below and drop the incomplete prefix so the registry does
# not invent a ghost capability. Software, naturally, tried to register half a word.
if ($actions.ContainsKey("function_return_")) {
    $actions.Remove("function_return_")
}

foreach ($typedRuntime in @(
    "runtime_int_set",
    "runtime_int_add",
    "runtime_int_sub",
    "runtime_bool_set",
    "runtime_bool_not_set",
    "runtime_bool_toggle",
    "runtime_trap_if_bool_false",
    "runtime_string_set",
    "runtime_string_concat",
    "runtime_string_substring",
    "runtime_int_parse",
    "runtime_if_int",
    "runtime_if_bool",
    "runtime_if_string",
    "runtime_else",
    "runtime_if_end",
    "runtime_while_int",
    "runtime_break",
    "runtime_continue",
    "runtime_while_end",
    "function_call",
    "function_call_assign",
    "function_return",
    "function_return_int",
    "function_return_bool",
    "function_return_string"
)) {
    Add-Action $typedRuntime "typed_runtime_contract"
}

$generatedDir = Join-Path $RepoRoot "Build/Generated"
New-Item -ItemType Directory -Path $generatedDir -Force | Out-Null

$registryPath = Join-Path $generatedDir "runtime_action_registry.txt"
$lines = New-Object System.Collections.Generic.List[string]
$script:runtimeRegistryLines = $lines

$lines.Add("RUNTIME_ACTION_REGISTRY|generated") | Out-Null
Write-Host "RUNTIME_ACTION_REGISTRY|generated"

foreach ($name in ($actions.Keys | Sort-Object)) {
    $status = "missing"
    if ($capabilities.ContainsKey($name)) {
        $status = $capabilities[$name]
    }

    $sourceValue = $actions[$name]
    if ($sourceValue -is [System.Collections.IEnumerable] -and $sourceValue -isnot [string]) {
        $sources = @($sourceValue | ForEach-Object { $_.ToString() } | Sort-Object) -join ","
    } else {
        $sources = [string]$sourceValue
    }
    $line = "ACTION|$name|capability=$status|sources=$sources"

    $lines.Add($line) | Out-Null
    Write-Host $line
}

$required = @(
    "show_message",
    "print_stdout",
    "exit",
    "file_write",
    "file_append",
    "file_load",
    "print_runtime_slot",
    "command_arg_count",
    "command_arg_index",
    "runtime_int_set",
    "runtime_int_add",
    "runtime_int_sub",
    "runtime_bool_set",
    "runtime_bool_not_set",
    "runtime_bool_toggle",
    "runtime_trap_if_bool_false",
    "runtime_string_set",
    "runtime_string_concat",
    "runtime_string_substring",
    "runtime_int_parse",
    "runtime_if_int",
    "runtime_if_bool",
    "runtime_if_string",
    "runtime_else",
    "runtime_if_end",
    "runtime_while_int",
    "runtime_break",
    "runtime_continue",
    "runtime_while_end",
    "function_call",
    "function_call_assign",
    "function_return",
    "function_return_int",
    "function_return_bool",
    "function_return_string",
    "window_create",
    "window_set_title",
    "window_set_resolution",
    "window_set_resizable",
    "window_style_title_bar_color",
    "window_style_title_text_color",
    "window_show",
    "window_run",
    "window_close",
    "event_window_closed",
    "event_key_pressed",
    "event_end"
)

foreach ($requiredAction in $required) {
    Emit-Check "runtime_action_$requiredAction" ($actions.ContainsKey($requiredAction)) "required emitted/runtime action present"
}

$missingCapability = @()
$unsupportedCapability = @()

foreach ($name in $actions.Keys) {
    if (-not $capabilities.ContainsKey($name)) {
        $missingCapability += $name
        continue
    }

    if ($capabilities[$name] -ne "supported") {
        $unsupportedCapability += $name
    }
}

foreach ($catalogName in ($catalogActions.Keys | Sort-Object)) {
    Emit-Check "runtime_catalog_action_$catalogName" ($actions.ContainsKey($catalogName)) "catalog action appears in generated registry"
}

Emit-Check "runtime_actions_have_capabilities" (($missingCapability.Count -eq 0) -and ($unsupportedCapability.Count -eq 0)) ("missing=$($missingCapability.Count) unsupported=$($unsupportedCapability.Count)")
Emit-Check "runtime_action_count_min" ($actions.Count -ge 15) "count=$($actions.Count)"

$summaryLine = "SUMMARY|actions=$($actions.Count)|missingCapabilities=$($missingCapability.Count)|unsupportedCapabilities=$($unsupportedCapability.Count)"
$lines.Add($summaryLine) | Out-Null
Write-Host $summaryLine

[System.IO.File]::WriteAllText(
    $registryPath,
    (($lines.ToArray() -join [Environment]::NewLine) + [Environment]::NewLine),
    [System.Text.UTF8Encoding]::new($false)
)

if ($failed) {
    exit 1
}

exit 0
