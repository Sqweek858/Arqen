param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$failed = $false

function Emit-Check {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Message
    )

    if ($Ok) {
        Write-Host "PASS|$Name|$Message"
    } else {
        Write-Host "FAIL|$Name|$Message"
        $script:failed = $true
    }
}

function Emit-Warn {
    param(
        [string]$Name,
        [string]$Message
    )

    Write-Host "WARN|$Name|$Message"
}

function Read-AllParserSource {
    param([string]$ParserRoot)

    if (-not (Test-Path $ParserRoot)) {
        return ""
    }

    return (
        Get-ChildItem $ParserRoot -Recurse -Filter *.cs |
        Sort-Object FullName |
        ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }
    ) -join "`n"
}

function Get-Field {
    param(
        [string[]]$Parts,
        [string]$Name
    )

    for ($i = 0; $i -lt $Parts.Count - 1; $i++) {
        if ($Parts[$i] -eq $Name) {
            return $Parts[$i + 1]
        }
    }

    return ""
}

$generatorPath = Join-Path $RepoRoot "Tools/generate_parser_statement_map.ps1"
$parserRoot = Join-Path $RepoRoot "Tools/M10GDriver/Parser"
$statementsPath = Join-Path $parserRoot "Parser.Statements.cs"
$generatedPath = Join-Path $RepoRoot "Build/Generated/parser_statement_map.txt"

Emit-Check "parser_statement_generator_exists" (Test-Path $generatorPath) "statement map generator present"

if (Test-Path $generatorPath) {
    & $generatorPath | Out-Null
}

Emit-Check "parser_statement_map_generated" (Test-Path $generatedPath) "statement map generated"

$rows = @()
if (Test-Path $generatedPath) {
    $rows = @(Get-Content $generatedPath | Where-Object {
        $_.Trim() -ne "" -and
        -not $_.Trim().StartsWith("#") -and
        $_ -match "\|"
    })
}

Emit-Check "parser_statement_map_row_count" ($rows.Count -ge 15) "rows=$($rows.Count)"

$missingSpecs = @()
$missingTests = @()
$missingValid = @()
$missingInvalid = @()

foreach ($row in $rows) {
    $parts = $row.Split("|")
    $commandId = Get-Field $parts "COMMAND_ID"
    $hasTests = Get-Field $parts "HAS_TESTS"
    $hasValid = Get-Field $parts "HAS_VALID_SAMPLE"
    $hasInvalid = Get-Field $parts "HAS_INVALID_SAMPLE"

    if ([string]::IsNullOrWhiteSpace($commandId)) {
        continue
    }

    $specPath = Join-Path $RepoRoot "Specs/Commands/$commandId.command.txt"
    $testPath = Join-Path $RepoRoot "Tests/CommandTests/$commandId"

    if (-not (Test-Path $specPath)) {
        $missingSpecs += $commandId
    }

    if (-not (Test-Path $testPath) -and $hasTests -ne "true") {
        $missingTests += $commandId
    }

    if ($hasValid -ne "true") {
        $missingValid += $commandId
    }

    if ($hasInvalid -ne "true") {
        $missingInvalid += $commandId
    }
}

if ($missingSpecs.Count -eq 0) {
    Write-Host "PASS|parser_statement_map_specs_present|missingSpec=0"
} else {
    Emit-Warn "parser_statement_map_specs_present" ("missingSpec=$($missingSpecs.Count) names=" + (($missingSpecs | Sort-Object -Unique) -join ","))
}

if ($missingTests.Count -eq 0) {
    Write-Host "PASS|parser_statement_map_tests_present|missingTests=0"
} else {
    Emit-Warn "parser_statement_map_tests_present" ("missingTests=$($missingTests.Count) names=" + (($missingTests | Sort-Object -Unique) -join ","))
}

if ($missingValid.Count -eq 0) {
    Write-Host "PASS|parser_statement_map_valid_samples|missingValid=0"
} else {
    Emit-Warn "parser_statement_map_valid_samples" ("missingValid=$($missingValid.Count) names=" + (($missingValid | Sort-Object -Unique) -join ","))
}

if ($missingInvalid.Count -eq 0) {
    Write-Host "PASS|parser_statement_map_invalid_samples|missingInvalid=0"
} else {
    Emit-Warn "parser_statement_map_invalid_samples" ("missingInvalid=$($missingInvalid.Count) names=" + (($missingInvalid | Sort-Object -Unique) -join ","))
}

Emit-Check "parser_statement_dispatch_file_exists" (Test-Path $statementsPath) "statement dispatch file present"

$parserText = Read-AllParserSource $parserRoot

$coreStarts = @(
    "program",
    "let",
    "define",
    "rename",
    "print",
    "show",
    "set",
    "write",
    "load",
    "if",
    "while",
    "function",
    "call",
    "run",
    "when",
    "close",
    "with",
    "use",
    "style",
    "blend"
)

$missingStarts = @()

foreach ($start in $coreStarts) {
    $escaped = [regex]::Escape($start)

    $has =
        ($parserText -match "MatchKeyword\(`"$escaped`"\)") -or
        ($parserText -match "CheckKeyword\(`"$escaped`"\)") -or
        ($parserText -match "ExpectKeyword\(`"$escaped`"\)") -or
        ($parserText -match "`"$escaped`"")

    if (-not $has) {
        $missingStarts += $start
    }
}

if ($missingStarts.Count -eq 0) {
    $dispatchMessage = "statement dispatch includes core/runtime starts"
} else {
    $dispatchMessage = "missing=" + (($missingStarts | Sort-Object) -join ",")
}

Emit-Check "parser_statement_dispatch_known_starts" ($missingStarts.Count -eq 0) $dispatchMessage

if ($failed) {
    exit 1
}

exit 0
