param(
    [switch]$Clean,
    [switch]$RunConsoleSamples,
    [switch]$SkipDx12,
    [switch]$RunDx12,
    [switch]$Dx12Timed,
    [int]$Dx12Frames = 900,
    [int]$Dx12Fps = 60,
    [int]$Dx12HoldMilliseconds = 15000
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$WicdRoot = Join-Path $Root "What_I_Can_Do"
$SourceDir = Join-Path $WicdRoot "Source"
$BuildDir = Join-Path $WicdRoot "Build"
$ExeDir = Join-Path $WicdRoot "Exe"
$ArtifactDir = Join-Path $BuildDir "Artifacts"
$Driver = Join-Path $Root "Tools\arqc_m10g.exe"
$Dx12Builder = Join-Path $Root "Tools\Build\DX12\build_m31a_dx12_ui_controls_scene.ps1"

function Write-Line {
    param([string]$Text, [string]$Color = "Gray")
    Write-Host $Text -ForegroundColor $Color
}

function Copy-IfExists {
    param([string]$From, [string]$To)
    if (Test-Path $From) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $To) | Out-Null
        Copy-Item $From $To -Force
    }
}

function Write-OutputAndLog {
    param(
        [object[]]$Output,
        [string]$Log,
        [switch]$Append
    )

    $lines = @($Output | ForEach-Object { [string]$_ })
    if ($Append) {
        $lines | Add-Content -Path $Log
    } else {
        $lines | Set-Content -Path $Log
    }
    foreach ($line in $lines) { Write-Host $line }
}

function Invoke-ConsoleSampleBuild {
    param(
        [System.IO.FileInfo]$Source,
        [string]$Stem,
        [string]$Exe,
        [string]$Log,
        [string]$CaseArtifactDir
    )

    $exit = 1
    Push-Location $Root
    try {
        $output = @(& $Driver $Source.FullName -o $Exe *>&1)
        $exit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally {
        Pop-Location
    }

    Write-OutputAndLog -Output $output -Log $Log

    Copy-IfExists (Join-Path $Root "Build\Tokens\$Stem.tokens") (Join-Path $CaseArtifactDir "$Stem.tokens")
    Copy-IfExists (Join-Path $Root "Build\AST\$Stem.ast") (Join-Path $CaseArtifactDir "$Stem.ast")
    Copy-IfExists (Join-Path $Root "Build\IR\$Stem.arqir") (Join-Path $CaseArtifactDir "$Stem.arqir")
    Copy-IfExists (Join-Path $Root "Build\Manifests\$Stem.manifest.txt") (Join-Path $CaseArtifactDir "$Stem.manifest.txt")
    Copy-IfExists $Log (Join-Path $CaseArtifactDir "$Stem.build.log")

    return $exit
}

function Invoke-Dx12SampleBuild {
    param(
        [System.IO.FileInfo]$Source,
        [string]$Stem,
        [string]$Exe,
        [string]$Log,
        [string]$CaseArtifactDir
    )

    if (-not (Test-Path $Dx12Builder)) {
        throw "Missing DX12 native build wrapper: $Dx12Builder"
    }

    $keepOpen = -not $Dx12Timed
    $nativeExeName = "m31a_dx12_ui_controls_scene.exe"
    $nativeExeCandidates = @(
        (Join-Path $CaseArtifactDir $nativeExeName),
        (Join-Path $Root ("Build\EXE\" + $nativeExeName))
    )
    $exit = 1

    Push-Location $Root
    try {
        $output = @(& $Dx12Builder `
            -SourcePath $Source.FullName `
            -RepoRoot $Root `
            -OutDir $CaseArtifactDir `
            -BuildNative `
            -FrameCount $Dx12Frames `
            -TargetFps $Dx12Fps `
            -HoldMilliseconds $Dx12HoldMilliseconds `
            -KeepOpen:$keepOpen `
            -Run:$RunDx12 *>&1)
        $exit = 0
        Write-OutputAndLog -Output $output -Log $Log
    } catch {
        $output = @($_ | Out-String)
        Write-OutputAndLog -Output $output -Log $Log -Append
        $exit = 1
    } finally {
        Pop-Location
    }

    Copy-IfExists (Join-Path $Root "Build\Tokens\$Stem.tokens") (Join-Path $CaseArtifactDir "$Stem.tokens")
    Copy-IfExists (Join-Path $Root "Build\AST\$Stem.ast") (Join-Path $CaseArtifactDir "$Stem.ast")
    Copy-IfExists (Join-Path $Root "Build\IR\$Stem.arqir") (Join-Path $CaseArtifactDir "$Stem.arqir")
    Copy-IfExists (Join-Path $Root "Build\Manifests\$Stem.manifest.txt") (Join-Path $CaseArtifactDir "$Stem.manifest.txt")
    Copy-IfExists $Log (Join-Path $CaseArtifactDir "$Stem.build.log")

    if ($exit -eq 0) {
        $nativeExe = $null
        foreach ($candidate in $nativeExeCandidates) {
            if (Test-Path $candidate) {
                $nativeExe = $candidate
                break
            }
        }

        if ($null -ne $nativeExe) {
            Copy-Item $nativeExe $Exe -Force
            Write-Line ("[INFO ] DX12 native exe copied from " + $nativeExe) DarkCyan
        } else {
            Write-Line "[WARN ] DX12 native exe was not found in expected locations:" Yellow
            foreach ($candidate in $nativeExeCandidates) {
                Write-Line ("       " + $candidate) Yellow
            }
            $exit = 1
        }
    }

    return $exit
}

if (-not (Test-Path $Driver)) {
    throw "Missing compiler driver: $Driver. Run .\Tools\arqc.ps1 -BuildDriver first."
}
if ($Dx12Frames -lt 1) { throw "Dx12Frames must be positive." }
if ($Dx12Fps -lt 1) { throw "Dx12Fps must be positive." }
if ($Dx12HoldMilliseconds -lt 1) { throw "Dx12HoldMilliseconds must be positive." }

New-Item -ItemType Directory -Force -Path $SourceDir, $BuildDir, $ExeDir, $ArtifactDir | Out-Null

if ($Clean) {
    Get-ChildItem $BuildDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "build_all.ps1" -and $_.Name -ne ".gitkeep" } |
        Remove-Item -Force
    Get-ChildItem $ExeDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne ".gitkeep" } |
        Remove-Item -Force
}

$Sources = @(Get-ChildItem $SourceDir -File -Filter "*.arq" | Sort-Object Name)
if ($SkipDx12) {
    $Sources = @($Sources | Where-Object { $_.Name -notlike "*dx12*" })
}

Write-Line "+================================================================================+" Cyan
Write-Line "| What_I_Can_Do build                                                           |" Cyan
Write-Line "+================================================================================+" Cyan
Write-Line "Source: $SourceDir" DarkCyan
Write-Line "Exe   : $ExeDir" DarkCyan
Write-Line "Build : $BuildDir" DarkCyan
Write-Line "DX12  : native wrapper, keep-open by default; use -Dx12Timed for timed close" DarkCyan
Write-Line ""

$Failed = $false
foreach ($src in $Sources) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($src.Name)
    $exe = Join-Path $ExeDir ($stem + ".exe")
    $log = Join-Path $BuildDir ($stem + ".build.log")
    $caseArtifactDir = Join-Path $ArtifactDir $stem
    New-Item -ItemType Directory -Force -Path $caseArtifactDir | Out-Null

    $isDx12 = $src.Name -like "*dx12*"
    if ($isDx12) {
        Write-Line ("[DX12 ] " + $src.Name + " -> native keep-open exe") Magenta
        $exit = Invoke-Dx12SampleBuild -Source $src -Stem $stem -Exe $exe -Log $log -CaseArtifactDir $caseArtifactDir
    } else {
        Write-Line ("[BUILD] " + $src.Name) Yellow
        $exit = Invoke-ConsoleSampleBuild -Source $src -Stem $stem -Exe $exe -Log $log -CaseArtifactDir $caseArtifactDir
    }

    if ($exit -eq 0) {
        Write-Line ("[PASS ] " + $src.Name + " -> " + $exe) Green
    } else {
        Write-Line ("[FAIL ] " + $src.Name + " exit=" + $exit + " log=" + $log) Red
        $Failed = $true
        continue
    }

    if ($RunConsoleSamples -and -not $isDx12) {
        $runLog = Join-Path $caseArtifactDir ($stem + ".stdout.txt")
        Write-Line ("[RUN  ] " + $src.Name) DarkYellow
        $runOutput = @(& $exe "sample_arg" *>&1)
        $runExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
        Write-OutputAndLog -Output $runOutput -Log $runLog
        if ($runExit -eq 0) { Write-Line ("[PASS ] run " + $src.Name) Green }
        else { Write-Line ("[FAIL ] run " + $src.Name + " exit=" + $runExit) Red; $Failed = $true }
    }

    if ($RunDx12 -and $isDx12) {
        Write-Line "[INFO ] DX12 run returns after the window closes." DarkCyan
    }

    Write-Line ""
}

Write-Line "+================================================================================+" Cyan
if ($Failed) {
    Write-Line "What_I_Can_Do build finished with failures." Red
    exit 1
}
Write-Line "What_I_Can_Do build finished successfully." Green
Write-Line "Use -RunConsoleSamples to execute non-DX12 samples after build." DarkCyan
Write-Line "Use -RunDx12 to launch the DX12 sample; it stays open by default." DarkCyan
exit 0
