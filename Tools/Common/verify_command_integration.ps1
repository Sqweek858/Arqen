param(
    [Parameter(Mandatory=$true)]
    [string]$CommandId
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
Import-Module (Join-Path $RepoRoot "Tools\Common\CommandAutomationCommon.psm1") -Force

function Normalize-CommandId {
    param([string]$Value)
    $id = $Value.Trim().ToLowerInvariant() -replace '[\s-]+', '_'
    $id = $id -replace '[^a-z0-9_]', ''
    return $id.Trim("_")
}

function Find-CommandSpec {
    param([string]$Id)
    foreach ($spec in Get-ArqenCommandSpecs) {
        $specId = Get-ArqenSpecValue $spec "COMMAND_ID" $spec.Id
        $fileId = [IO.Path]::GetFileNameWithoutExtension($spec.Path).Replace(".command", "")
        if ((Normalize-CommandId $specId) -eq $Id -or (Normalize-CommandId $spec.Id) -eq $Id -or (Normalize-CommandId $fileId) -eq $Id) {
            return $spec
        }
    }
    return $null
}

function File-Text {
    param([string]$Path)
    if (Test-Path $Path) {
        for ($i = 0; $i -lt 5; $i++) {
            try {
                return Get-Content $Path -Raw
            } catch {
                Start-Sleep -Milliseconds 100
            }
        }
        return Get-Content $Path -Raw
    }
    return ""
}

$id = Normalize-CommandId $CommandId
if ([string]::IsNullOrWhiteSpace($id)) {
    Write-Error "CommandId is required."
    exit 2
}

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outDir = Join-Path $generated "CommandSkeletons"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outPath = Join-Path $outDir "$id.integration_verification.txt"
$lines = @()
$failed = $false

& (Join-Path $root "Tools\Generate\generate_keyword_registry.ps1") *> $null
& (Join-Path $root "Tools\Generate\generate_parser_rule_registry.ps1") *> $null
& (Join-Path $root "Tools\Generate\generate_command_test_index.ps1") *> $null
& (Join-Path $root "Tools\Generate\generate_command_status.ps1") *> $null

$spec = Find-CommandSpec $id
if ($spec) {
    $lines += "PASS|spec_exists"
} else {
    $lines += "FAIL|spec_exists"
    $failed = $true
}

$statusText = File-Text (Join-Path $generated "command_status.txt")
$statusLine = @($statusText -split "`r?`n" | Where-Object { $_ -match "^COMMAND\|$([regex]::Escape($id))\|" -or $_ -match "^COMMAND\|.*\|.*status=" } | Where-Object {
    if (-not $spec) { return $false }
    $specId = Get-ArqenSpecValue $spec "COMMAND_ID" $spec.Id
    $_.StartsWith("COMMAND|$specId|") -or $_.StartsWith("COMMAND|$id|")
} | Select-Object -First 1)
$status = if ($spec) { Get-ArqenSpecValue $spec "STATUS" "stable" } else { "" }
if ($statusLine) {
    $lines += "PASS|command_status|status=$status"
} else {
    $lines += "FAIL|command_status"
    $failed = $true
}

if ($status -eq "skeleton") {
    $lines += "PASS|skeleton_status"
}

$tokens = if ($spec) { Get-ArqenSpecValue $spec "TOKENS" "" } else { "" }
$keywords = @(Get-ArqenKeywordTokens $tokens)
$keywordText = File-Text (Join-Path $generated "keyword_registry.txt")
$missingKeywords = @($keywords | Where-Object { -not $keywordText.Contains("KEYWORD|$_") })
if ($missingKeywords.Count -eq 0) {
    $lines += "PASS|keyword_registry"
} else {
    $lines += "FAIL|keyword_registry|missing=$($missingKeywords -join ',')"
    $failed = $true
}

$ruleText = File-Text (Join-Path $generated "parser_rule_registry.txt")
$specIdForRule = if ($spec) { Get-ArqenSpecValue $spec "COMMAND_ID" $spec.Id } else { $id }
if ($ruleText.Contains("RULE|$specIdForRule|") -or $ruleText.Contains("RULE|$id|")) {
    $lines += "PASS|parser_rule_registry"
} else {
    $lines += "FAIL|parser_rule_registry"
    $failed = $true
}

$validPath = if ($spec) { Get-ArqenSpecValue $spec "VALID_TEST" "" } else { "" }
$invalidPath = if ($spec) { Get-ArqenSpecValue $spec "INVALID_TEST" "" } else { "" }
$testsOk = (Test-ArqenReferencedPath $validPath) -and (Test-ArqenReferencedPath $invalidPath)
$expectedCandidates = @(
    (Join-Path $root "Tests\CommandTests\$id\expected.txt"),
    (Join-Path $root "Tests\CommandSkeletons\$id\expected.txt")
)
$expectedOk = @($expectedCandidates | Where-Object { Test-Path $_ }).Count -gt 0
if ($testsOk -and $expectedOk) {
    $lines += "PASS|tests_exist"
} else {
    $lines += "FAIL|tests_exist"
    $failed = $true
}

$runnerText = File-Text (Join-Path $root "Tools\Internal\Test\run_test_slice.ps1")
$commandTestsDir = Join-Path $root "Tests\CommandTests\$id"
if ((Test-Path $commandTestsDir) -or $runnerText.Contains($id)) {
    $lines += "PASS|test_runner_coverage"
} elseif ($status -eq "skeleton") {
    $lines += "PASS|test_runner_coverage|skeleton_not_active"
} else {
    $lines += "WARN|manual_check_required|test_runner_coverage"
}

$lines += "WARN|manual_check_required|semantic_validation"
$lines += "WARN|manual_check_required|ir_lowering"

Set-Content -Path $outPath -Value $lines -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
