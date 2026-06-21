param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$failed = $false

function Emit-Check {
    param([string]$Name, [bool]$Ok, [string]$Message)
    if ($Ok) {
        Write-Host "PASS|$Name|$Message"
    } else {
        Write-Host "FAIL|$Name|$Message"
        $script:failed = $true
    }
}

$programPath = Join-Path $RepoRoot "Tools/M10GDriver/Program.cs"
$parserDir = Join-Path $RepoRoot "Tools/M10GDriver/Parser"
$programText = if (Test-Path $programPath) { [System.IO.File]::ReadAllText($programPath) } else { "" }
$parserFiles = if (Test-Path $parserDir) { @(Get-ChildItem $parserDir -Filter "Parser.*.cs" | Sort-Object Name) } else { @() }
$parserText = ($parserFiles | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"

Emit-Check "parser_dir_exists" (Test-Path $parserDir) "parser split directory present"
Emit-Check "program_no_parser_monolith" ($programText -notmatch "sealed\s+class\s+Parser" -and $programText -notmatch "sealed\s+partial\s+class\s+Parser") "Program.cs no longer owns parser implementation"
Emit-Check "parser_partial_class_present" ($parserText -match "sealed\s+partial\s+class\s+Parser") "parser is nested partial class"
Emit-Check "parser_file_count_min" ($parserFiles.Count -ge 8) "parser split has multiple focused files"
Emit-Check "parser_core_present" (Test-Path (Join-Path $parserDir "Parser.Core.cs")) "core parser file present"
Emit-Check "parser_statements_present" (Test-Path (Join-Path $parserDir "Parser.Statements.cs")) "statement parser file present"
Emit-Check "parser_expressions_present" (Test-Path (Join-Path $parserDir "Parser.Expressions.cs")) "expression parser file present"
Emit-Check "parser_helpers_present" (Test-Path (Join-Path $parserDir "Parser.Helpers.cs")) "helper parser file present"
Emit-Check "parser_parse_entry_present" ($parserText -match "AstModel\s+Parse\s*\(") "Parse entry point moved into parser split"
Emit-Check "parser_statement_dispatch_present" ($parserText -match "ParseStatement\s*\(") "statement dispatch preserved"
Emit-Check "parser_expression_dispatch_present" ($parserText -match "ParseExpression\s*\(") "expression dispatch preserved"
Emit-Check "parser_doc_present" (Test-Path (Join-Path $RepoRoot "Docs/Milestones/M16_M20.md")) "parser split doc present"

if ($failed) { exit 1 }
exit 0
