param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M37ABC"
$SourceDir = Join-Path $OutRoot "Sources"
$BinDir = Join-Path $OutRoot "Bin"
$RunDir = Join-Path $OutRoot "Run"
$LogDir = Join-Path $OutRoot "Logs"
$GeneratedDir = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force $SourceDir,$BinDir,$RunDir,$LogDir,$GeneratedDir | Out-Null

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$Results = New-Object System.Collections.Generic.List[string]

function Add-Result {
    param([string]$Status,[string]$Name,[string]$Note = "")
    $line = if ($Note -eq "") { "$Status|$Name" } else { "$Status|$Name|$Note" }
    $Results.Add($line) | Out-Null
    Write-Host $line
}

function Write-TextFile {
    param([string]$Path,[string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Invoke-Exe {
    param([string]$Exe,[string]$WorkingDirectory,[int]$Timeout)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Exe
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::new()
    $p.StartInfo = $psi
    try {
        [void]$p.Start()
    } catch {
        return @{ ExitCode = 999999; Stdout = ""; Stderr = $_.Exception.Message; TimedOut = $false; StartFailed = $true }
    }
    $stdoutTask = $p.StandardOutput.ReadToEndAsync()
    $stderrTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($Timeout * 1000)) {
        try { $p.Kill() } catch {}
        return @{ ExitCode = 999998; Stdout = $stdoutTask.Result; Stderr = $stderrTask.Result; TimedOut = $true; StartFailed = $false }
    }
    return @{ ExitCode = $p.ExitCode; Stdout = $stdoutTask.Result; Stderr = $stderrTask.Result; TimedOut = $false; StartFailed = $false }
}

function New-Program {
    param([string]$Name,[string]$Body)
@"
program "$Name"

$Body

blend mix to code 0

end program "$Name"
"@
}

if (-not $NoBuildDriver) {
    $publishLog = Join-Path $LogDir "driver_publish.log"
    Push-Location $RepoRoot
    try {
        & dotnet publish ".\Tools\M10GDriver\ArqcM10G.csproj" -c Release -o ".\Tools\M10GDriver\publish" *> $publishLog
        if ($LASTEXITCODE -eq 0) {
            Copy-Item ".\Tools\M10GDriver\publish\arqc_m10g.exe" ".\Tools\arqc_m10g.exe" -Force
            Add-Result "PASS" "m37abc_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m37abc_driver_build" "dotnet publish failed; see Build\M37ABC\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m37abc_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M36_M40.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('runtime_string_concat') -and $docText.Contains('runtime_string_substring') -and $docText.Contains('runtime_int_parse') -and $docText.Contains('contains')) { "PASS" } else { "FAIL" })) "m37c_docs_runtime_string_data" "Docs\Milestones\\M36_M40.md documents M37 string/data utilities"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m37abc') -and $slice.Contains('runtime_string_data')) { "PASS" } else { "FAIL" })) "m37c_slice_aliases" "run_test_slice exposes m37abc/m37a/m37b/m37c"

$Cases = @(
    @{ Name="runtime_string_contains_and_casefold"; ExpectExit=0; ExpectStdout="contains`nfold`nnot fold`n"; Body=@'
define runtime string called "status" be string "thermal bloom ready"
runtime if "status" contains string "bloom"
print string "contains"
end if
set runtime string "status" to string "BOOT"
runtime if "status" equals string "boot" ignoring case
print string "fold"
end if
runtime if "status" is not string "sleep" ignoring case
print string "not fold"
end if
'@ },
    @{ Name="runtime_string_concat_and_substring"; ExpectExit=0; ExpectStdout="Cryblo`nryb`ncore-alpha`n"; Body=@'
define runtime string called "left" be string "Cry"
define runtime string called "right" be string "blo"
define runtime string called "full" be string ""
set runtime string "full" to "left" + "right"
print "full"
define runtime string called "part" be string ""
set runtime string "part" to substring "full" from 1 length 3
print "part"
set runtime string "full" to string "core-" + string "alpha"
print "full"
'@ },
    @{ Name="runtime_parse_int_from_string"; ExpectExit=0; ExpectStdout="-7`n42`n"; Body=@'
define runtime string called "raw" be string "-12"
define runtime int called "value" be 0
set runtime int "value" to parse int from "raw"
add 5 to "value"
print "value"
set runtime int "value" to parse int from string "42"
print "value"
'@ },
    @{ Name="runtime_string_contains_rejects_int_rhs_negative"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime string called "status" be string "ready"
define runtime int called "code" be 7
runtime if "status" contains "code"
print string "bad"
end if
'@ },
    @{ Name="runtime_string_contains_ignoring_case_reserved_negative"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime string called "status" be string "READY"
runtime if "status" contains string "ready" ignoring case
print string "bad"
end if
'@ },
    @{ Name="runtime_string_concat_rejects_bool_rhs_negative"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime string called "name" be string "core"
define runtime bool called "flag" be true
set runtime string "name" to "name" + "flag"
'@ },
    @{ Name="runtime_string_substring_rejects_int_source_negative"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime int called "count" be 123
define runtime string called "part" be string ""
set runtime string "part" to substring "count" from 0 length 2
'@ },
    @{ Name="runtime_parse_int_rejects_bool_source_negative"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime bool called "flag" be true
define runtime int called "value" be 0
set runtime int "value" to parse int from "flag"
'@ }
)

foreach ($case in $Cases) {
    $sourcePath = Join-Path $SourceDir ($case["Name"] + ".arq")
    $exePath = Join-Path $BinDir ($case["Name"] + ".exe")
    $runCaseDir = Join-Path $RunDir $case["Name"]
    New-Item -ItemType Directory -Force $runCaseDir | Out-Null
    Write-TextFile $sourcePath (New-Program $case["Name"] $case["Body"])

    Push-Location $RepoRoot
    try {
        & $Driver $sourcePath -o $exePath *> (Join-Path $LogDir ($case["Name"] + ".build.log"))
        $buildExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }

    if ($buildExit -ne $case["ExpectExit"]) {
        Add-Result "FAIL" ("m37abc_build_" + $case["Name"]) "exit=$buildExit expected=$($case["ExpectExit"])"
        continue
    }
    Add-Result "PASS" ("m37abc_build_" + $case["Name"]) "exit=$buildExit"

    if ($case["ExpectExit"] -ne 0) { continue }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result "FAIL" ("m37abc_run_" + $case["Name"]) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result "FAIL" ("m37abc_run_" + $case["Name"]) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq 0) { "PASS" } else { "FAIL" })) ("m37abc_run_" + $case["Name"]) "exit=$($run.ExitCode)"

    $stdoutPath = Join-Path $LogDir ($case["Name"] + ".stdout.txt")
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case["ExpectStdout"], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case["ExpectStdout"])
    Add-Result ($(if ($ok) { "PASS" } else { "FAIL" })) ("m37abc_stdout_" + $case["Name"]) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=Build\M37ABC\Logs\$($case["Name"]).stdout.txt"
}

$outPath = Join-Path $GeneratedDir "m37abc_runtime_string_data_validation.txt"
[System.IO.File]::WriteAllLines($outPath, $Results, $Utf8NoBom)
Write-Host "OUT|Build\Generated\m37abc_runtime_string_data_validation.txt"

if ($Results | Where-Object { $_.StartsWith('FAIL|') }) { exit 1 }
exit 0
