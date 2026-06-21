param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$outPath = Join-Path $generated "m20a_dx12_contract_validation.txt"
$lines = @()
$failed = $false

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Message)
    if ($Ok) { $script:lines += "PASS|$Name|$Message" } else { $script:lines += "FAIL|$Name|$Message"; $script:failed = $true }
}

function Read-TextOrEmpty {
    param([string]$Path)
    if (Test-Path $Path) { return [System.IO.File]::ReadAllText($Path) }
    return ""
}

$m20DocPath = Join-Path $RepoRoot "Docs\Milestones\\M16_M20.md"
$dx12DocPath = Join-Path $RepoRoot "Docs\Reference\Backends\DX12_BACKEND_CONTRACT.md"
$runtimeDocPath = Join-Path $RepoRoot "Docs\Reference\Runtime\RUNTIME_CONTRACT.md"
$irDocPath = Join-Path $RepoRoot "Docs\Reference\IR\ARQIR_V0_CONTRACT.md"
$capPath = Join-Path $RepoRoot "Docs\Reference\Backends\WindowsX64PE_Config\capabilities_v0.txt"
$bridgeCppPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.cpp"
$bridgeHeaderPath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearWindow.h"
$smokePath = Join-Path $RepoRoot "Backends\DX12\Runtime\ArqenDx12ClearSmoke.cpp"
$buildPath = Join-Path $RepoRoot "Tools\Build\DX12\build_m20a_dx12_clear.ps1"

$m20Text = Read-TextOrEmpty $m20DocPath
$dx12Text = Read-TextOrEmpty $dx12DocPath
$runtimeText = Read-TextOrEmpty $runtimeDocPath
$irText = Read-TextOrEmpty $irDocPath
$capText = Read-TextOrEmpty $capPath
$cppText = Read-TextOrEmpty $bridgeCppPath
$headerText = Read-TextOrEmpty $bridgeHeaderPath
$smokeText = Read-TextOrEmpty $smokePath
$buildText = Read-TextOrEmpty $buildPath

Add-Result "m20a_handoff_exists" (Test-Path $m20DocPath) "Docs/Milestones/M16_M20.md present"
Add-Result "m20a_handoff_scope" ($m20Text.Contains("M20A") -and $m20Text.Contains("no public Arqen command") -and $m20Text.Contains("capability")) "M20A scope documented"
Add-Result "m20a_dx12_runtime_files" ((Test-Path $bridgeCppPath) -and (Test-Path $bridgeHeaderPath) -and (Test-Path $smokePath) -and (Test-Path $buildPath)) "DX12 bridge, smoke, and build helper present"
Add-Result "m20a_hwnd_handoff" ($headerText.Contains("HWND hwnd") -and $cppText.Contains("HWND handoff") -and $runtimeText.Contains("Window handoff rule")) "DX12 bridge requires explicit HWND handoff"
Add-Result "m20a_real_dx12_device" ($cppText.Contains("D3D12CreateDevice") -and $cppText.Contains("CreateDXGIFactory2") -and $cppText.Contains("ID3D12Device")) "device/factory creation present"
Add-Result "m20a_real_dx12_swapchain" ($cppText.Contains("CreateSwapChainForHwnd") -and $cppText.Contains("IDXGISwapChain3") -and $cppText.Contains("Present")) "HWND swapchain/present present"
Add-Result "m20a_real_dx12_command_path" ($cppText.Contains("CreateCommandQueue") -and $cppText.Contains("CreateCommandAllocator") -and $cppText.Contains("CreateCommandList") -and $cppText.Contains("ExecuteCommandLists")) "command queue/list path present"
Add-Result "m20a_real_dx12_clear" ($cppText.Contains("CreateRenderTargetView") -and $cppText.Contains("ResourceBarrier") -and $cppText.Contains("ClearRenderTargetView")) "RTV/barrier/clear present"
Add-Result "m20a_real_dx12_fence" ($cppText.Contains("CreateFence") -and $cppText.Contains("SetEventOnCompletion") -and $cppText.Contains("WaitForSingleObject")) "fence sync present"
Add-Result "m20a_smoke_is_separate" ($smokeText.Contains("CreateWindowExW") -and $smokeText.Contains("ArqenDx12ClearWindowOnce")) "smoke creates window only outside compiler path"
Add-Result "m20a_build_helper_msvc" ($buildText.Contains("cl.exe") -and $buildText.Contains("d3d12.lib") -and $buildText.Contains("dxgi.lib")) "native smoke build helper uses MSVC + DX12 libs"

foreach ($op in @("dx12", "shader", "render_pass", "frame_update")) {
    Add-Result "m20a_capability_still_unsupported_$op" ($capText -match "(?m)^$([regex]::Escape($op))\|unsupported$") "reserved operation stays unsupported"
}

Add-Result "m20a_dx12_contract_updated" ($dx12Text.Contains("M20A") -and $dx12Text.Contains("ArqenDx12ClearWindowOnce") -and $dx12Text.Contains("not a public language feature")) "DX12 contract describes M20A bridge boundary"
Add-Result "m20a_ir_contract_no_new_action" ($irText.Contains("M20A") -and $irText.Contains("does not add new ARQIR action kinds")) "IR contract keeps ARQIR unchanged for M20A"

Set-Content -Path $outPath -Value $lines -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
