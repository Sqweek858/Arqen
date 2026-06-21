param(
    [switch]$Clean,
    [switch]$SkipDx12,
    [switch]$RunDx12,
    [switch]$RunConsoleSamples,
    [switch]$Dx12Timed,
    [int]$Dx12Frames = 900,
    [int]$Dx12Fps = 60,
    [int]$Dx12HoldMilliseconds = 15000
)

$ErrorActionPreference = "Stop"

$VsRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = Split-Path -Parent $VsRoot
$BuildScript = Join-Path $RepoRoot "What_I_Can_Do\Build\build_all.ps1"
$TrashRoot = Join-Path $VsRoot "Trash\Arqen.WhatICanDo"
$StampPath = Join-Path $TrashRoot "last_build.stamp"
$LogPath = Join-Path $TrashRoot "last_build.log"

New-Item -ItemType Directory -Force -Path $TrashRoot | Out-Null

function Write-VsBuildLine {
    param([string]$Text)
    Write-Host $Text
}

function ConvertTo-CmdQuotedArg {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Find-VcVars64 {
    $candidates = New-Object System.Collections.Generic.List[string]

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere) {
        try {
            $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
            if (-not [string]::IsNullOrWhiteSpace($installPath)) {
                $candidates.Add((Join-Path $installPath "VC\Auxiliary\Build\vcvars64.bat"))
            }
        }
        catch {
            # Fall through to common Visual Studio install paths.
        }
    }

    $programFiles = ${env:ProgramFiles}
    if (-not [string]::IsNullOrWhiteSpace($programFiles)) {
        $candidates.Add((Join-Path $programFiles "Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"))
        $candidates.Add((Join-Path $programFiles "Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"))
        $candidates.Add((Join-Path $programFiles "Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"))
        $candidates.Add((Join-Path $programFiles "Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"))
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    return $null
}

if (-not (Test-Path -LiteralPath $BuildScript)) {
    throw "What_I_Can_Do build script was not found: $BuildScript"
}

Push-Location $RepoRoot
try {
    $argsList = @()
    if ($Clean) { $argsList += "-Clean" }
    if ($SkipDx12) { $argsList += "-SkipDx12" }
    if ($RunDx12) { $argsList += "-RunDx12" }
    if ($RunConsoleSamples) { $argsList += "-RunConsoleSamples" }
    if ($Dx12Timed) { $argsList += "-Dx12Timed" }
    if ($Dx12HoldMilliseconds -lt 1) {
        Write-VsBuildLine "MSVC : Dx12HoldMilliseconds was less than 1; using 15000."
        $Dx12HoldMilliseconds = 15000
    }
    $argsList += @("-Dx12Frames", $Dx12Frames)
    $argsList += @("-Dx12Fps", $Dx12Fps)
    $argsList += @("-Dx12HoldMilliseconds", $Dx12HoldMilliseconds)

    Write-VsBuildLine "+================================================================================+"
    Write-VsBuildLine "| VisualStudio -> What_I_Can_Do build                                           |"
    Write-VsBuildLine "+================================================================================+"
    Write-VsBuildLine "Repo : $RepoRoot"
    Write-VsBuildLine "Log  : $LogPath"

    $useVsDevBootstrap = $false
    $vcvars = $null
    if (-not $SkipDx12 -and -not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
        $vcvars = Find-VcVars64
        if (-not [string]::IsNullOrWhiteSpace($vcvars)) {
            $useVsDevBootstrap = $true
            Write-VsBuildLine "MSVC : cl.exe not found in current PATH; bootstrapping vcvars64.bat"
            Write-VsBuildLine "VCVARS: $vcvars"
        }
        else {
            Write-VsBuildLine "MSVC : cl.exe not found, and vcvars64.bat could not be located. DX12 native build may fail."
        }
    }
    else {
        Write-VsBuildLine "MSVC : cl.exe available or DX12 skipped"
    }

    $buildExitCode = 1
    if ($useVsDevBootstrap) {
        $psArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $BuildScript) + $argsList
        $psArgText = ($psArgs | ForEach-Object { ConvertTo-CmdQuotedArg ([string]$_) }) -join " "
        $cmdLine = "call " + (ConvertTo-CmdQuotedArg $vcvars) + " >nul && powershell.exe " + $psArgText
        & cmd.exe /d /s /c $cmdLine 2>&1 | Tee-Object -FilePath $LogPath
        $buildExitCode = $LASTEXITCODE
    }
    else {
        $psArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $BuildScript) + $argsList
        & powershell.exe @psArgs 2>&1 | Tee-Object -FilePath $LogPath
        $buildExitCode = $LASTEXITCODE
    }

    if ($null -eq $buildExitCode) { $buildExitCode = 0 }

    @(
        "timestamp=$(Get-Date -Format o)",
        "exit=$buildExitCode",
        "repo=$RepoRoot",
        "script=$BuildScript",
        "log=$LogPath",
        "vcvars=$vcvars"
    ) | Set-Content -LiteralPath $StampPath -Encoding ASCII

    Write-VsBuildLine "VisualStudio build log: $LogPath"
    exit $buildExitCode
}
finally {
    Pop-Location
}
