param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M35ABC"
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
            Add-Result "PASS" "m35abc_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m35abc_driver_build" "dotnet publish failed; see Build\M35ABC\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m35abc_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M31_M35.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('define runtime bool called') -and $docText.Contains('define runtime string called') -and $docText.Contains('runtime_if_bool')) { "PASS" } else { "FAIL" })) "m35c_docs_runtime_state" "Docs\Milestones\\M31_M35.md documents bool/string runtime state"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m35abc') -and $slice.Contains('runtime_state')) { "PASS" } else { "FAIL" })) "m35c_slice_aliases" "run_test_slice exposes m35abc/m35a/m35b/m35c"

$Cases = @(
    @{ Name="runtime_bool_define_set_if"; ExpectExit=0; ExpectStdout="cold`nwarm`nnot false`n"; Body=@'
define runtime bool called "ready" be false
runtime if "ready" is false
print string "cold"
end if
set runtime bool "ready" to true
runtime if "ready" is true
print string "warm"
end if
runtime if "ready" is not false
print string "not false"
end if
'@ },
    @{ Name="runtime_bool_slot_compare_copy"; ExpectExit=0; ExpectStdout="same`ndifferent`n"; Body=@'
define runtime bool called "left" be true
define runtime bool called "right" be true
runtime if "left" equals "right"
print string "same"
end if
set runtime bool "right" to false
runtime if "left" is not "right"
print string "different"
end if
'@ },
    @{ Name="runtime_string_print_set_copy"; ExpectExit=0; ExpectStdout="boot`nready`nready`n"; Body=@'
define runtime string called "status" be string "boot"
print "status"
set runtime string "status" to string "ready"
print "status"
define runtime string called "copy" be string ""
set runtime string "copy" to "status"
print "copy"
'@ },
    @{ Name="runtime_string_set_inside_bool_if_else"; ExpectExit=0; ExpectStdout="online`n"; Body=@'
define runtime bool called "enabled" be true
define runtime string called "state" be string "offline"
runtime if "enabled" is true
set runtime string "state" to string "online"
else
set runtime string "state" to string "blocked"
end if
print "state"
'@ },
    @{ Name="runtime_bool_requires_bool_literal_negative"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime bool called "flag" be string "true"
'@ },
    @{ Name="runtime_bool_rejects_int_slot_source_negative"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime bool called "flag" be false
define runtime int called "count" be 1
set runtime bool "flag" to "count"
'@ },
    @{ Name="runtime_string_rejects_bool_literal_negative"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime string called "status" be string "boot"
set runtime string "status" to true
'@ },
    @{ Name="runtime_if_rejects_string_condition_negative"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime string called "status" be string "boot"
runtime if "status" is true
print string "bad"
end if
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
        Add-Result "FAIL" ("m35abc_build_" + $case["Name"]) "exit=$buildExit expected=$($case["ExpectExit"])"
        continue
    }
    Add-Result "PASS" ("m35abc_build_" + $case["Name"]) "exit=$buildExit"

    if ($case["ExpectExit"] -ne 0) { continue }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result "FAIL" ("m35abc_run_" + $case["Name"]) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result "FAIL" ("m35abc_run_" + $case["Name"]) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq 0) { "PASS" } else { "FAIL" })) ("m35abc_run_" + $case["Name"]) "exit=$($run.ExitCode)"

    $stdoutPath = Join-Path $LogDir ($case["Name"] + ".stdout.txt")
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case["ExpectStdout"], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case["ExpectStdout"])
    Add-Result ($(if ($ok) { "PASS" } else { "FAIL" })) ("m35abc_stdout_" + $case["Name"]) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=Build\M35ABC\Logs\$($case["Name"]).stdout.txt"
}

$outPath = Join-Path $GeneratedDir "m35abc_runtime_state_validation.txt"
[System.IO.File]::WriteAllLines($outPath, $Results, $Utf8NoBom)
Write-Host "OUT|Build\Generated\m35abc_runtime_state_validation.txt"

if ($Results | Where-Object { $_.StartsWith('FAIL|') }) { exit 1 }
exit 0
