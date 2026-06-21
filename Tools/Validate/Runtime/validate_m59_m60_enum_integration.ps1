param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M59M60"
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
            Add-Result "PASS" "m59m60_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m59m60_driver_build" "dotnet publish failed; see Build\M59M60\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m59m60_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M56_M60.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('enum params') -and $docText.Contains('enum returns') -and $docText.Contains('runtime enum array') -and $docText.Contains('runtime enum field')) { "PASS" } else { "FAIL" })) "m59m60_docs_enum_integration" "Docs\Milestones\\M56_M60.md documents M59/M60"

$spec = Join-Path $RepoRoot "Tests\CommandTests\misc\runtime_enum_integration.command.txt"
$specText = if (Test-Path $spec) { Get-Content $spec -Raw } else { "" }
Add-Result ($(if ($specText.Contains('COMMAND_ID|runtime_enum_integration') -and $specText.Contains('MILESTONE|M59_M60') -and $specText.Contains('function_return_int') -and $specText.Contains('define runtime enum array')) { "PASS" } else { "FAIL" })) "m59m60_spec_enum_integration" "Tests\CommandTests\misc\runtime_enum_integration.command.txt records M59/M60"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m59m60') -and $slice.Contains('enum_integration')) { "PASS" } else { "FAIL" })) "m59m60_slice_aliases" "run_test_slice exposes m59m60/m59/m60"

$Cases = @(
    @{ Name='enum_param_return_echo'; BuildExit=0; RunExit=0; ExpectStdout="moving`n"; RequireIr='FUNCTION|name=echoState|return=enum:ActorState,function_return_int,function_call_assign|path=int|value_kind=static|value=echoState|target=__enum_out'; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define function called "echoState" with runtime enum "value" from "ActorState"
return runtime enum "value"
end function
define runtime enum "state" from "ActorState" be "Moving"
define runtime enum "out" from "ActorState" be "Idle"
set runtime enum "out" to call function "echoState" with runtime enum "state"
runtime switch enum "out"
case "Moving"
print string "moving"
default
print string "bad"
end switch
'@ },
    @{ Name='enum_literal_return'; BuildExit=0; RunExit=0; ExpectStdout="dead`n"; RequireIr='FUNCTION|name=spawnState|return=enum:ActorState,function_return_int|path=|value_kind=static|value=2|target='; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define function called "spawnState"
return enum "Dead" from "ActorState"
end function
define runtime enum "out" from "ActorState" be "Idle"
set runtime enum "out" to call function "spawnState"
runtime switch enum "out"
case "Dead"
print string "dead"
default
print string "bad"
end switch
'@ },
    @{ Name='enum_record_field'; BuildExit=0; RunExit=0; ExpectStdout="dead`n"; RequireIr='runtime_int_set|path=|value_kind=static|value=2|target=__rec_actor_state'; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define record called "Actor" with runtime enum field "state" from "ActorState", runtime int field "hp"
define runtime record "actor" from "Actor"
define runtime enum "out" from "ActorState" be "Idle"
set runtime record "actor" field "state" to "Dead"
set runtime enum "out" to runtime record "actor" field "state"
runtime switch enum "out"
case "Dead"
print string "dead"
default
print string "bad"
end switch
'@ },
    @{ Name='enum_record_array_field'; BuildExit=0; RunExit=0; ExpectStdout="moving`n"; RequireIr='runtime_int_set|path=|value_kind=static|value=1|target=__recarr_actors_1_state'; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define record called "Actor" with runtime enum field "state" from "ActorState", runtime int field "hp"
define runtime record array called "actors" from "Actor" size 2
define runtime enum "out" from "ActorState" be "Idle"
set runtime record array "actors" at 1 field "state" to "Moving"
set runtime enum "out" to runtime record array "actors" at 1 field "state"
runtime switch enum "out"
case "Moving"
print string "moving"
default
print string "bad"
end switch
'@ },
    @{ Name='enum_array_static_dynamic_fill_copy_length'; BuildExit=0; RunExit=0; ExpectStdout="moving`n3`n"; RequireIr='target=__enumarr_states_1,target=__enumarr_copy_1'; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define runtime enum array called "states" from "ActorState" size 3
define runtime enum array called "copy" from "ActorState" size 3
define runtime int called "idx" be 1
define runtime int called "len" be 0
define runtime enum "out" from "ActorState" be "Idle"
fill runtime enum array "states" with "Idle"
set runtime enum array "states" at runtime int "idx" to "Moving"
copy runtime enum array "states" to runtime enum array "copy"
set runtime enum "out" to runtime enum array "copy" at 1
set runtime int "len" to length of runtime enum array "copy"
runtime switch enum "out"
case "Moving"
print string "moving"
default
print string "bad"
end switch
print "len"
'@ },
    @{ Name='enum_param_wrong_type_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define enum called "DoorState" with "Open", "Closed"
define function called "echoState" with runtime enum "value" from "ActorState"
return runtime enum "value"
end function
define runtime enum "door" from "DoorState" be "Open"
define runtime enum "out" from "ActorState" be "Idle"
set runtime enum "out" to call function "echoState" with runtime enum "door"
'@ },
    @{ Name='enum_return_wrong_assignment_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define enum called "DoorState" with "Open", "Closed"
define function called "doorState"
return enum "Open" from "DoorState"
end function
define runtime enum "out" from "ActorState" be "Idle"
set runtime enum "out" to call function "doorState"
'@ },
    @{ Name='enum_record_field_unknown_value_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define record called "Actor" with runtime enum field "state" from "ActorState"
define runtime record "actor" from "Actor"
set runtime record "actor" field "state" to "Dead"
'@ },
    @{ Name='enum_record_field_wrong_read_type_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define enum called "DoorState" with "Open", "Closed"
define record called "Actor" with runtime enum field "state" from "ActorState"
define runtime record "actor" from "Actor"
define runtime enum "door" from "DoorState" be "Open"
set runtime enum "door" to runtime record "actor" field "state"
'@ },
    @{ Name='enum_array_copy_type_mismatch_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define enum called "DoorState" with "Open", "Closed"
define runtime enum array called "actors" from "ActorState" size 2
define runtime enum array called "doors" from "DoorState" size 2
copy runtime enum array "actors" to runtime enum array "doors"
'@ },
    @{ Name='enum_array_copy_size_mismatch_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define runtime enum array called "a" from "ActorState" size 2
define runtime enum array called "b" from "ActorState" size 3
copy runtime enum array "a" to runtime enum array "b"
'@ },
    @{ Name='enum_array_unknown_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define runtime enum "out" from "ActorState" be "Idle"
set runtime enum "out" to runtime enum array "missing" at 0
'@ }
)

foreach ($Case in $Cases) {
    $src = Join-Path $SourceDir ($Case.Name + '.arq')
    $bin = Join-Path $BinDir ($Case.Name + '.exe')
    $program = New-Program $Case.Name $Case.Body
    Write-TextFile $src $program

    Push-Location $RepoRoot
    try { & $Driver $src -o $bin *> (Join-Path $LogDir ($Case.Name + '.build.log')); $buildExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE } } finally { Pop-Location }
    Add-Result ($(if ($buildExit -eq $Case.BuildExit) { 'PASS' } else { 'FAIL' })) "m59m60_build_$($Case.Name)" "exit=$buildExit expected=$($Case.BuildExit)"

    $irPath = Join-Path $RepoRoot "Build\IR\$($Case.Name).arqir"
    $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { "" }
    if ($Case.ContainsKey('RequireIr') -and $Case.BuildExit -eq 0) {
        foreach ($needle in ($Case.RequireIr -split ',')) {
            $safe = ($needle -replace '[^A-Za-z0-9_]+','_').Trim('_')
            Add-Result ($(if ($irText.Contains($needle)) { 'PASS' } else { 'FAIL' })) "m59m60_ir_$($Case.Name)_$safe" "$needle present"
        }
    }

    if ($buildExit -eq 0 -and $Case.ContainsKey('RunExit')) {
        $caseRunDir = Join-Path $RunDir $Case.Name
        New-Item -ItemType Directory -Force $caseRunDir | Out-Null
        Copy-Item $bin (Join-Path $caseRunDir 'run.exe') -Force
        $run = Invoke-Exe (Join-Path $caseRunDir 'run.exe') $caseRunDir $TimeoutSeconds
        Write-TextFile (Join-Path $LogDir ($Case.Name + '.stdout.txt')) $run.Stdout
        Write-TextFile (Join-Path $LogDir ($Case.Name + '.stderr.txt')) $run.Stderr
        Add-Result ($(if ($run.ExitCode -eq $Case.RunExit) { 'PASS' } else { 'FAIL' })) "m59m60_run_$($Case.Name)" "exit=$($run.ExitCode) expected=$($Case.RunExit)"
        if ($Case.ContainsKey('ExpectStdout')) {
            Add-Result ($(if ($run.Stdout -eq $Case.ExpectStdout) { 'PASS' } else { 'FAIL' })) "m59m60_stdout_$($Case.Name)" "bytes=$($run.Stdout.Length) expected_bytes=$($Case.ExpectStdout.Length) stdout=Build\M59M60\Logs\$($Case.Name).stdout.txt"
        }
    }
}

$outPath = Join-Path $GeneratedDir "m59m60_enum_integration_validation.txt"
Write-TextFile $outPath (($Results -join "`n") + "`n")
Write-Host "OUT|Build\Generated\m59m60_enum_integration_validation.txt"

if ($Results | Where-Object { $_ -like 'FAIL|*' }) { exit 1 }
exit 0
