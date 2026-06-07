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

function Read-TextSafe {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return ""
    }

    return [System.IO.File]::ReadAllText($Path)
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

$driverRoot = Join-Path $RepoRoot "Tools/M10GDriver"
$driverText = Read-AllDriverSource $driverRoot

$irDocPath = Join-Path $RepoRoot "IR/ARQIR_V0_CONTRACT.md"
$irDocText = Read-TextSafe $irDocPath

$backendHelperPath = Join-Path $RepoRoot "Tools/BackendCommon/WindowsX64PE.psm1"
$backendHelperText = Read-TextSafe $backendHelperPath

$capabilitiesPath = Join-Path $RepoRoot "Backends/WindowsX64PE/Config/capabilities_v0.txt"
$capabilitiesText = Read-TextSafe $capabilitiesPath

Emit-Check "ir_readme_exists" (Test-Path $irDocPath) "IR documentation present"

# After M18DE source split, these may live in Frontend/IrEmit.cs, not Program.cs.
Emit-Check "ir_version_0_emitted" (
    $driverText -match 'ARQIR\|version=0'
) "driver emits ARQIR v0"

Emit-Check "ir_entry_emitted" (
    $driverText -match 'ENTRY\|actions='
) "driver emits entry action list"

Emit-Check "ir_action_lines_emitted" (
    $driverText -match 'IrActionLine' -or
    $driverText -match 'ACTION\|id='
) "IR action line helper present"

Emit-Check "ir_const_lines_emitted" (
    $driverText -match 'IrConstLine' -or
    $driverText -match 'CONST\|id='
) "IR const line helper present"

Emit-Check "backend_ir_model_parser" (
    $backendHelperText -match 'Parse-ArqIr' -or
    $backendHelperText -match 'ARQIR' -or
    $driverText -match 'ParseIr'
) "backend helper can parse ARQIR"

Emit-Check "backend_capability_gate" (
    $backendHelperText -match 'unsupported backend action' -or
    $backendHelperText -match 'capabilit' -or
    $driverText -match 'unsupported backend action' -or
    $capabilitiesText -match '\|supported'
) "backend helper gates actions by capabilities"

Emit-Check "backend_only_supported" (
    $driverText -match '--backend-only'
) "driver supports backend-only IR path"

Emit-Check "ir_docs_mentions_pipeline" (
    $irDocText -match 'pipeline' -or
    ($irDocText -match 'lexer' -and $irDocText -match 'parser' -and $irDocText -match 'backend')
) "IR doc keeps stage boundary visible"

Emit-Check "sample_window_ir_capability_check" (
    $capabilitiesText -match 'window_create\|supported' -and
    $capabilitiesText -match 'window_run\|supported' -and
    $capabilitiesText -match 'event_window_closed\|supported'
) ""

Emit-Check "sample_dx12_ir_rejected" (
    $capabilitiesText -match 'dx12\|unsupported' -or
    $capabilitiesText -match 'dx12\|reserved'
) "unsupported backend action: dx12"

if ($failed) {
    exit 1
}

exit 0
