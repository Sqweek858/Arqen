param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$runtime = Join-Path $RepoRoot "Backends\DX12\Runtime"
$outDir = Join-Path $RepoRoot "Build\EXE"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$cpp = Join-Path $runtime "ArqenDx12ClearWindow.cpp"
$smoke = Join-Path $runtime "ArqenDx12ClearSmoke.cpp"
$out = Join-Path $outDir "m20a_dx12_clear_smoke.exe"

$cl = Get-Command cl.exe -ErrorAction SilentlyContinue
if ($null -eq $cl) {
    throw "cl.exe was not found. Run this from a Visual Studio Developer PowerShell/Command Prompt."
}

Push-Location $RepoRoot
try {
    & cl.exe /nologo /std:c++20 /EHsc /W4 /DUNICODE /D_UNICODE $cpp $smoke /Fe:$out d3d12.lib dxgi.lib user32.lib gdi32.lib
    if ($LASTEXITCODE -ne 0) {
        throw "MSVC build failed."
    }
    Write-Host "PASS|m20a_dx12_clear_smoke_build|$out"
} finally {
    Pop-Location
}
