param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M34BC"
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
            Add-Result "PASS" "m34bc_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m34bc_driver_build" "dotnet publish failed; see Build\M34BC\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m34bc_driver_exists" "Tools\arqc_m10g.exe"

$Cases = @(
    @{ Name="runtime_int_add_sub_set"; ExpectExit=0; ExpectStdout="-2`n"; Body=@'
define runtime int called "x" be 1
add 4 to "x"
remove 2 from "x"
set runtime int "x" to -2
print "x"
'@ },
    @{ Name="runtime_if_less_greater"; ExpectExit=0; ExpectStdout="lt`ngt`n"; Body=@'
define runtime int called "x" be 3
runtime if "x" is less than 5
print string "lt"
end if
runtime if "x" greater than 1
print string "gt"
end if
'@ },
    @{ Name="runtime_while_counter"; ExpectExit=0; ExpectStdout="0`n1`n2`n3`n4`n"; Body=@'
define runtime int called "i" be 0
runtime while "i" is less than 5
print "i"
add 1 to "i"
end while
'@ },
    @{ Name="runtime_while_outer_false"; ExpectExit=0; ExpectStdout="after`n"; Body=@'
define runtime int called "i" be 5
runtime while "i" is less than 5
print string "bad"
add 1 to "i"
end while
print string "after"
'@ },
    @{ Name="runtime_while_with_nested_if"; ExpectExit=0; ExpectStdout="0`none`n2`n"; Body=@'
define runtime int called "i" be 0
runtime while "i" is less than 3
runtime if "i" is 1
print string "one"
else
print "i"
end if
add 1 to "i"
end while
'@ },
    @{ Name="runtime_nested_while"; ExpectExit=0; ExpectStdout="0`n1`n0`n1`n"; Body=@'
define runtime int called "outer" be 0
define runtime int called "inner" be 0
runtime while "outer" is less than 2
set runtime int "inner" to 0
runtime while "inner" is less than 2
print "inner"
add 1 to "inner"
end while
add 1 to "outer"
end while
'@ },
    @{ Name="runtime_while_static_symbol_rejected"; ExpectExit=1; ExpectStdout=$null; Body=@'
define int called "i" be 0
runtime while "i" is less than 3
print string "bad"
end while
'@ },
    @{ Name="runtime_multiply_rejected"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime int called "x" be 2
multiply "x" by 3
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
        Add-Result "FAIL" ("m34bc_build_" + $case["Name"]) "exit=$buildExit expected=$($case["ExpectExit"])"
        continue
    }
    Add-Result "PASS" ("m34bc_build_" + $case["Name"]) "exit=$buildExit"

    if ($case["ExpectExit"] -ne 0) { continue }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result "FAIL" ("m34bc_run_" + $case["Name"]) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result "FAIL" ("m34bc_run_" + $case["Name"]) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq 0) { "PASS" } else { "FAIL" })) ("m34bc_run_" + $case["Name"]) "exit=$($run.ExitCode)"

    $stdoutPath = Join-Path $LogDir ($case["Name"] + ".stdout.txt")
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case["ExpectStdout"], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case["ExpectStdout"])
    Add-Result ($(if ($ok) { "PASS" } else { "FAIL" })) ("m34bc_stdout_" + $case["Name"]) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=Build\M34BC\Logs\$($case["Name"]).stdout.txt"
}

$outPath = Join-Path $GeneratedDir "m34bc_runtime_math_while_validation.txt"
[System.IO.File]::WriteAllLines($outPath, $Results, $Utf8NoBom)
Write-Host "OUT|Build\Generated\m34bc_runtime_math_while_validation.txt"

if ($Results | Where-Object { $_.StartsWith('FAIL|') }) { exit 1 }
exit 0
