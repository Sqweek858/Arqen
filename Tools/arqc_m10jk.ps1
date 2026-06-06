$ErrorActionPreference = "Stop"

$CompilerVersion = "0.10.0-bootstrap"
$BackendName = "WindowsX64PE"
$BackendId = "WindowsX64PE_MessageBoxBackend"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$HelperPath = Join-Path $RepoRoot "Tools\BackendCommon\WindowsX64PE.psm1"
Import-Module $HelperPath -Force

$backendOnly = $false
$inputArg = $null
$outputArg = $null
$templateArg = Join-Path $RepoRoot "Experiments\M10_SimpleExpressions\template_messagebox_m8.exe"

for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "--backend-only") {
        $backendOnly = $true
    } elseif ($args[$i] -eq "-o") {
        if (($i + 1) -ge $args.Count) {
            Write-Host "Error: -o requires an output path."
            exit 2
        }
        $outputArg = $args[$i + 1]
        $i += 1
    } elseif ($args[$i] -eq "--template") {
        if (($i + 1) -ge $args.Count) {
            Write-Host "Error: --template requires a path."
            exit 2
        }
        $templateArg = $args[$i + 1]
        $i += 1
    } elseif ($null -eq $inputArg) {
        $inputArg = $args[$i]
    } else {
        Write-Host "Error: unexpected argument: $($args[$i])"
        exit 2
    }
}

if ($null -eq $inputArg) {
    Write-Host "Usage: arqc_m10jk.ps1 <input.arq> [-o output.exe]"
    Write-Host "       arqc_m10jk.ps1 --backend-only <input.arqir> [-o output.exe]"
    exit 2
}

function AbsPath {
    param([string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function RelPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }
    $root = ([IO.Path]::GetFullPath($RepoRoot)).TrimEnd("\") + "\"
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length).Replace("\", "/")
    }
    return $full.Replace("\", "/")
}

function Write-Lines {
    param([string]$Path, [string[]]$Lines)
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -Path $Path -Value $Lines -Encoding UTF8
}

$inputPath = AbsPath $inputArg
if (-not (Test-Path $inputPath)) {
    Write-Host "Error: input file not found: $inputPath"
    exit 2
}

$stem = [IO.Path]::GetFileNameWithoutExtension($inputPath)
$buildRoot = Join-Path $RepoRoot "Build"
$sourceDir = Join-Path $buildRoot "Sources"
$tokenDir = Join-Path $buildRoot "Tokens"
$astDir = Join-Path $buildRoot "AST"
$semanticDir = Join-Path $buildRoot "Semantic"
$irDir = Join-Path $buildRoot "IR"
$exeDir = Join-Path $buildRoot "EXE"
$logDir = Join-Path $buildRoot "Logs"
$manifestDir = Join-Path $buildRoot "Manifests"
$cacheDir = Join-Path $buildRoot "Cache"
$tempDir = Join-Path $buildRoot "Temp"
$errorDir = Join-Path $buildRoot "Errors"
$diagnosticsRoot = Join-Path $buildRoot "Diagnostics"
$backendDiagnosticDir = Join-Path $diagnosticsRoot "Backend"

foreach ($dir in @(
    $sourceDir, $tokenDir, $astDir, $semanticDir, $irDir, $exeDir, $logDir,
    $manifestDir, $cacheDir, $tempDir, $errorDir,
    (Join-Path $diagnosticsRoot "Lexer"),
    (Join-Path $diagnosticsRoot "Parser"),
    (Join-Path $diagnosticsRoot "Semantic"),
    (Join-Path $diagnosticsRoot "IR"),
    $backendDiagnosticDir
)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$sourceCopyPath = Join-Path $sourceDir ([IO.Path]::GetFileName($inputPath))
$tokenPath = Join-Path $tokenDir "$stem.tokens"
$astPath = Join-Path $astDir "$stem.ast"
$semanticPath = Join-Path $semanticDir "$stem.semantic.txt"
$irPath = if ($backendOnly) { $inputPath } else { Join-Path $irDir "$stem.arqir" }
$tempPath = Join-Path $tempDir "$stem.exe.tmp"
$artifactPath = if ($null -eq $outputArg) { Join-Path $exeDir "$stem.exe" } else { AbsPath $outputArg }
$logPath = Join-Path $logDir "$stem.m10jk.build.log"
$buildManifestPath = Join-Path $manifestDir "$stem.build.txt"
$artifactIndexPath = Join-Path $buildRoot "artifact_index.txt"
$layoutPath = Join-Path $RepoRoot "Backends\WindowsX64PE\Config\pe_layout_v0.txt"
$importsPath = Join-Path $RepoRoot "Backends\WindowsX64PE\Config\import_registry_v0.txt"
$capabilitiesPath = Join-Path $RepoRoot "Backends\WindowsX64PE\Config\capabilities_v0.txt"
$templatePath = AbsPath $templateArg
$buildId = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff")
$logLines = New-Object System.Collections.Generic.List[string]
$stageState = @{}
$stageOrder = @("lexer", "parser", "semantic", "ir", "codegen", "backend")

foreach ($stage in $stageOrder) {
    $stageState[$stage] = [pscustomobject]@{
        Status = "skipped"
        ExitCode = ""
        ErrorCode = ""
        ErrorFile = ""
        Notes = ""
    }
}

function Log-Line {
    param([string]$Line)
    Write-Host $Line
    $script:logLines.Add($Line) | Out-Null
}

function Stage-Input {
    param([string]$Stage)
    switch ($Stage) {
        "lexer" { return $inputPath }
        "parser" { return $tokenPath }
        "semantic" { return $astPath }
        "ir" { return $semanticPath }
        "codegen" { return $irPath }
        "backend" { return $irPath }
    }
}

function Stage-Output {
    param([string]$Stage)
    switch ($Stage) {
        "lexer" { return $tokenPath }
        "parser" { return $astPath }
        "semantic" { return $semanticPath }
        "ir" { return $irPath }
        "codegen" { return "" }
        "backend" { return $tempPath }
    }
}

function Write-StageManifest {
    param([string]$Stage)

    $state = $stageState[$Stage]
    $stageFile = switch ($Stage) {
        "lexer" { "lex" }
        "parser" { "parse" }
        default { $Stage }
    }
    $path = Join-Path $manifestDir "$stem.$stageFile.stage.txt"
    Write-Lines $path @(
        "STAGE|$Stage",
        "INPUT|$(RelPath (Stage-Input $Stage))",
        "OUTPUT|$(RelPath (Stage-Output $Stage))",
        "STATUS|$($state.Status)",
        "EXIT_CODE|$($state.ExitCode)",
        "ERROR_CODE|$($state.ErrorCode)",
        "ERROR_FILE|$(RelPath $state.ErrorFile)",
        "NOTES|$($state.Notes)"
    )
}

function Write-AllStageManifests {
    foreach ($stage in $stageOrder) {
        Write-StageManifest $stage
    }
}

function Write-BuildManifest {
    param(
        [string]$Status,
        [string]$FailedStage,
        [string]$ErrorPath
    )

    $run = @()
    $skipped = @()
    foreach ($stage in $stageOrder) {
        if ($stageState[$stage].Status -eq "skipped") {
            $skipped += $stage
        } else {
            $run += $stage
        }
    }

    Write-Lines $buildManifestPath @(
        "BUILD_ID|$buildId",
        "COMPILER_VERSION|$CompilerVersion",
        "SOURCE_PATH|$(RelPath $inputPath)",
        "SOURCE_HASH|$(Get-ArqFileSha256 $inputPath)",
        "TOKEN_PATH|$(RelPath $tokenPath)",
        "AST_PATH|$(RelPath $astPath)",
        "SEMANTIC_PATH|$(RelPath $semanticPath)",
        "IR_PATH|$(RelPath $irPath)",
        "ARTIFACT_PATH|$(RelPath $artifactPath)",
        "BACKEND|$BackendName",
        "STATUS|$Status",
        "FAILED_STAGE|$FailedStage",
        "STAGES_RUN|$($run -join ',')",
        "STAGES_SKIPPED|$($skipped -join ',')",
        "ERROR_PATH|$(RelPath $ErrorPath)",
        "LOG_PATH|$(RelPath $logPath)"
    )
}

function Write-BackendError {
    param([string]$Code, [string]$Message)

    $diag = Join-Path $backendDiagnosticDir "$stem.backend.diagnostic.txt"
    $err = Join-Path $errorDir "$stem.backend.error.txt"
    $lines = @(
        "Error ${Code}:",
        $Message
    )
    Write-Lines $diag $lines
    Write-Lines $err $lines
    return $err
}

function Set-Failure {
    param([string]$Stage, [string]$Code, [string]$ErrorPath, [string]$Notes)

    $stageState[$Stage].Status = "fail"
    $stageState[$Stage].ExitCode = "1"
    $stageState[$Stage].ErrorCode = $Code
    $stageState[$Stage].ErrorFile = $ErrorPath
    $stageState[$Stage].Notes = $Notes
    Write-AllStageManifests
    Write-BuildManifest "failure" $Stage $ErrorPath
    Write-Lines $logPath $logLines.ToArray()
}

function Promote-Artifact {
    $artifactDir = Split-Path -Parent $artifactPath
    if (-not [string]::IsNullOrWhiteSpace($artifactDir)) {
        New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
    }
    if (-not (Test-Path $tempPath) -or (Get-Item $tempPath).Length -le 0) {
        $err = Write-BackendError "B006" "temp output missing or empty"
        Set-Failure "backend" "B006" $err "temp-output"
        return $false
    }

    $check = Test-ArqPeArtifact $tempPath $importsPath
    if (-not $check.Ok) {
        $err = Write-BackendError $check.Code $check.Message
        Set-Failure "backend" $check.Code $err "temp-verification"
        return $false
    }

    try {
        Copy-Item -Path $tempPath -Destination $artifactPath -Force
    } catch {
        $err = Write-BackendError "B006" "output write failed: $($_.Exception.Message)"
        Set-Failure "backend" "B006" $err "promote"
        return $false
    }

    $finalCheck = Test-ArqPeArtifact $artifactPath $importsPath
    if (-not $finalCheck.Ok) {
        $err = Write-BackendError $finalCheck.Code $finalCheck.Message
        Set-Failure "backend" $finalCheck.Code $err "final-verification"
        return $false
    }

    return $true
}

foreach ($old in Get-ChildItem $errorDir -Filter "$stem.*.error.txt" -ErrorAction SilentlyContinue) {
    Remove-Item $old.FullName -Force
}
foreach ($dir in Get-ChildItem $diagnosticsRoot -Directory -ErrorAction SilentlyContinue) {
    foreach ($old in Get-ChildItem $dir.FullName -Filter "$stem.*.diagnostic.txt" -ErrorAction SilentlyContinue) {
        Remove-Item $old.FullName -Force
    }
}
foreach ($old in Get-ChildItem $manifestDir -Filter "$stem.*.stage.txt" -ErrorAction SilentlyContinue) {
    Remove-Item $old.FullName -Force
}
Remove-Item $tempPath -Force -ErrorAction SilentlyContinue

Copy-Item $inputPath $sourceCopyPath -Force
Log-Line "[M10JK] BUILD_ID $buildId"

$templateCheck = Test-ArqPeTemplate $templatePath $layoutPath $importsPath
if (-not $templateCheck.Ok) {
    $stageState["backend"].Status = "fail"
    $err = Write-BackendError $templateCheck.Code $templateCheck.Message
    Log-Line "[BACKEND] FAIL $($templateCheck.Code) -> $(RelPath $err)"
    Set-Failure "backend" $templateCheck.Code $err "template-validation"
    exit 1
}

$tool = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
if (-not (Test-Path $tool)) {
    $err = Write-BackendError "B006" "missing bootstrap driver Tools\arqc_m10g.exe"
    Log-Line "[BACKEND] FAIL B006 -> $(RelPath $err)"
    Set-Failure "backend" "B006" $err "missing-bootstrap-driver"
    exit 1
}

if ($backendOnly) {
    $capCheck = Test-ArqBackendCapabilities $irPath $capabilitiesPath
    if (-not $capCheck.Ok) {
        $err = Write-BackendError $capCheck.Code $capCheck.Message
        Log-Line "[BACKEND] FAIL $($capCheck.Code) -> $(RelPath $err)"
        Set-Failure "backend" $capCheck.Code $err "capability-check"
        exit 1
    }

    $rdataCheck = Test-ArqRDataPlan $irPath $layoutPath
    if (-not $rdataCheck.Ok) {
        $err = Write-BackendError $rdataCheck.Code $rdataCheck.Message
        Log-Line "[BACKEND] FAIL $($rdataCheck.Code) -> $(RelPath $err)"
        Set-Failure "backend" $rdataCheck.Code $err "rdata-plan"
        exit 1
    }

    $cmdArgs = @("--backend-only", $irPath, "-o", $tempPath)
} else {
    $cmdArgs = @($inputPath, "-o", $tempPath)
}

$outputLines = & $tool @cmdArgs 2>&1 | ForEach-Object { $_.ToString() }
$exitCode = $LASTEXITCODE
foreach ($line in $outputLines) {
    Log-Line $line
}

$passMap = @{
    "LEX" = "lexer"
    "PARSE" = "parser"
    "SEMANTIC" = "semantic"
    "IR" = "ir"
    "BACKEND" = "backend"
}
$failedStage = ""
$failedCode = ""
$reportedError = ""

foreach ($line in $outputLines) {
    if ($line -match '^\[(LEX|PARSE|SEMANTIC|IR|BACKEND)\] PASS') {
        $stage = $passMap[$matches[1]]
        $stageState[$stage].Status = "pass"
        $stageState[$stage].ExitCode = "0"
    } elseif ($line -match '^\[(LEX|PARSE|SEMANTIC|IR|BACKEND)\] FAIL ([A-Z][0-9]+) -> (.+)$') {
        $failedStage = $passMap[$matches[1]]
        $failedCode = $matches[2]
        $reportedError = AbsPath $matches[3]
    }
}

$stageState["codegen"].Status = "skipped"
$stageState["codegen"].Notes = "replaced-by-ir-backend"

if (-not $backendOnly -and (Test-Path $astPath) -and $stageState["semantic"].Status -eq "pass") {
    Write-Lines $semanticPath @(
        "SEMANTIC|OK",
        "AST|$(RelPath $astPath)",
        "IR|$(RelPath $irPath)"
    )
}

if ($exitCode -ne 0) {
    if ([string]::IsNullOrWhiteSpace($failedStage)) {
        $failedStage = "backend"
        $failedCode = "B006"
    }

    if ($failedStage -eq "backend" -and (Test-Path $irPath)) {
        $capCheck = Test-ArqBackendCapabilities $irPath $capabilitiesPath
        if (-not $capCheck.Ok) {
            $failedCode = $capCheck.Code
            $reportedError = Write-BackendError $capCheck.Code $capCheck.Message
        } else {
            $rdataCheck = Test-ArqRDataPlan $irPath $layoutPath
            if (-not $rdataCheck.Ok) {
                $failedCode = $rdataCheck.Code
                $reportedError = Write-BackendError $rdataCheck.Code $rdataCheck.Message
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($reportedError) -or -not (Test-Path $reportedError)) {
        $reportedError = Write-BackendError $failedCode "stage failed"
    }

    Log-Line "[M10JK] FAIL $failedStage $failedCode"
    Set-Failure $failedStage $failedCode $reportedError "bootstrap-stage-failure"
    exit 1
}

if (-not (Test-Path $irPath)) {
    $err = Write-BackendError "B007" "IR output missing"
    Log-Line "[IR] FAIL B007 -> $(RelPath $err)"
    Set-Failure "ir" "B007" $err "missing-ir"
    exit 1
}

$capCheck = Test-ArqBackendCapabilities $irPath $capabilitiesPath
if (-not $capCheck.Ok) {
    $err = Write-BackendError $capCheck.Code $capCheck.Message
    Log-Line "[BACKEND] FAIL $($capCheck.Code) -> $(RelPath $err)"
    Set-Failure "backend" $capCheck.Code $err "capability-check"
    exit 1
}

$rdataCheck = Test-ArqRDataPlan $irPath $layoutPath
if (-not $rdataCheck.Ok) {
    $err = Write-BackendError $rdataCheck.Code $rdataCheck.Message
    Log-Line "[BACKEND] FAIL $($rdataCheck.Code) -> $(RelPath $err)"
    Set-Failure "backend" $rdataCheck.Code $err "rdata-plan"
    exit 1
}

if (-not (Promote-Artifact)) {
    exit 1
}

$stageState["backend"].Status = "pass"
$stageState["backend"].ExitCode = "0"
$stageState["backend"].Notes = "promoted=$(RelPath $artifactPath)"

$sameStemErrors = Get-ChildItem $errorDir -Filter "$stem.*.error.txt" -ErrorAction SilentlyContinue
if ($sameStemErrors.Count -gt 0) {
    $err = Write-BackendError "B007" "error file exists for passing build"
    Log-Line "[BACKEND] FAIL B007 -> $(RelPath $err)"
    Set-Failure "backend" "B007" $err "stale-error-file"
    exit 1
}

Write-AllStageManifests
Write-BuildManifest "success" "" ""
Write-Lines $logPath $logLines.ToArray()
Write-Lines $artifactIndexPath @(
    "ARTIFACT|$(RelPath $artifactPath)|source=$(RelPath $inputPath)|backend=$BackendName|status=pass"
)

Log-Line "[M10JK] PASS -> $(RelPath $artifactPath)"
Write-Lines $logPath $logLines.ToArray()
exit 0
