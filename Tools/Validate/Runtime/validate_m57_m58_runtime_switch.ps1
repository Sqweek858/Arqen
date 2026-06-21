param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M57M58"
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
    try { [void]$p.Start() } catch { return @{ ExitCode = 999999; Stdout = ""; Stderr = $_.Exception.Message; TimedOut = $false; StartFailed = $true } }
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
            Add-Result "PASS" "m57m58_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m57m58_driver_build" "dotnet publish failed; see Build\M57M58\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m57m58_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M56_M60.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('runtime switch enum') -and $docText.Contains('runtime switch int') -and $docText.Contains('__switch_match_')) { "PASS" } else { "FAIL" })) "m57m58_docs_runtime_switch" "Docs\Milestones\\M56_M60.md documents M57/M58"

$spec = Join-Path $RepoRoot "Tests\CommandTests\misc\runtime_switch.command.txt"
$specText = if (Test-Path $spec) { Get-Content $spec -Raw } else { "" }
Add-Result ($(if ($specText.Contains('COMMAND_ID|runtime_switch') -and $specText.Contains('MILESTONE|M57_M58') -and $specText.Contains('runtime switch enum') -and $specText.Contains('runtime switch int')) { "PASS" } else { "FAIL" })) "m57m58_spec_runtime_switch" "Tests\CommandTests\misc\runtime_switch.command.txt records M57/M58"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m57m58') -and $slice.Contains('runtime_switch')) { "PASS" } else { "FAIL" })) "m57m58_slice_aliases" "run_test_slice exposes m57m58/m57/m58"

$Cases = @(
    @{ Name='runtime_switch_enum_basic'; BuildExit=0; RunExit=0; ExpectStdout="moving`n"; RequireIr='target=__switch_match_1,runtime_if_int|path=eq|value_kind=static|value=1|target=__enum_state'; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define runtime enum "state" from "ActorState" be "Moving"
runtime switch enum "state"
case "Idle"
print string "idle"
case "Moving"
print string "moving"
case "Dead"
print string "dead"
end switch
'@ },
    @{ Name='runtime_switch_enum_default'; BuildExit=0; RunExit=0; ExpectStdout="fallback`n"; RequireIr='runtime_if_bool|path=eq|value_kind=static|value=false|target=__switch_match_1'; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define runtime enum "state" from "ActorState" be "Dead"
runtime switch enum "state"
case "Idle"
print string "idle"
case "Moving"
print string "moving"
default
print string "fallback"
end switch
'@ },
    @{ Name='runtime_switch_int_basic'; BuildExit=0; RunExit=0; ExpectStdout="run`n"; RequireIr='runtime_if_int|path=eq|value_kind=static|value=1|target=mode'; Body=@'
define runtime int called "mode" be 1
runtime switch int "mode"
case 0
print string "boot"
case 1
print string "run"
case 2
print string "shutdown"
end switch
'@ },
    @{ Name='runtime_switch_int_default'; BuildExit=0; RunExit=0; ExpectStdout="invalid`n"; RequireIr='runtime_if_bool|path=eq|value_kind=static|value=false|target=__switch_match_1'; Body=@'
define runtime int called "mode" be 9
runtime switch int "mode"
case 0
print string "boot"
case 1
print string "run"
default
print string "invalid"
end switch
'@ },
    @{ Name='runtime_switch_nested'; BuildExit=0; RunExit=0; ExpectStdout="outer`ninner`n"; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define runtime enum "state" from "ActorState" be "Moving"
define runtime int called "mode" be 2
runtime switch enum "state"
case "Idle"
print string "idle"
case "Moving"
print string "outer"
runtime switch int "mode"
case 2
print string "inner"
default
print string "bad"
end switch
end switch
'@ },
    @{ Name='runtime_switch_enum_unknown_case_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define runtime enum "state" from "ActorState" be "Idle"
runtime switch enum "state"
case "Dead"
print string "dead"
end switch
'@ },
    @{ Name='runtime_switch_enum_duplicate_case_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define runtime enum "state" from "ActorState" be "Idle"
runtime switch enum "state"
case "Idle"
print string "one"
case "Idle"
print string "two"
end switch
'@ },
    @{ Name='runtime_switch_duplicate_default_negative'; BuildExit=1; Body=@'
define runtime int called "mode" be 0
runtime switch int "mode"
default
print string "a"
default
print string "b"
end switch
'@ },
    @{ Name='runtime_switch_case_after_default_negative'; BuildExit=1; Body=@'
define runtime int called "mode" be 0
runtime switch int "mode"
default
print string "a"
case 0
print string "b"
end switch
'@ },
    @{ Name='runtime_switch_int_duplicate_case_negative'; BuildExit=1; Body=@'
define runtime int called "mode" be 0
runtime switch int "mode"
case 1
print string "a"
case 1
print string "b"
end switch
'@ },
    @{ Name='runtime_switch_int_unknown_slot_negative'; BuildExit=1; Body=@'
runtime switch int "missing"
case 0
print string "zero"
end switch
'@ },
    @{ Name='runtime_switch_missing_end_negative'; BuildExit=1; Body=@'
define runtime int called "mode" be 0
runtime switch int "mode"
case 0
print string "zero"
'@ }
)

foreach ($Case in $Cases) {
    $src = Join-Path $SourceDir ($Case.Name + '.arq')
    $bin = Join-Path $BinDir ($Case.Name + '.exe')
    $program = New-Program $Case.Name $Case.Body
    Write-TextFile $src $program

    Push-Location $RepoRoot
    try { & $Driver $src -o $bin *> (Join-Path $LogDir ($Case.Name + '.build.log')); $buildExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE } } finally { Pop-Location }
    Add-Result ($(if ($buildExit -eq $Case.BuildExit) { 'PASS' } else { 'FAIL' })) "m57m58_build_$($Case.Name)" "exit=$buildExit expected=$($Case.BuildExit)"

    $irPath = Join-Path $RepoRoot "Build\IR\$($Case.Name).arqir"
    $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { "" }
    if ($Case.ContainsKey('RequireIr') -and $Case.BuildExit -eq 0) {
        foreach ($needle in ($Case.RequireIr -split ',')) {
            $safe = ($needle -replace '[^A-Za-z0-9_]+','_').Trim('_')
            Add-Result ($(if ($irText.Contains($needle)) { 'PASS' } else { 'FAIL' })) "m57m58_ir_$($Case.Name)_$safe" "$needle present"
        }
    }

    if ($buildExit -eq 0 -and $Case.ContainsKey('RunExit')) {
        $caseRunDir = Join-Path $RunDir $Case.Name
        New-Item -ItemType Directory -Force $caseRunDir | Out-Null
        Copy-Item $bin (Join-Path $caseRunDir 'run.exe') -Force
        $run = Invoke-Exe (Join-Path $caseRunDir 'run.exe') $caseRunDir $TimeoutSeconds
        Write-TextFile (Join-Path $LogDir ($Case.Name + '.stdout.txt')) $run.Stdout
        Write-TextFile (Join-Path $LogDir ($Case.Name + '.stderr.txt')) $run.Stderr
        Add-Result ($(if ($run.ExitCode -eq $Case.RunExit) { 'PASS' } else { 'FAIL' })) "m57m58_run_$($Case.Name)" "exit=$($run.ExitCode) expected=$($Case.RunExit)"
        if ($Case.ContainsKey('ExpectStdout')) {
            Add-Result ($(if ($run.Stdout -eq $Case.ExpectStdout) { 'PASS' } else { 'FAIL' })) "m57m58_stdout_$($Case.Name)" "bytes=$($run.Stdout.Length) expected_bytes=$($Case.ExpectStdout.Length) stdout=Build\M57M58\Logs\$($Case.Name).stdout.txt"
        }
    }
}

$outPath = Join-Path $GeneratedDir "m57m58_runtime_switch_validation.txt"
Write-TextFile $outPath (($Results -join "`n") + "`n")
Write-Host "OUT|Build\Generated\m57m58_runtime_switch_validation.txt"

if ($Results | Where-Object { $_ -like 'FAIL|*' }) { exit 1 }
exit 0
