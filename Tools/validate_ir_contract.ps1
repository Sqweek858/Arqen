$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "CommandAutomationCommon.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "BackendCommon\WindowsX64PE.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "ir_contract_validation.txt"
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) { $lines.Add("PASS|$Name|$Detail") | Out-Null } else { $script:failed = $true; $lines.Add("FAIL|$Name|$Detail") | Out-Null }
}

$programPath = Join-Path $root "Tools\M10GDriver\Program.cs"
$backendModulePath = Join-Path $root "Tools\BackendCommon\WindowsX64PE.psm1"
$irReadme = Join-Path $root "IR\README.md"
$capPath = Join-Path $root "Backends\WindowsX64PE\Config\capabilities_v0.txt"
$program = Get-Content $programPath -Raw
$backendModule = Get-Content $backendModulePath -Raw
$irText = if (Test-Path $irReadme) { Get-Content $irReadme -Raw } else { "" }

Add-Result "ir_readme_exists" (Test-Path $irReadme) "IR documentation present"
Add-Result "ir_version_0_emitted" ($program.Contains('ARQIR|version=0')) "driver emits ARQIR v0"
Add-Result "ir_entry_emitted" ($program.Contains('ENTRY|actions=')) "driver emits entry action list"
Add-Result "ir_action_lines_emitted" ($program.Contains('ACTION|id=')) "IR action line helper present"
Add-Result "ir_const_lines_emitted" ($program.Contains('CONST|id=')) "IR const line helper present"
Add-Result "backend_ir_model_parser" ($backendModule.Contains('function Get-ArqIrModel')) "backend helper can parse ARQIR"
Add-Result "backend_capability_gate" ($backendModule.Contains('function Test-ArqBackendCapabilities')) "backend helper gates actions by capabilities"
Add-Result "backend_only_supported" ($program.Contains('--backend-only')) "driver supports backend-only IR path"
Add-Result "ir_docs_mentions_pipeline" ($irText.Contains('Source -> Lexer') -and $irText.Contains('IR -> Backend')) "IR doc keeps stage boundary visible"

$sampleIrPath = Join-Path $generated "m18b_sample_window.arqir"
Set-Content -Path $sampleIrPath -Encoding UTF8 -Value @(
    "ARQIR|version=0",
    "TARGET|kind=program|name=M18BWindowSample",
    "META|source=Tests/CommandTests/window/valid_window_small.arq",
    "ACTION|id=act_0|op=window_create|path=|value_kind=static|value=|target=Window",
    "ACTION|id=act_1|op=window_show|path=|value_kind=static|value=|target=Window",
    "ACTION|id=act_2|op=window_run|path=|value_kind=static|value=|target=Window",
    "ACTION|id=act_3|op=exit|code=i32_0",
    "CONST|id=i32_0|type=int|value=0",
    "ENTRY|actions=act_0,act_1,act_2,act_3",
    "END"
)
$capCheck = Test-ArqBackendCapabilities $sampleIrPath $capPath
Add-Result "sample_window_ir_capability_check" $capCheck.Ok $capCheck.Message

$badIrPath = Join-Path $generated "m18b_sample_dx12_unsupported.arqir"
Set-Content -Path $badIrPath -Encoding UTF8 -Value @(
    "ARQIR|version=0",
    "TARGET|kind=program|name=M18BDx12UnsupportedSample",
    "META|source=generated",
    "ACTION|id=act_0|op=dx12|path=|value_kind=static|value=|target=Device",
    "ACTION|id=act_1|op=exit|code=i32_0",
    "CONST|id=i32_0|type=int|value=0",
    "ENTRY|actions=act_0,act_1",
    "END"
)
$badCapCheck = Test-ArqBackendCapabilities $badIrPath $capPath
Add-Result "sample_dx12_ir_rejected" (-not $badCapCheck.Ok -and $badCapCheck.Message.Contains('unsupported backend action')) $badCapCheck.Message

Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
