param(
    [Parameter(Mandatory=$true)]
    [string]$Name
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$draftRoot = Join-Path $repoRoot "Experiments\CommandDrafts\$Name"

if (Test-Path $draftRoot) {
    Write-Host "Command draft already exists: $draftRoot"
    exit 1
}

New-Item -ItemType Directory -Force $draftRoot | Out-Null

function Write-DraftFile {
    param(
        [string]$FileName,
        [string]$Content
    )
    Set-Content -Path (Join-Path $draftRoot $FileName) -Value $Content -Encoding UTF8
}

Write-DraftFile "LANGUAGE_DESIGN.md" @"
# $Name Language Design

Canonical syntax:

TODO

Meaning:

TODO

Valid examples:

TODO

Invalid examples:

TODO
"@

Write-DraftFile "COMMAND_SPEC.command.txt" @"
COMMAND $Name
SYNTAX TODO
TOKENS TODO
AST TODO
SEMANTIC TODO
CODEGEN TODO
TEST_VALID TODO
TEST_INVALID TODO
LIMITATIONS TODO
"@

Write-DraftFile "LEXER_CHANGES.md" "# $Name Lexer Changes`r`n`r`nTODO`r`n"
Write-DraftFile "PARSER_CHANGES.md" "# $Name Parser Changes`r`n`r`nTODO`r`n"
Write-DraftFile "AST_CHANGES.md" "# $Name AST Changes`r`n`r`nTODO`r`n"
Write-DraftFile "SEMANTIC_CHANGES.md" "# $Name Semantic Changes`r`n`r`nTODO`r`n"
Write-DraftFile "CODEGEN_CHANGES.md" "# $Name Codegen Changes`r`n`r`nTODO`r`n"
Write-DraftFile "TESTS.md" "# $Name Tests`r`n`r`nTODO`r`n"

Write-DraftFile "IMPLEMENTATION_CHECKLIST.md" @"
# $Name Implementation Checklist

- [ ] syntax designed
- [ ] examples written
- [ ] invalid examples written
- [ ] lexer tokens added
- [ ] token dump verified
- [ ] parser rule added
- [ ] AST node added
- [ ] semantic checks added
- [ ] codegen behavior added or explicitly none
- [ ] positive tests added
- [ ] negative tests added
- [ ] docs updated
- [ ] old tests still pass
"@

Write-Host "Created command draft: $draftRoot"
