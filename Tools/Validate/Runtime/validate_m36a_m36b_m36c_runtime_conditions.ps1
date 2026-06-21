param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M36ABC"
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
            Add-Result "PASS" "m36abc_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m36abc_driver_build" "dotnet publish failed; see Build\M36ABC\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m36abc_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M36_M40.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('runtime_if_string') -and $docText.Contains('runtime_bool_not_set') -and $docText.Contains('runtime_bool_toggle')) { "PASS" } else { "FAIL" })) "m36c_docs_runtime_conditions" "Docs\Milestones\\M36_M40.md documents M36 runtime conditions"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m36abc') -and $slice.Contains('runtime_conditions')) { "PASS" } else { "FAIL" })) "m36c_slice_aliases" "run_test_slice exposes m36abc/m36a/m36b/m36c"

$Cases = @(
    @{ Name="runtime_string_comparison_static_and_slot"; ExpectExit=0; ExpectStdout="boot`nnot boot`nslot ready`n"; Body=@'
define runtime string called "mode" be string "boot"
runtime if "mode" equals string "boot"
print string "boot"
end if
set runtime string "mode" to string "ready"
runtime if "mode" is not string "boot"
print string "not boot"
end if
define runtime string called "expected" be string "ready"
runtime if "mode" equals "expected"
print string "slot ready"
end if
'@ },
    @{ Name="runtime_bool_not_set_literal_and_slot"; ExpectExit=0; ExpectStdout="disabled`nmirror`nliteral`n"; Body=@'
define runtime bool called "enabled" be true
define runtime bool called "mirror" be false
set runtime bool "enabled" to not "enabled"
runtime if "enabled" is false
print string "disabled"
end if
set runtime bool "mirror" to not "enabled"
runtime if "mirror" is true
print string "mirror"
end if
set runtime bool "mirror" to not false
runtime if "mirror" is true
print string "literal"
end if
'@ },
    @{ Name="runtime_bool_toggle_basic"; ExpectExit=0; ExpectStdout="on`noff`n"; Body=@'
define runtime bool called "armed" be false
toggle runtime bool "armed"
runtime if "armed" is true
print string "on"
end if
toggle runtime bool "armed"
runtime if "armed" is false
print string "off"
end if
'@ },
    @{ Name="runtime_mixed_condition_polish"; ExpectExit=0; ExpectStdout="ready`n"; Body=@'
define runtime string called "status" be string "boot"
define runtime bool called "active" be false
runtime if "status" equals string "boot"
set runtime bool "active" to not "active"
end if
runtime if "active" is true
set runtime string "status" to string "ready"
end if
runtime if "status" equals string "ready"
print string "ready"
end if
'@ },
    @{ Name="runtime_string_rejects_bool_slot_rhs_negative"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime string called "status" be string "boot"
define runtime bool called "flag" be true
runtime if "status" equals "flag"
print string "bad"
end if
'@ },
    @{ Name="runtime_string_rejects_ordering_negative"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime string called "status" be string "boot"
runtime if "status" is less than string "ready"
print string "bad"
end if
'@ },
    @{ Name="runtime_bool_not_rejects_string_slot_negative"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime bool called "flag" be false
define runtime string called "status" be string "ready"
set runtime bool "flag" to not "status"
'@ },
    @{ Name="runtime_bool_toggle_rejects_int_slot_negative"; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime int called "count" be 1
toggle runtime bool "count"
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
        Add-Result "FAIL" ("m36abc_build_" + $case["Name"]) "exit=$buildExit expected=$($case["ExpectExit"])"
        continue
    }
    Add-Result "PASS" ("m36abc_build_" + $case["Name"]) "exit=$buildExit"

    if ($case["ExpectExit"] -ne 0) { continue }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result "FAIL" ("m36abc_run_" + $case["Name"]) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result "FAIL" ("m36abc_run_" + $case["Name"]) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq 0) { "PASS" } else { "FAIL" })) ("m36abc_run_" + $case["Name"]) "exit=$($run.ExitCode)"

    $stdoutPath = Join-Path $LogDir ($case["Name"] + ".stdout.txt")
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case["ExpectStdout"], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case["ExpectStdout"])
    Add-Result ($(if ($ok) { "PASS" } else { "FAIL" })) ("m36abc_stdout_" + $case["Name"]) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=Build\M36ABC\Logs\$($case["Name"]).stdout.txt"
}

$outPath = Join-Path $GeneratedDir "m36abc_runtime_conditions_validation.txt"
[System.IO.File]::WriteAllLines($outPath, $Results, $Utf8NoBom)
Write-Host "OUT|Build\Generated\m36abc_runtime_conditions_validation.txt"

if ($Results | Where-Object { $_.StartsWith('FAIL|') }) { exit 1 }
exit 0
