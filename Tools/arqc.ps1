param(
    [switch]$BuildDriver,
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

function Get-ArqenRepoRoot {
    $dir = (Resolve-Path (Join-Path $PSScriptRoot ".." )).Path
    while ($true) {
        if ((Test-Path (Join-Path $dir "Docs\MILESTONES.md")) -and (Test-Path (Join-Path $dir "Tools\M10GDriver")) -and (Test-Path (Join-Path $dir "Tests\CommandTests"))) {
            return $dir
        }
        $parent = Split-Path -Parent $dir
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $dir) { break }
        $dir = $parent
    }
    throw "Could not locate Arqen repo root from $PSScriptRoot"
}

function Show-Usage {
    Write-Host "Usage:"
    Write-Host "  .\Tools\arqc.ps1 -BuildDriver"
    Write-Host "  .\Tools\arqc.ps1 <input.arq> [-o output.exe]"
    Write-Host "  .\Tools\arqc.ps1 --backend-only <input.arqir> [-o output.exe]"
}

$RepoRoot = Get-ArqenRepoRoot
$driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"

if ($BuildDriver) {
    $project = Join-Path $RepoRoot "Tools\M10GDriver\ArqcM10G.csproj"
    $publish = Join-Path $RepoRoot "Tools\M10GDriver\publish"
    New-Item -ItemType Directory -Force -Path $publish | Out-Null
    Push-Location $RepoRoot
    try {
        & dotnet publish $project -c Release -o $publish
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $publishedDriver = Join-Path $publish "arqc_m10g.exe"
        if (-not (Test-Path $publishedDriver)) {
            $fallback = Join-Path $publish "ArqcM10G.exe"
            if (Test-Path $fallback) { $publishedDriver = $fallback }
        }
        if (-not (Test-Path $publishedDriver)) { throw "Published driver exe not found in $publish" }
        Copy-Item $publishedDriver $driver -Force
        Write-Host "BUILD|driver|$driver"
    } finally {
        Pop-Location
    }
    exit 0
}

if ($Help -or $RemainingArgs.Count -eq 0) {
    Show-Usage
    exit 0
}

if (-not (Test-Path $driver)) {
    throw "Driver not found: $driver. Rebuild with: .\Tools\arqc.ps1 -BuildDriver"
}

& $driver @RemainingArgs
exit $LASTEXITCODE
