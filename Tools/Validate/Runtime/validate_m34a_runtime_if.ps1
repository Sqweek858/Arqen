param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M34A"
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
            Add-Result "PASS" "m34a_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m34a_driver_build" "dotnet publish failed; see Build\M34A\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m34a_driver_exists" "Tools\arqc_m10g.exe"

$Cases = @(
    @{ Name="runtime_if_true"; ExpectExit=0; ExpectStdout="hit`n"; Body=@'
define runtime int called "x" be 5
runtime if "x" is 5
print string "hit"
end if
'@ },
    @{ Name="runtime_if_false"; ExpectExit=0; ExpectStdout="after`n"; Body=@'
define runtime int called "x" be 3
runtime if "x" is 5
print string "bad"
end if
print string "after"
'@ },
    @{ Name="runtime_if_else"; ExpectExit=0; ExpectStdout="else branch`n"; Body=@'
define runtime int called "x" be 4
runtime if "x" is 5
print string "then branch"
else
print string "else branch"
end if
'@ },
    @{ Name="runtime_nested_true"; ExpectExit=0; ExpectStdout="outer`ninner`ndone`n"; Body=@'
define runtime int called "x" be 5
define runtime int called "y" be 9
runtime if "x" is 5
print string "outer"
runtime if "y" equals 9
print string "inner"
end if
print string "done"
end if
'@ },
    @{ Name="runtime_nested_outer_false"; ExpectExit=0; ExpectStdout="after`n"; Body=@'
define runtime int called "x" be 4
define runtime int called "y" be 9
runtime if "x" is 5
print string "bad outer"
runtime if "y" is 9
print string "bad inner"
end if
end if
print string "after"
'@ },
    @{ Name="runtime_if_not"; ExpectExit=0; ExpectStdout="not five`n"; Body=@'
define runtime int called "x" be 4
runtime if "x" is not 5
print string "not five"
end if
'@ },
    @{ Name="runtime_print_int_slot"; ExpectExit=0; ExpectStdout="42`n"; Body=@'
define runtime int called "x" be 42
print "x"
'@ },
    @{ Name="runtime_if_static_symbol_rejected"; ExpectExit=1; ExpectStdout=$null; Body=@'
define int called "x" be 5
runtime if "x" is 5
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
        Add-Result "FAIL" ("m34a_build_" + $case["Name"]) "exit=$buildExit expected=$($case["ExpectExit"])"
        continue
    }
    Add-Result "PASS" ("m34a_build_" + $case["Name"]) "exit=$buildExit"

    if ($case["ExpectExit"] -ne 0) { continue }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result "FAIL" ("m34a_run_" + $case["Name"]) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result "FAIL" ("m34a_run_" + $case["Name"]) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq 0) { "PASS" } else { "FAIL" })) ("m34a_run_" + $case["Name"]) "exit=$($run.ExitCode)"

    $stdoutPath = Join-Path $LogDir ($case["Name"] + ".stdout.txt")
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case["ExpectStdout"], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case["ExpectStdout"])
    Add-Result ($(if ($ok) { "PASS" } else { "FAIL" })) ("m34a_stdout_" + $case["Name"]) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=Build\M34A\Logs\$($case["Name"]).stdout.txt"
}

$outPath = Join-Path $GeneratedDir "m34a_runtime_if_validation.txt"
[System.IO.File]::WriteAllLines($outPath, $Results, $Utf8NoBom)
Write-Host "OUT|Build\Generated\m34a_runtime_if_validation.txt"

if ($Results | Where-Object { $_.StartsWith('FAIL|') }) { exit 1 }
exit 0
