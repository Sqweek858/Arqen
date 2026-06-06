param(
    [Parameter(Mandatory=$true)]
    [string]$CommandId,
    [string]$Syntax,
    [string]$Tokens,
    [string]$Ast,
    [string]$Semantic,
    [string]$Ir,
    [string]$Backend,
    [string]$Category = "command",
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "CommandAutomationCommon.psm1") -Force

function Normalize-CommandId {
    param([string]$Value)
    $id = $Value.Trim().ToLowerInvariant() -replace '[\s-]+', '_'
    $id = $id -replace '[^a-z0-9_]', ''
    return $id.Trim("_")
}

function Require-Value {
    param([string]$Name, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-Host "ERROR|missing_$Name"
        exit 2
    }
}

function Expand-Command {
    param([string]$Text, [string]$Replacement)
    $result = $Text
    $result = $result -replace '<int>', $Replacement
    $result = $result -replace '<text-expression>', '"Hello"'
    $result = $result -replace '<string>', '"Hello"'
    $result = $result -replace '<[^>]+>', $Replacement
    return $result
}

function Write-GeneratedFile {
    param([string]$Path, [string[]]$Lines)
    if ((Test-Path $Path) -and -not $Force) {
        Write-Host "ERROR|file_exists|$(ConvertTo-ArqenRelativePath $Path)"
        exit 1
    }
    Set-Content -Path $Path -Value $Lines -Encoding UTF8
}

$id = Normalize-CommandId $CommandId
if ([string]::IsNullOrWhiteSpace($id)) {
    Write-Host "ERROR|invalid_CommandId"
    exit 2
}

Require-Value "Syntax" $Syntax
Require-Value "Tokens" $Tokens
Require-Value "Ast" $Ast
Require-Value "Semantic" $Semantic
Require-Value "Ir" $Ir
Require-Value "Backend" $Backend

if ($Category -notmatch '^[A-Za-z0-9_\-]+$') {
    Write-Host "WARN|unknown_category|$Category"
}

$root = Get-ArqenRepoRoot
$specPath = Join-Path $root "Specs\Commands\$id.command.txt"
$testDir = Join-Path $root "Tests\CommandSkeletons\$id"
$generatedDir = Join-Path (Get-ArqenGeneratedDir) "CommandSkeletons"
$touchMapPath = Join-Path $generatedDir "$id.touch_map.txt"
$checklistPath = Join-Path $generatedDir "$id.implementation_checklist.txt"

$paths = @(
    $specPath,
    $testDir,
    (Join-Path $testDir "valid_basic.arq"),
    (Join-Path $testDir "invalid_missing_code.arq"),
    (Join-Path $testDir "invalid_wrong_type.arq"),
    (Join-Path $testDir "expected.txt"),
    $touchMapPath,
    $checklistPath
)

if ($DryRun) {
    foreach ($path in $paths) {
        Write-Host "DRYRUN|would_write|$(ConvertTo-ArqenRelativePath $path)"
    }
    exit 0
}

if (Test-Path $specPath) {
    $existing = Read-ArqenCommandSpec $specPath
    $existingStatus = Get-ArqenSpecValue $existing "STATUS" "stable"
    if ($existingStatus -ne "skeleton") {
        Write-Host "ERROR|implemented_spec_exists|$(ConvertTo-ArqenRelativePath $specPath)"
        exit 1
    }
}

foreach ($path in $paths) {
    if ((Test-Path $path) -and -not $Force) {
        Write-Host "ERROR|file_exists|$(ConvertTo-ArqenRelativePath $path)"
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $specPath), $testDir, $generatedDir | Out-Null

$validCommand = Expand-Command $Syntax "0"
$missingCommand = if ($Syntax.Contains("<")) { ($Syntax -replace '\s*<[^>]+>', '') } else { ($Syntax -replace '\s+\S+$', '') }
$wrongTypeCommand = if ($Syntax.Contains("<")) { Expand-Command $Syntax "true" } else { "$Syntax true" }
$programName = ($id.Split("_") | ForEach-Object { $_.Substring(0,1).ToUpperInvariant() + $_.Substring(1) }) -join ""

Write-GeneratedFile $specPath @(
    "COMMAND $id",
    "CATEGORY $Category",
    "SYNTAX $Syntax",
    "TOKENS $Tokens",
    "AST $Ast",
    "SEMANTIC $Semantic",
    "IR $Ir",
    "BACKEND $Backend",
    "TEST_VALID Tests\CommandSkeletons\$id\valid_basic.arq",
    "TEST_INVALID Tests\CommandSkeletons\$id\invalid_missing_code.arq",
    "TEST_INVALID Tests\CommandSkeletons\$id\invalid_wrong_type.arq",
    "STATUS skeleton",
    "LIMITATIONS generated skeleton, not implemented yet"
)

Write-GeneratedFile (Join-Path $testDir "valid_basic.arq") @(
    "program `"$programName`"",
    "",
    "title `"$programName`"",
    "message text `"Skeleton only`"",
    $validCommand,
    "",
    "end program `"$programName`""
)

Write-GeneratedFile (Join-Path $testDir "invalid_missing_code.arq") @(
    "program `"Bad$programName`"",
    "title `"Bad`"",
    "message text `"Bad`"",
    $missingCommand,
    "end program `"Bad$programName`""
)

Write-GeneratedFile (Join-Path $testDir "invalid_wrong_type.arq") @(
    "program `"Bad$programName`"",
    "title `"Bad`"",
    "message text `"Bad`"",
    $wrongTypeCommand,
    "end program `"Bad$programName`""
)

Write-GeneratedFile (Join-Path $testDir "expected.txt") @(
    "valid_basic.arq|SKELETON|valid|$validCommand",
    "invalid_missing_code.arq|SKELETON|invalid|$missingCommand",
    "invalid_wrong_type.arq|SKELETON|invalid|$wrongTypeCommand"
)

& (Join-Path $PSScriptRoot "generate_command_touch_map.ps1") -CommandId $id *> $null
& (Join-Path $PSScriptRoot "generate_command_checklist.ps1") -CommandId $id *> $null

Write-Host "CREATED|spec|$(ConvertTo-ArqenRelativePath $specPath)"
Write-Host "CREATED|tests|$(ConvertTo-ArqenRelativePath $testDir)"
Write-Host "CREATED|touch_map|$(ConvertTo-ArqenRelativePath $touchMapPath)"
Write-Host "CREATED|checklist|$(ConvertTo-ArqenRelativePath $checklistPath)"
exit 0
