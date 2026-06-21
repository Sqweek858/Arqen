param(
    [string]$CaseRoot = "Tests\ExpectedIR",
    [string]$Compiler = "Tools\arqc.ps1"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$caseRootPath = if ([IO.Path]::IsPathRooted($CaseRoot)) { $CaseRoot } else { Join-Path $repoRoot $CaseRoot }
$compilerPath = if ([IO.Path]::IsPathRooted($Compiler)) { $Compiler } else { Join-Path $repoRoot $Compiler }
$outDir = Join-Path $repoRoot "Build\Generated"
$outPath = Join-Path $outDir "expected_ir_validation.txt"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function RelPath {
    param([string]$Path)
    $root = ([IO.Path]::GetFullPath($repoRoot)).TrimEnd("\") + "\"
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length)
    }
    return $full
}

if (-not (Test-Path $caseRootPath)) {
    Set-Content -Path $outPath -Value @("FAIL|expected_ir_root|missing $(RelPath $caseRootPath)") -Encoding UTF8
    Write-Host "FAIL|expected_ir_root|missing $(RelPath $caseRootPath)"
    exit 1
}

$expectFiles = @(Get-ChildItem $caseRootPath -Filter "*.expected.ir" -File -Recurse | Sort-Object FullName)
if ($expectFiles.Count -eq 0) {
    Set-Content -Path $outPath -Value @("FAIL|expected_ir|no cases") -Encoding UTF8
    Write-Host "FAIL|expected_ir|no cases"
    exit 1
}

$lines = @()
$failed = $false

foreach ($expectFile in $expectFiles) {
    $caseName = [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetFileNameWithoutExtension($expectFile.Name))
    $sourcePath = Join-Path $expectFile.DirectoryName "$caseName.arq"
    if (-not (Test-Path $sourcePath)) {
        $lines += "FAIL|$caseName|missing_source|$(RelPath $sourcePath)"
        $failed = $true
        continue
    }

    Push-Location $repoRoot
    & $compilerPath $sourcePath | Out-Null
    $exit = $LASTEXITCODE
    Pop-Location

    $stem = [IO.Path]::GetFileNameWithoutExtension($sourcePath)
    $irPath = Join-Path $repoRoot "Build\IR\$stem.arqir"
    if ($exit -ne 0 -or -not (Test-Path $irPath)) {
        $lines += "FAIL|$caseName|compile_or_ir_missing|exit=$exit|source=$(RelPath $sourcePath)"
        $failed = $true
        continue
    }

    $irText = Get-Content $irPath -Raw
    $caseFailed = $false
    foreach ($raw in Get-Content $expectFile.FullName) {
        $line = $raw.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#") -or $line.StartsWith("RULE_ID|") -or $line.StartsWith("COMMAND_ID|")) {
            continue
        }
        if ($line.StartsWith("EXPECT_CONTAINS|")) {
            $needle = $line.Substring("EXPECT_CONTAINS|".Length)
            if (-not $irText.Contains($needle)) {
                $lines += "FAIL|$caseName|missing|$needle"
                $caseFailed = $true
            }
        } elseif ($line.StartsWith("EXPECT_NOT_CONTAINS|")) {
            $needle = $line.Substring("EXPECT_NOT_CONTAINS|".Length)
            if ($irText.Contains($needle)) {
                $lines += "FAIL|$caseName|forbidden|$needle"
                $caseFailed = $true
            }
        } else {
            $lines += "FAIL|$caseName|unknown_directive|$line"
            $caseFailed = $true
        }
    }

    if ($caseFailed) {
        $failed = $true
    } else {
        $lines += "PASS|$caseName|$(RelPath $sourcePath)|$(RelPath $irPath)"
    }
}

Set-Content -Path $outPath -Value $lines -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
exit $(if ($failed) { 1 } else { 0 })
