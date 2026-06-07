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
    if ($Ok) { Write-Host "PASS|$Name|$Message" } else { Write-Host "FAIL|$Name|$Message"; $script:failed = $true }
}

$path = Join-Path $RepoRoot "Tools/run_test_slice.ps1"
$text = if (Test-Path $path) { [System.IO.File]::ReadAllText($path) } else { "" }

Emit-Check "test_slice_exists" (Test-Path $path) "selective runner present"
Emit-Check "test_slice_changed_includes_untracked" ($text -match 'ls-files\s+--others\s+--exclude-standard') "-Changed includes untracked files"
Emit-Check "test_slice_case_no_match_fails" ($text -match 'CASE_MATCH' -and $text -match 'no cases matched') "-Case cannot pass when no case matches"
Emit-Check "test_slice_flow_group" ($text -match '"flow"' -and $text -match 'if_compile_time' -and $text -match 'while_compile_time') "flow group alias present"
Emit-Check "test_slice_m18h_group" ($text -match '"m18h"' -and $text -match 'test_slice_self') "M18H group present"
Emit-Check "test_slice_m18i_group" ($text -match '"m18i"' -and $text -match 'strict_ir') "M18I group present"
Emit-Check "test_slice_m18j_group" ($text -match '"m18j"' -and $text -match 'keyword_registry') "M18J group present"
Emit-Check "test_slice_strict_ir_tool" ($text -match 'validate_strict_ir\.ps1') "strict IR tool alias present"
Emit-Check "test_slice_keyword_tools" ($text -match 'validate_keyword_registry\.ps1' -and $text -match 'validate_parser_statement_map\.ps1') "keyword/parser registry tools present"

if ($failed) { exit 1 }
exit 0
