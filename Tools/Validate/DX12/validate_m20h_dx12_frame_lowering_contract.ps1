param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
$tempRoot = Join-Path $RepoRoot "Build\Temp\m20h_dx12_frame_lowering"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$outPath = Join-Path $generated "m20h_dx12_frame_lowering_validation.txt"
$script:lines = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Read-TextSafe { param([string]$Path) if (-not (Test-Path $Path)) { return "" } return Get-Content $Path -Raw }
function Add-Result { param([string]$Name, [bool]$Pass, [string]$Note = "") $prefix = if ($Pass) { "PASS" } else { "FAIL" }; $script:lines.Add(("{0}|{1}|{2}" -f $prefix, $Name, $Note)) | Out-Null; if (-not $Pass) { $script:failed = $true } }

function Invoke-LowererCase {
    param(
        [string]$Name,
        [string]$IrFile,
        [string]$Renderer = "",
        [switch]$RequireFrame
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
            $output = & $lowerer -IrPath $IrFile -OutDir $caseOut -RequireFrame:$RequireFrame -Quiet 2>&1
        } else {
            $output = & $lowerer -IrPath $IrFile -OutDir $caseOut -Renderer $Renderer -RequireFrame:$RequireFrame -Quiet 2>&1
        }
        if ($null -ne $output) { $output | Out-File -FilePath $consolePath -Encoding UTF8 } else { Set-Content -Path $consolePath -Value "" -Encoding UTF8 }
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
        Config = Join-Path $caseOut "dx12_clear_config.generated.h"
    }
}

$lowererPath = Join-Path $RepoRoot "Tools\Lowering\DX12\lower_m20e1_dx12_clear_from_ir.ps1"
$fixtures = Join-Path $RepoRoot "Tests\DX12Lowering\M20H"
$m20 = Read-TextSafe (Join-Path $RepoRoot "Docs\Milestones\\M16_M20.md")
$mini = Read-TextSafe (Join-Path $RepoRoot "Docs\Milestones\\M16_M20.md")
$spec = Read-TextSafe (Join-Path $RepoRoot "Tests\CommandTests\misc\dx12.command.txt")
$irDoc = Read-TextSafe (Join-Path $RepoRoot "Docs\Reference\IR\ARQIR_V0_CONTRACT.md")
$runtimeDoc = Read-TextSafe (Join-Path $RepoRoot "Docs\Reference\Runtime\RUNTIME_CONTRACT.md")
$dx12Doc = Read-TextSafe (Join-Path $RepoRoot "Docs\Reference\Backends\DX12_BACKEND_CONTRACT.md")
$cap = Read-TextSafe (Join-Path $RepoRoot "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt")
$lowererText = Read-TextSafe $lowererPath

Add-Result "m20h_lowerer_accepts_frame_requirement" ($lowererText -match '\[switch\]\$RequireFrame' -and $lowererText -match 'DX12_FRAME' -and $lowererText -match 'begin,clear,end,present') "lowerer parses and validates DX12_FRAME sequence"
Add-Result "m20h_fixture_folder_exists" (Test-Path $fixtures) "M20H lowering fixtures present"

$basic = Invoke-LowererCase "valid_frame_ready_basic" (Join-Path $fixtures "valid_frame_ready_basic.arqir") -RequireFrame
$basicManifest = Read-TextSafe $basic.Manifest
$basicConfig = Read-TextSafe $basic.Config
Add-Result "m20h_valid_frame_basic_lowers" ($basic.Ok -and $basicManifest.Contains("FRAME_MODE|oneshot_clear_frame") -and $basicManifest.Contains("FRAME_SEQUENCE|begin,clear,end,present") -and $basicConfig.Contains('ARQEN_M20H_FRAME_SEQUENCE "begin,clear,end,present"')) "basic frame IR lowers with frame markers"

$title = Invoke-LowererCase "valid_frame_title_resolution" (Join-Path $fixtures "valid_frame_title_resolution.arqir") -RequireFrame
$titleManifest = Read-TextSafe $title.Manifest
Add-Result "m20h_valid_frame_title_resolution_lowers" ($title.Ok -and $titleManifest.Contains("TITLE|Arqen M20H DX12 Frame Clear") -and $titleManifest.Contains("WIDTH|1280") -and $titleManifest.Contains("HEIGHT|720")) "title/resolution carried through frame-aware lowering"

$multi = Invoke-LowererCase "valid_frame_multi_select" (Join-Path $fixtures "valid_frame_multi_select.arqir") "RendererB" -RequireFrame
$multiManifest = Read-TextSafe $multi.Manifest
Add-Result "m20h_valid_frame_multi_select_lowers" ($multi.Ok -and $multiManifest.Contains("RENDERER|RendererB") -and $multiManifest.Contains("COLOR_HEX|#405060") -and $multiManifest.Contains("FRAME_SEQUENCE|begin,clear,end,present")) "explicit renderer selection works with frame sequence"

$backCompat = Invoke-LowererCase "valid_clear_ready_without_frame_still_lowers" (Join-Path $fixtures "valid_clear_ready_without_frame_still_lowers.arqir")
$backManifest = Read-TextSafe $backCompat.Manifest
Add-Result "m20h_backcompat_clear_ready_without_frame" ($backCompat.Ok -and $backManifest.Contains("FRAME_MODE|clear_ready_metadata_only")) "M20E1 lowering still works without -RequireFrame"

$invalids = @(
    "invalid_frame_missing_begin.arqir",
    "invalid_frame_missing_clear.arqir",
    "invalid_frame_missing_end.arqir",
    "invalid_frame_missing_present.arqir",
    "invalid_frame_clear_before_begin.arqir",
    "invalid_frame_present_before_end.arqir",
    "invalid_frame_duplicate_sequence.arqir",
    "invalid_frame_unknown_renderer.arqir"
)
foreach ($name in $invalids) {
    $result = Invoke-LowererCase ([System.IO.Path]::GetFileNameWithoutExtension($name)) (Join-Path $fixtures $name) -RequireFrame
    $intentionalFailure = ((-not $result.Ok) -and $result.Message.Contains("M20E1 DX12 lowering failed:"))
    Add-Result ("m20h_rejects_{0}" -f [System.IO.Path]::GetFileNameWithoutExtension($name)) $intentionalFailure $result.Message
}
$selectedMissing = Invoke-LowererCase "invalid_selected_renderer_missing_frame" (Join-Path $fixtures "invalid_selected_renderer_missing_frame.arqir") "RendererB" -RequireFrame
Add-Result "m20h_rejects_selected_renderer_missing_frame" ((-not $selectedMissing.Ok) -and $selectedMissing.Message.Contains("M20E1 DX12 lowering failed:")) $selectedMissing.Message

Add-Result "m20h_docs_handoff" ($m20.Contains("M20H DX12 frame-aware lowering") -and $m20.Contains("FRAME_SEQUENCE|begin,clear,end,present")) "M20 handoff documents frame-aware lowering"
Add-Result "m20h_docs_mini_bible" ($mini.Contains("M20H frame-aware lowering") -and $mini.Contains("-RequireFrame")) "mini bible documents M20H lowering"
Add-Result "m20h_spec_status" ($spec.Contains("M20H_FRAME_LOWERING") -and $spec.Contains("STATUS|m20h_dx12_frame_aware_lowering")) "command spec records frame lowering milestone"
Add-Result "m20h_contract_docs" ($irDoc.Contains("M20H") -and $runtimeDoc.Contains("M20H") -and $dx12Doc.Contains("M20H")) "IR/runtime/DX12 contracts document M20H"
Add-Result "m20h_capability_still_unsupported" ($cap -match 'dx12\|unsupported' -and $cap -match 'shader\|unsupported' -and $cap -match 'render_pass\|unsupported' -and $cap -match 'frame_update\|unsupported') "DX12 families remain unsupported"

[System.IO.File]::WriteAllLines($outPath, $script:lines, [System.Text.UTF8Encoding]::new($false))
foreach ($line in $script:lines) { Write-Host $line }
Write-Host "OUT|$outPath"
exit $(if ($script:failed) { 1 } else { 0 })
