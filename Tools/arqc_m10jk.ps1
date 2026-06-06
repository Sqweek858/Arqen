$ErrorActionPreference = "Stop"

$CompilerVersion = "0.10.0-bootstrap"
$BackendName = "WindowsX64PE"
$BackendId = "WindowsX64PE_MessageBoxBackend"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$HelperPath = Join-Path $RepoRoot "Tools\BackendCommon\WindowsX64PE.psm1"
Import-Module $HelperPath -Force

$backendOnly = $false
$noCache = $false
$rebuild = $false
$cleanCache = $false
$cacheInfo = $false
$inputArg = $null
$outputArg = $null
$templateArg = Join-Path $RepoRoot "Experiments\M10_SimpleExpressions\template_messagebox_m8.exe"

for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "--backend-only") {
        $backendOnly = $true
    } elseif ($args[$i] -eq "--no-cache") {
        $noCache = $true
    } elseif ($args[$i] -eq "--rebuild") {
        $rebuild = $true
    } elseif ($args[$i] -eq "--clean-cache") {
        $cleanCache = $true
    } elseif ($args[$i] -eq "--cache-info") {
        $cacheInfo = $true
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

if ($cleanCache) {
    $cacheRoot = Join-Path $RepoRoot "Build\Cache"
    New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null
    Get-ChildItem $cacheRoot -Force | Where-Object { $_.Name -ne ".gitkeep" } | Remove-Item -Recurse -Force
    Write-Host "[CACHE] CLEAN -> Build/Cache"
    exit 0
}

if ($null -eq $inputArg) {
    Write-Host "Usage: arqc_m10jk.ps1 <input.arq> [-o output.exe]"
    Write-Host "       arqc_m10jk.ps1 --backend-only <input.arqir> [-o output.exe]"
    Write-Host "       arqc_m10jk.ps1 --clean-cache"
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
$cacheSchemaVersion = "0"
$cacheTarget = $BackendName
$cacheEnabled = $true
$cacheStatus = "miss"
$cacheReason = ""
$cacheKey = ""
$cachePath = ""
$cacheRecordPath = ""
$cacheArtifactPath = ""
$cacheDiagnosticsPath = ""
$cacheBuildManifestPath = ""
$buildId = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff")
$logLines = New-Object System.Collections.Generic.List[string]
$diagnostics = New-Object System.Collections.Generic.List[object]
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

$allDiagnosticsPath = Join-Path $diagnosticsRoot "$stem.all_errors.txt"
$lexDiagnosticsPath = Join-Path $diagnosticsRoot "$stem.lex.diagnostics.txt"

function Log-Line {
    param([string]$Line)
    Write-Host $Line
    $script:logLines.Add($Line) | Out-Null
}

function Add-Diagnostic {
    param(
        [string]$Code,
        [string]$Stage,
        [int]$Line,
        [int]$Column,
        [string]$Message
    )

    $key = "$Code|$Stage|$Line|$Column|$Message"
    foreach ($diag in $diagnostics) {
        if ($diag.Key -eq $key) {
            return
        }
    }
    $diagnostics.Add([pscustomobject]@{
        Key = $key
        Code = $Code
        Stage = $Stage
        Line = $Line
        Column = $Column
        Message = $Message
    }) | Out-Null
}

function Diagnostic-Line {
    param($Diag)

    return "$($Diag.Code)|$($Diag.Stage)|line=$($Diag.Line)|column=$($Diag.Column)|$($Diag.Message)"
}

function Write-AllDiagnostics {
    param([string]$Status)

    $lines = @(
        "DIAGNOSTICS|$(RelPath $inputPath)",
        "STATUS|$Status",
        "ERROR_COUNT|$($diagnostics.Count)"
    )
    foreach ($diag in $diagnostics) {
        $lines += Diagnostic-Line $diag
    }
    $lines += "END"
    Write-Lines $allDiagnosticsPath $lines

    $lexLines = @()
    foreach ($diag in $diagnostics) {
        if ($diag.Stage -eq "lexer" -or $diag.Code.StartsWith("L")) {
            $lexLines += Diagnostic-Line $diag
        }
    }
    if ($lexLines.Count -gt 0) {
        Write-Lines $lexDiagnosticsPath $lexLines
    } else {
        Remove-Item $lexDiagnosticsPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-DiagnosticStageCount {
    param([string]$Stage)

    $count = 0
    foreach ($diag in $diagnostics) {
        if ($diag.Stage -eq $Stage) {
            $count += 1
        } elseif ($Stage -eq "lexer" -and $diag.Code.StartsWith("L")) {
            $count += 1
        } elseif ($Stage -eq "parser" -and $diag.Stage -eq "lint" -and $diag.Code.StartsWith("P")) {
            $count += 1
        }
    }
    return $count
}

function Get-EarliestDiagnosticStage {
    $hasLexer = $false
    $hasParser = $false
    $hasSemantic = $false
    $hasBackend = $false
    foreach ($diag in $diagnostics) {
        if ($diag.Stage -eq "lexer" -or $diag.Code.StartsWith("L")) { $hasLexer = $true }
        elseif ($diag.Stage -eq "parser" -or $diag.Stage -eq "lint" -or $diag.Code.StartsWith("P")) { $hasParser = $true }
        elseif ($diag.Stage -eq "semantic" -or $diag.Code.StartsWith("S")) { $hasSemantic = $true }
        elseif ($diag.Stage -eq "backend" -or $diag.Code.StartsWith("B")) { $hasBackend = $true }
    }
    if ($hasLexer) { return "lexer" }
    if ($hasParser) { return "parser" }
    if ($hasSemantic) { return "semantic" }
    if ($hasBackend) { return "backend" }
    return ""
}

function Get-FirstDiagnosticCodeForStage {
    param([string]$Stage)

    foreach ($diag in $diagnostics) {
        if ($Stage -eq "lexer" -and ($diag.Stage -eq "lexer" -or $diag.Code.StartsWith("L"))) { return $diag.Code }
        if ($Stage -eq "parser" -and ($diag.Stage -eq "parser" -or $diag.Stage -eq "lint" -or $diag.Code.StartsWith("P"))) { return $diag.Code }
        if ($Stage -eq "semantic" -and ($diag.Stage -eq "semantic" -or $diag.Code.StartsWith("S"))) { return $diag.Code }
        if ($Stage -eq "backend" -and ($diag.Stage -eq "backend" -or $diag.Code.StartsWith("B"))) { return $diag.Code }
    }
    return ""
}

function Add-ErrorFileDiagnostic {
    param(
        [string]$Stage,
        [string]$Path,
        [string]$FallbackCode,
        [string]$FallbackMessage
    )

    if (-not (Test-Path $Path)) {
        Add-Diagnostic $FallbackCode $Stage 0 0 $FallbackMessage
        return
    }

    $text = Get-Content $Path -Raw
    $line = 0
    $column = 0
    $code = $FallbackCode
    $message = $FallbackMessage

    if ($text -match 'Error\s+([A-Z][0-9]+)(?:\s+at\s+line\s+([0-9]+),\s+column\s+([0-9]+))?:\s*[\r\n]+(.+)') {
        $code = $matches[1]
        if ($matches[2]) { $line = [int]$matches[2] }
        if ($matches[3]) { $column = [int]$matches[3] }
        $message = $matches[4].Trim()
    } elseif ($text -match 'Error\s+([A-Z][0-9]+):\s*[\r\n]+(.+)') {
        $code = $matches[1]
        $message = $matches[2].Trim()
    }

    Add-Diagnostic $code $Stage $line $column $message
}

function Add-SourceDiagnostics {
    if ($backendOnly -or -not $inputPath.EndsWith(".arq", [StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    $knownStarts = @("program", "end", "let", "title", "message", "exit", "blend")
    $lines = Get-Content $inputPath
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNo = $i + 1
        $line = [string]$lines[$i]
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        for ($c = 0; $c -lt $line.Length; $c++) {
            $codePoint = [int][char]$line[$c]
            if ($codePoint -lt 32 -and $line[$c] -ne "`t") {
                Add-Diagnostic "L004" "lexer" $lineNo ($c + 1) "Unexpected control character."
            }
        }

        if ($trimmed.StartsWith("@")) {
            $col = $line.IndexOf("@") + 1
            Add-Diagnostic "L001" "lexer" $lineNo $col "Unknown character '@'."
        }

        $wordMatch = [regex]::Match($trimmed, '^([A-Za-z_][A-Za-z0-9_]*)')
        $firstWord = if ($wordMatch.Success) { $wordMatch.Groups[1].Value } else { "" }
        if ($firstWord -eq "tile") {
            Add-Diagnostic "P020" "lint" $lineNo 1 'Expected keyword "title", got "tile".'
        } elseif ($firstWord -ne "" -and ($knownStarts -notcontains $firstWord)) {
            Add-Diagnostic "P021" "lint" $lineNo 1 "Unknown top-level statement `"$firstWord`"."
        }

        if ($trimmed -eq "exit") {
            Add-Diagnostic "P030" "lint" $lineNo 1 'Expected exit code after "exit".'
        } elseif ($trimmed -match '^exit\s+([^0-9\s]\S*)') {
            Add-Diagnostic "L003" "lexer" $lineNo ($line.IndexOf($matches[1]) + 1) "Invalid integer."
        }

        $openQuote = 0
        $quoteOpen = $false
        for ($c = 0; $c -lt $line.Length; $c++) {
            if ($line[$c] -eq '"') {
                if (-not $quoteOpen) {
                    $quoteOpen = $true
                    $openQuote = $c + 1
                } else {
                    $quoteOpen = $false
                }
            }
        }
        if ($quoteOpen) {
            Add-Diagnostic "L002" "lint" $lineNo $openQuote "Unterminated string."
        }
    }
}

function Get-StringSha256 {
    param([string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $hash = $sha.ComputeHash($bytes)
    return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Get-FileHashOrEmpty {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return ""
    }
    return Get-ArqFileSha256 $Path
}

function Get-DirectoryContentHash {
    param(
        [string]$Path,
        [string]$Filter = "*.txt"
    )

    if (-not (Test-Path $Path)) {
        return ""
    }

    $lines = @()
    foreach ($file in Get-ChildItem $Path -Filter $Filter -File -Recurse | Sort-Object FullName) {
        $lines += "$(RelPath $file.FullName)=$(Get-ArqFileSha256 $file.FullName)"
    }
    return Get-StringSha256 ($lines -join "`n")
}

function Initialize-CacheState {
    $script:cacheKeyInputLines = @(
        "CACHE_SCHEMA_VERSION|$cacheSchemaVersion",
        "SOURCE_HASH|$(Get-ArqFileSha256 $inputPath)",
        "COMPILER_VERSION|$CompilerVersion",
        "DRIVER_HASH|$(Get-FileHashOrEmpty (Join-Path $RepoRoot 'Tools\arqc_m10jk.ps1'))",
        "M10G_HASH|$(Get-FileHashOrEmpty (Join-Path $RepoRoot 'Tools\arqc_m10g.exe'))",
        "M10JK_HASH|$(Get-FileHashOrEmpty (Join-Path $RepoRoot 'Tools\arqc_m10jk.ps1'))",
        "BACKEND_HELPER_HASH|$(Get-FileHashOrEmpty (Join-Path $RepoRoot 'Tools\BackendCommon\WindowsX64PE.psm1'))",
        "BACKEND_CONFIG_HASH|$(Get-DirectoryContentHash (Join-Path $RepoRoot 'Backends\WindowsX64PE\Config') '*.txt')",
        "TEMPLATE_HASH|$(Get-FileHashOrEmpty $templatePath)",
        "COMMAND_SPECS_HASH|$(Get-DirectoryContentHash (Join-Path $RepoRoot 'Specs\Commands') '*.command.txt')",
        "TARGET|$cacheTarget"
    )
    $script:cacheKey = Get-StringSha256 ($script:cacheKeyInputLines -join "`n")
    $script:cachePath = Join-Path $cacheDir $script:cacheKey
    $script:cacheRecordPath = Join-Path $script:cachePath "cache_record.txt"
    $script:cacheArtifactPath = Join-Path $script:cachePath "artifact.exe"
    $script:cacheDiagnosticsPath = Join-Path $script:cachePath "diagnostics.txt"
    $script:cacheBuildManifestPath = Join-Path $script:cachePath "build_manifest.txt"
}

function Write-CacheInfo {
    Write-Host "CACHE_KEY|$cacheKey"
    foreach ($line in $script:cacheKeyInputLines) {
        Write-Host $line
    }
    Write-Host "CACHE_PATH|$(RelPath $cachePath)"
    Write-Host "CACHE_EXISTS|$(if (Test-Path $cacheRecordPath) { 'true' } else { 'false' })"
}

function Test-CacheHit {
    if (-not (Test-Path $cacheRecordPath)) {
        $script:cacheReason = "no-entry"
        return $false
    }
    if (-not (Test-Path $cacheArtifactPath) -or (Get-Item $cacheArtifactPath).Length -le 0) {
        $script:cacheReason = "missing-artifact"
        return $false
    }
    if (-not (Test-Path $cacheDiagnosticsPath)) {
        $script:cacheReason = "missing-diagnostics"
        return $false
    }

    $record = Get-Content $cacheRecordPath -Raw
    if (-not $record.Contains("CACHE_KEY|$cacheKey") -or -not $record.Contains("STATUS|success")) {
        $script:cacheReason = "record-mismatch"
        return $false
    }

    $diag = Get-Content $cacheDiagnosticsPath -Raw
    if (-not $diag.Contains("ERROR_COUNT|0") -or -not $diag.Contains("STATUS|success")) {
        $script:cacheReason = "diagnostics-not-success"
        return $false
    }

    $check = Test-ArqPeArtifact $cacheArtifactPath $importsPath
    if (-not $check.Ok) {
        $script:cacheReason = "artifact-invalid-$($check.Code)"
        return $false
    }

    $script:cacheReason = "valid-entry"
    return $true
}

function Write-ArtifactIndex {
    param([string]$CacheState)

    Write-Lines $artifactIndexPath @(
        "ARTIFACT|$(RelPath $artifactPath)|source=$(RelPath $inputPath)|backend=$BackendName|status=pass|cache=$CacheState",
        "CACHE|$CacheState|$(RelPath $artifactPath)|key=$cacheKey"
    )
}

function Restore-CacheHit {
    $artifactDir = Split-Path -Parent $artifactPath
    if (-not [string]::IsNullOrWhiteSpace($artifactDir)) {
        New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
    }

    Copy-Item $cacheArtifactPath $artifactPath -Force
    Copy-Item $cacheDiagnosticsPath $allDiagnosticsPath -Force

    $finalCheck = Test-ArqPeArtifact $artifactPath $importsPath
    if (-not $finalCheck.Ok) {
        $script:cacheStatus = "miss"
        $script:cacheReason = "restored-artifact-invalid-$($finalCheck.Code)"
        return $false
    }

    foreach ($stage in @("lexer", "parser", "semantic", "ir", "backend")) {
        $stageState[$stage].Status = "skipped"
        $stageState[$stage].Notes = "cache-hit"
    }
    $stageState["codegen"].Status = "skipped"
    $stageState["codegen"].Notes = "cache-hit"
    $script:cacheStatus = "hit"
    $script:cacheReason = "valid-entry"
    Write-AllStageManifests
    Write-BuildManifest "success" "" ""
    Write-Lines $logPath $logLines.ToArray()
    Write-ArtifactIndex "hit"
    return $true
}

function Store-CacheEntry {
    if ($noCache -or $backendOnly) {
        return
    }
    if (-not (Test-Path $artifactPath) -or (Get-Item $artifactPath).Length -le 0) {
        return
    }
    if (-not (Test-Path $allDiagnosticsPath) -or -not (Get-Content $allDiagnosticsPath -Raw).Contains("ERROR_COUNT|0")) {
        return
    }

    $check = Test-ArqPeArtifact $artifactPath $importsPath
    if (-not $check.Ok) {
        return
    }

    New-Item -ItemType Directory -Force -Path $cachePath | Out-Null
    Copy-Item $artifactPath $cacheArtifactPath -Force
    Copy-Item $allDiagnosticsPath $cacheDiagnosticsPath -Force
    if (Test-Path $buildManifestPath) { Copy-Item $buildManifestPath $cacheBuildManifestPath -Force }
    if (Test-Path $sourceCopyPath) { Copy-Item $sourceCopyPath (Join-Path $cachePath "source.arq") -Force }
    if (Test-Path $tokenPath) { Copy-Item $tokenPath (Join-Path $cachePath "tokens.txt") -Force }
    if (Test-Path $astPath) { Copy-Item $astPath (Join-Path $cachePath "ast.txt") -Force }
    if (Test-Path $semanticPath) { Copy-Item $semanticPath (Join-Path $cachePath "semantic.txt") -Force }
    if (Test-Path $irPath) { Copy-Item $irPath (Join-Path $cachePath "ir.arqir") -Force }

    $record = @(
        "CACHE_SCHEMA_VERSION|$cacheSchemaVersion",
        "CACHE_KEY|$cacheKey",
        "CACHE_STATUS|stored",
        "SOURCE_PATH|$(RelPath $inputPath)",
        "SOURCE_HASH|$(Get-ArqFileSha256 $inputPath)",
        "COMPILER_VERSION|$CompilerVersion",
        "DRIVER_HASH|$(($script:cacheKeyInputLines | Where-Object { $_.StartsWith('DRIVER_HASH|') }).Split('|')[1])",
        "BACKEND_HASH|$(($script:cacheKeyInputLines | Where-Object { $_.StartsWith('BACKEND_HELPER_HASH|') }).Split('|')[1])",
        "BACKEND_CONFIG_HASH|$(($script:cacheKeyInputLines | Where-Object { $_.StartsWith('BACKEND_CONFIG_HASH|') }).Split('|')[1])",
        "TEMPLATE_HASH|$(($script:cacheKeyInputLines | Where-Object { $_.StartsWith('TEMPLATE_HASH|') }).Split('|')[1])",
        "COMMAND_SPECS_HASH|$(($script:cacheKeyInputLines | Where-Object { $_.StartsWith('COMMAND_SPECS_HASH|') }).Split('|')[1])",
        "TARGET|$cacheTarget",
        "ARTIFACT_PATH|$(RelPath $cacheArtifactPath)",
        "DIAGNOSTICS_PATH|$(RelPath $cacheDiagnosticsPath)",
        "STORED_AT|$((Get-Date).ToUniversalTime().ToString('o'))",
        "STATUS|success"
    )
    Write-Lines $cacheRecordPath $record
    Log-Line "[CACHE] STORE -> $(RelPath $cachePath)"
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
        "DIAGNOSTIC_COUNT|$(Get-DiagnosticStageCount $Stage)",
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
        "DIAGNOSTICS_PATH|$(RelPath $allDiagnosticsPath)",
        "ERROR_COUNT|$($diagnostics.Count)",
        "CACHE_ENABLED|$cacheEnabled",
        "CACHE_SCHEMA_VERSION|$cacheSchemaVersion",
        "CACHE_KEY|$cacheKey",
        "CACHE_STATUS|$cacheStatus",
        "CACHE_PATH|$(RelPath $cachePath)",
        "CACHE_REASON|$cacheReason",
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
    Add-Diagnostic $Code "backend" 0 0 $Message
    return $err
}

function Set-Failure {
    param([string]$Stage, [string]$Code, [string]$ErrorPath, [string]$Notes)

    $stageState[$Stage].Status = "fail"
    $stageState[$Stage].ExitCode = "1"
    $stageState[$Stage].ErrorCode = $Code
    $stageState[$Stage].ErrorFile = $ErrorPath
    $stageState[$Stage].Notes = $Notes
    Write-AllDiagnostics "failed"
    Write-AllStageManifests
    Write-BuildManifest "failure" $Stage $allDiagnosticsPath
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
    Remove-Item $old.FullName -Force -ErrorAction SilentlyContinue
}
foreach ($dir in Get-ChildItem $diagnosticsRoot -Directory -ErrorAction SilentlyContinue) {
    foreach ($old in Get-ChildItem $dir.FullName -Filter "$stem.*.diagnostic.txt" -ErrorAction SilentlyContinue) {
        Remove-Item $old.FullName -Force -ErrorAction SilentlyContinue
    }
}
foreach ($old in Get-ChildItem $manifestDir -Filter "$stem.*.stage.txt" -ErrorAction SilentlyContinue) {
    Remove-Item $old.FullName -Force -ErrorAction SilentlyContinue
}
Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
Remove-Item $allDiagnosticsPath, $lexDiagnosticsPath -Force -ErrorAction SilentlyContinue

Copy-Item $inputPath $sourceCopyPath -Force
Log-Line "[M10JK] BUILD_ID $buildId"
Initialize-CacheState
if ($cacheInfo) {
    Write-CacheInfo
}

Add-SourceDiagnostics
if ($diagnostics.Count -gt 0) {
    $cacheStatus = "bypass"
    $cacheReason = "diagnostics_error"
    $earlyStage = Get-EarliestDiagnosticStage
    $earlyCode = Get-FirstDiagnosticCodeForStage $earlyStage
    $stageState[$earlyStage].Status = "fail"
    $stageState[$earlyStage].ExitCode = "1"
    $stageState[$earlyStage].ErrorCode = $earlyCode
    $stageState[$earlyStage].ErrorFile = $allDiagnosticsPath
    $stageState[$earlyStage].Notes = "unified-diagnostics-gate"
    Log-Line "[M10JK] FAIL $earlyStage $earlyCode"
    Set-Failure $earlyStage $earlyCode $allDiagnosticsPath "unified-diagnostics-gate"
    exit 1
}

if ($backendOnly) {
    $cacheStatus = "bypass"
    $cacheReason = "backend-only"
    Log-Line "[CACHE] BYPASS backend-only"
} elseif ($noCache) {
    $cacheStatus = "bypass"
    $cacheReason = "no-cache"
    Log-Line "[CACHE] BYPASS no-cache"
} elseif ($rebuild) {
    $cacheStatus = "miss"
    $cacheReason = "rebuild"
    Log-Line "[CACHE] MISS rebuild"
} elseif (Test-CacheHit) {
    Log-Line "[CACHE] HIT"
    if (Restore-CacheHit) {
        Log-Line "[BUILD] SKIP"
        Log-Line "[ARTIFACT] $(RelPath $artifactPath)"
        Write-Lines $logPath $logLines.ToArray()
        exit 0
    }
    Log-Line "[CACHE] MISS $cacheReason"
} else {
    $cacheStatus = "miss"
    Log-Line "[CACHE] MISS $cacheReason"
}

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
    } else {
        Add-ErrorFileDiagnostic $failedStage $reportedError $failedCode "stage failed"
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
Write-AllDiagnostics "success"
if ($noCache) {
    $cacheStatus = "bypass"
    $cacheReason = "no-cache"
} elseif ($backendOnly) {
    $cacheStatus = "bypass"
    $cacheReason = "backend-only"
} else {
    $cacheStatus = "store"
    if ([string]::IsNullOrWhiteSpace($cacheReason) -or $cacheReason -eq "valid-entry") {
        $cacheReason = if ($rebuild) { "rebuild" } else { "stored-success" }
    }
}
Write-BuildManifest "success" "" ""
Write-Lines $logPath $logLines.ToArray()
Write-ArtifactIndex $cacheStatus
Store-CacheEntry

Log-Line "[M10JK] PASS -> $(RelPath $artifactPath)"
Write-Lines $logPath $logLines.ToArray()
exit 0
