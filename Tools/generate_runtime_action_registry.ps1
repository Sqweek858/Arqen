param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$failed = $false

function Emit-Check {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Message
    )

    if ($Ok) {
        Write-Host "PASS|$Name|$Message"
    } else {
        Write-Host "FAIL|$Name|$Message"
        $script:failed = $true
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

$capabilitiesPath = Join-Path $RepoRoot "Backends/WindowsX64PE/Config/capabilities_v0.txt"
$capabilities = Read-Capabilities $capabilitiesPath

$actions = @{}

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

# IrActionLine(..., "op", ...)
foreach ($m in [regex]::Matches($driverText, 'IrActionLine\s*\([^,]+,\s*"([^"]+)"')) {
    Add-Action $m.Groups[1].Value "IrActionLine"
}

# Some baseline IR actions can be emitted indirectly or are expected by contract.
foreach ($baseline in @("show_message", "print_stdout", "exit")) {
    Add-Action $baseline "baseline_ir"
}

$generatedDir = Join-Path $RepoRoot "Build/Generated"
New-Item -ItemType Directory -Path $generatedDir -Force | Out-Null

$registryPath = Join-Path $generatedDir "runtime_action_registry.txt"
$lines = New-Object System.Collections.Generic.List[string]

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

[System.IO.File]::WriteAllText(
    $registryPath,
    (($lines.ToArray() -join [Environment]::NewLine) + [Environment]::NewLine),
    [System.Text.UTF8Encoding]::new($false)
)

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
    "window_create",
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

Emit-Check "runtime_actions_have_capabilities" (($missingCapability.Count -eq 0) -and ($unsupportedCapability.Count -eq 0)) ("missing=$($missingCapability.Count) unsupported=$($unsupportedCapability.Count)")
Emit-Check "runtime_action_count_min" ($actions.Count -ge 15) "count=$($actions.Count)"

Write-Host "SUMMARY|actions=$($actions.Count)|missingCapabilities=$($missingCapability.Count)|unsupportedCapabilities=$($unsupportedCapability.Count)"

if ($failed) {
    exit 1
}

exit 0
