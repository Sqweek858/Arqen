
param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
$tempRoot = Join-Path $RepoRoot "Build\Temp\m20e1_dx12_lowering"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$outPath = Join-Path $generated "m20e1_dx12_lowering_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return "" }
    return Get-Content $Path -Raw
}

function Add-Result {
    param([string]$Name, [bool]$Pass, [string]$Note = "")
    $prefix = if ($Pass) { "PASS" } else { "FAIL" }
    $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null
    if (-not $Pass) { $script:failed = $true }
}

function Invoke-LowererCase {
    param(
        [string]$Name,
        [string]$IrFile,
        [string]$Renderer = ""
    )
    $lowerer = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
    $caseOut = Join-Path $tempRoot $Name
    if (Test-Path $caseOut) { Remove-Item -Recurse -Force $caseOut }
    New-Item -ItemType Directory -Force -Path $caseOut | Out-Null
    $ok = $true
    $message = ""
    $consolePath = Join-Path $caseOut "lowerer.console.txt"
    try {
        if ([string]::IsNullOrWhiteSpace($Renderer)) {
            $output = & $lowerer -IrPath $IrFile -OutDir $caseOut -Quiet 2>&1
        } else {
            $output = & $lowerer -IrPath $IrFile -OutDir $caseOut -Renderer $Renderer -Quiet 2>&1
        }

        if ($null -ne $output) {
            $output | Out-File -FilePath $consolePath -Encoding UTF8
        } else {
            Set-Content -Path $consolePath -Value "" -Encoding UTF8
        }
    } catch {
        $ok = $false
        $message = $_.Exception.Message
        Set-Content -Path $consolePath -Value $message -Encoding UTF8
        Set-Content -Path (Join-Path $caseOut "lowerer.error.txt") -Value $message -Encoding UTF8
    }
    return [pscustomobject]@{
        Ok = $ok
        Message = $message
        OutDir = $caseOut
        Manifest = Join-Path $caseOut "dx12_clear_manifest.generated.txt"
        Header = Join-Path $caseOut "dx12_clear_config.generated.h"
    }
}

$toolPath = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
$buildPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m20e1_dx12_clear_from_ir.ps1"
$fixtures = Join-Path $RepoRoot "Tests\DX12Lowering\M20E1"
$m20Path = Join-Path $RepoRoot "Docs\Milestones\\M16_M20.md"
$miniPath = Join-Path $RepoRoot "Docs\Milestones\\M16_M20.md"
$specPath = Join-Path $RepoRoot "Tests\CommandTests\misc\dx12.command.txt"
$irDocPath = Join-Path $RepoRoot "Docs\Reference\IR\ARQIR_V0_CONTRACT.md"
$runtimeDocPath = Join-Path $RepoRoot "Docs\Reference\Runtime\RUNTIME_CONTRACT.md"
$dx12ContractPath = Join-Path $RepoRoot "Docs\Reference\Backends\DX12_BACKEND_CONTRACT.md"
$toolMapPath = Join-Path $RepoRoot "Docs\Info\TOOLS.md"
$capPath = Join-Path $RepoRoot "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt"

$toolText = Read-TextSafe $toolPath
$buildText = Read-TextSafe $buildPath
$m20Text = Read-TextSafe $m20Path
$miniText = Read-TextSafe $miniPath
$specText = Read-TextSafe $specPath
$irDoc = Read-TextSafe $irDocPath
$runtimeDoc = Read-TextSafe $runtimeDocPath
$dx12Contract = Read-TextSafe $dx12ContractPath
$toolMap = Read-TextSafe $toolMapPath
$cap = Read-TextSafe $capPath

Add-Result "m20e1_lowerer_tool_exists" (Test-Path $toolPath) "lower_m20e1_dx12_clear_from_ir.ps1 present"
Add-Result "m20e1_lowerer_parses_required_metadata" ($toolText.Contains("DX12_CLEAR_READY") -and $toolText.Contains("DX12_PARENT") -and $toolText.Contains("window_create") -and $toolText.Contains("window_set_resolution")) "lowerer consumes ready/parent/window actions"
Add-Result "m20e1_lowerer_generates_manifest_and_header" ($toolText.Contains("dx12_clear_manifest.generated.txt") -and $toolText.Contains("dx12_clear_config.generated.h") -and $toolText.Contains("ARQEN_M20E1_CLEAR_R")) "manifest/header generation present"
Add-Result "m20e1_native_build_helper_exists" (Test-Path $buildPath) "M20E1 native build helper present"
Add-Result "m20e1_native_build_helper_uses_bridge" ($buildText.Contains("ArqenDx12ClearWindowOnce") -and $buildText.Contains("dx12_clear_config.generated.h") -and $buildText.Contains("lower_m20e1_dx12_clear_from_ir.ps1") -and $buildText.Contains("cl.exe")) "build helper lowers IR then compiles bridge smoke"
Add-Result "m20e1_fixture_folder_exists" (Test-Path $fixtures) "lowering fixtures present"

$validBasic = Invoke-LowererCase "valid_basic" (Join-Path $fixtures "valid_clear_ready_basic.arqir")
$basicManifest = Read-TextSafe $validBasic.Manifest
$basicHeader = Read-TextSafe $validBasic.Header
Add-Result "m20e1_valid_basic_lowers" ($validBasic.Ok -and $basicManifest.Contains("RENDERER|MainRenderer") -and $basicManifest.Contains("COLOR_HEX|#101820") -and $basicHeader.Contains("ARQEN_M20E1_CLEAR_R 0.062745f")) "basic ready IR lowers to manifest/header"

$validTitle = Invoke-LowererCase "valid_title_resolution" (Join-Path $fixtures "valid_clear_ready_title_resolution.arqir")
$titleManifest = Read-TextSafe $validTitle.Manifest
$titleHeader = Read-TextSafe $validTitle.Header
Add-Result "m20e1_valid_title_resolution_lowers" ($validTitle.Ok -and $titleManifest.Contains("TITLE|Arqen DX12 From IR") -and $titleManifest.Contains("WIDTH|1280") -and $titleManifest.Contains("HEIGHT|720") -and $titleHeader.Contains("ARQEN_M20E1_WINDOW_WIDTH 1280")) "title/resolution are carried into generated config"

$validSelected = Invoke-LowererCase "valid_multi_select" (Join-Path $fixtures "valid_clear_ready_multi_select.arqir") "RendererB"
$selectedManifest = Read-TextSafe $validSelected.Manifest
Add-Result "m20e1_valid_multi_select_lowers" ($validSelected.Ok -and $selectedManifest.Contains("RENDERER|RendererB") -and $selectedManifest.Contains("WINDOW|WindowB") -and $selectedManifest.Contains("COLOR_HEX|#405060")) "explicit renderer selection works"

$invalids = @(
    "invalid_missing_clear_ready.arqir",
    "invalid_duplicate_clear_ready.arqir",
    "invalid_bad_color.arqir",
    "invalid_missing_window_create.arqir",
    "invalid_missing_parent.arqir",
    "invalid_multiple_ready_requires_selector.arqir"
)
foreach ($name in $invalids) {
    $result = Invoke-LowererCase ([System.IO.Path]::GetFileNameWithoutExtension($name)) (Join-Path $fixtures $name)
    $intentionalFailure = ((-not $result.Ok) -and $result.Message.Contains("M20E1 DX12 lowering failed:"))
    Add-Result ("m20e1_rejects_{0}" -f [System.IO.Path]::GetFileNameWithoutExtension($name)) $intentionalFailure $result.Message
}

Add-Result "m20e1_docs_handoff" ($m20Text.Contains("M20E1 DX12 experimental clear lowering") -and $m20Text.Contains("DX12_CLEAR_READY -> generated native bridge config")) "M20 handoff documents lowering boundary"
Add-Result "m20e1_docs_mini_bible" ($miniText.Contains("M20E1 experimental clear lowering") -and $miniText.Contains("lower_m20e1_dx12_clear_from_ir.ps1")) "mini bible documents M20E1 path"
Add-Result "m20e1_spec_status" ($specText.Contains("M20E1_LOWERING") -and $specText.Contains("STATUS|m20e1_dx12_experimental_clear_lowering")) "command spec records lowering milestone"
Add-Result "m20e1_contract_docs" ($irDoc.Contains("M20E1") -and $runtimeDoc.Contains("M20E1") -and $dx12Contract.Contains("M20E1")) "IR/runtime/DX12 contracts document M20E1"
Add-Result "m20e1_tool_map" ($toolMap.Contains("lower_m20e1_dx12_clear_from_ir.ps1") -and $toolMap.Contains("build_m20e1_dx12_clear_from_ir.ps1")) "tool map documents lowerer/build helper"
Add-Result "m20e1_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
