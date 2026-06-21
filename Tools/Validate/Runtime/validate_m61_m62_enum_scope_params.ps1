param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M61M62"
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
            Add-Result "PASS" "m61m62_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m61m62_driver_build" "dotnet publish failed; see Build\M61M62\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m61m62_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M61_M62.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('local runtime enum') -and $docText.Contains('local runtime enum array') -and $docText.Contains('enum array parameters') -and $docText.Contains('copy-in/copy-back')) { "PASS" } else { "FAIL" })) "m61m62_docs_enum_scope_params" "Docs\Milestones\\M61_M62.md documents M61/M62"

$spec = Join-Path $RepoRoot "Tests\CommandTests\misc\runtime_enum_scope_params.command.txt"
$specText = if (Test-Path $spec) { Get-Content $spec -Raw } else { "" }
Add-Result ($(if ($specText.Contains('COMMAND_ID|runtime_enum_scope_params') -and $specText.Contains('MILESTONE|M61_M62') -and $specText.Contains('define local runtime enum') -and $specText.Contains('runtime enum array "states"')) { "PASS" } else { "FAIL" })) "m61m62_spec_enum_scope_params" "Tests\CommandTests\misc\runtime_enum_scope_params.command.txt records M61/M62"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m61m62') -and $slice.Contains('enum_scope_params')) { "PASS" } else { "FAIL" })) "m61m62_slice_aliases" "run_test_slice exposes m61m62/m61/m62"

$Cases = @(
    @{ Name='local_enum_return'; BuildExit=0; RunExit=0; ExpectStdout="moving`n"; RequireIr='locals=enum:ActorState:state:__fn_pickState_local_state,function_return_int|path=|value_kind=slot|value=__fn_pickState_local_state'; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define function called "pickState"
define local runtime enum "state" from "ActorState" be "Idle"
set runtime enum "state" to "Moving"
return runtime enum "state"
end function
define runtime enum "out" from "ActorState" be "Idle"
set runtime enum "out" to call function "pickState"
runtime switch enum "out"
case "Moving"
print string "moving"
default
print string "bad"
end switch
'@ },
    @{ Name='local_enum_called_form'; BuildExit=0; RunExit=0; ExpectStdout="dead`n"; RequireIr='locals=enum:ActorState:state:__fn_pickDead_local_state,function_return_int|path=|value_kind=slot|value=__fn_pickDead_local_state'; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define function called "pickDead"
define local runtime enum called "state" from "ActorState" be "Dead"
return runtime enum "state"
end function
define runtime enum "out" from "ActorState" be "Idle"
set runtime enum "out" to call function "pickDead"
runtime switch enum "out"
case "Dead"
print string "dead"
default
print string "bad"
end switch
'@ },
    @{ Name='local_enum_array_pick'; BuildExit=0; RunExit=0; ExpectStdout="3`ndead`n"; RequireIr='locals=enum_array:ActorState:states:__fn_pickFromLocalArray_local_arr_states,target=__enumarr___fn_pickFromLocalArray_local_arr_states_2'; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define function called "pickFromLocalArray"
define local runtime enum array called "states" from "ActorState" size 3
define local runtime enum "out" from "ActorState" be "Idle"
define local runtime int called "len" be 0
set runtime enum array "states" at 0 to "Idle"
set runtime enum array "states" at 1 to "Moving"
set runtime enum array "states" at 2 to "Dead"
set runtime enum "out" to runtime enum array "states" at 2
set runtime int "len" to length of runtime enum array "states"
print "len"
return runtime enum "out"
end function
define runtime enum "out" from "ActorState" be "Idle"
set runtime enum "out" to call function "pickFromLocalArray"
runtime switch enum "out"
case "Dead"
print string "dead"
default
print string "bad"
end switch
'@ },
    @{ Name='enum_array_param_copyback'; BuildExit=0; RunExit=0; ExpectStdout="dead`n"; RequireIr='params=enum_array:ActorState:states:__fn_markDead_param_arr_states:3,target=__enumarr___fn_markDead_param_arr_states_1,target=__enumarr_partyStates_1'; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define function called "markDead" with runtime enum array "states" from "ActorState" size 3
set runtime enum array "states" at 1 to "Dead"
end function
define runtime enum array called "partyStates" from "ActorState" size 3
define runtime enum "out" from "ActorState" be "Idle"
fill runtime enum array "partyStates" with "Idle"
call function "markDead" with runtime enum array "partyStates"
set runtime enum "out" to runtime enum array "partyStates" at 1
runtime switch enum "out"
case "Dead"
print string "dead"
default
print string "bad"
end switch
'@ },
    @{ Name='enum_array_param_return'; BuildExit=0; RunExit=0; ExpectStdout="moving`n"; RequireIr='FUNCTION|name=pickParty|return=enum:ActorState|params=enum_array:ActorState:states:__fn_pickParty_param_arr_states:3,function_return_int|path=|value_kind=slot|value=__fn_pickParty_local_out'; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define function called "pickParty" with runtime enum array "states" from "ActorState" size 3
define local runtime enum "out" from "ActorState" be "Idle"
set runtime enum "out" to runtime enum array "states" at 2
return runtime enum "out"
end function
define runtime enum array called "partyStates" from "ActorState" size 3
define runtime enum "out" from "ActorState" be "Idle"
fill runtime enum array "partyStates" with "Idle"
set runtime enum array "partyStates" at 2 to "Moving"
set runtime enum "out" to call function "pickParty" with runtime enum array "partyStates"
runtime switch enum "out"
case "Moving"
print string "moving"
default
print string "bad"
end switch
'@ },
    @{ Name='local_enum_outside_function_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define local runtime enum "state" from "ActorState" be "Idle"
'@ },
    @{ Name='local_enum_unknown_type_negative'; BuildExit=1; Body=@'
define function called "bad"
define local runtime enum "state" from "MissingState" be "Idle"
end function
'@ },
    @{ Name='local_enum_array_duplicate_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define function called "bad"
define local runtime enum "state" from "ActorState" be "Idle"
define local runtime enum array called "state" from "ActorState" size 2
end function
'@ },
    @{ Name='enum_array_param_type_mismatch_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define enum called "DoorState" with "Open", "Closed"
define function called "touchActors" with runtime enum array "states" from "ActorState" size 2
set runtime enum array "states" at 0 to "Moving"
end function
define runtime enum array called "doors" from "DoorState" size 2
call function "touchActors" with runtime enum array "doors"
'@ },
    @{ Name='enum_array_param_size_mismatch_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define function called "touchActors" with runtime enum array "states" from "ActorState" size 3
set runtime enum array "states" at 0 to "Moving"
end function
define runtime enum array called "actors" from "ActorState" size 2
call function "touchActors" with runtime enum array "actors"
'@ },
    @{ Name='enum_array_param_shadow_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define runtime enum array called "states" from "ActorState" size 2
define function called "bad" with runtime enum array "states" from "ActorState" size 2
end function
'@ }
)

foreach ($Case in $Cases) {
    $src = Join-Path $SourceDir ($Case.Name + '.arq')
    $bin = Join-Path $BinDir ($Case.Name + '.exe')
    $program = New-Program $Case.Name $Case.Body
    Write-TextFile $src $program

    Push-Location $RepoRoot
    try { & $Driver $src -o $bin *> (Join-Path $LogDir ($Case.Name + '.build.log')); $buildExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE } } finally { Pop-Location }
    Add-Result ($(if ($buildExit -eq $Case.BuildExit) { 'PASS' } else { 'FAIL' })) "m61m62_build_$($Case.Name)" "exit=$buildExit expected=$($Case.BuildExit)"

    $irPath = Join-Path $RepoRoot "Build\IR\$($Case.Name).arqir"
    $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { "" }
    if ($Case.ContainsKey('RequireIr') -and $Case.BuildExit -eq 0) {
        foreach ($needle in ($Case.RequireIr -split ',')) {
            $safe = ($needle -replace '[^A-Za-z0-9_]+','_').Trim('_')
            Add-Result ($(if ($irText.Contains($needle)) { 'PASS' } else { 'FAIL' })) "m61m62_ir_$($Case.Name)_$safe" "$needle present"
        }
    }

    if ($buildExit -eq 0 -and $Case.ContainsKey('RunExit')) {
        $caseRunDir = Join-Path $RunDir $Case.Name
        New-Item -ItemType Directory -Force $caseRunDir | Out-Null
        Copy-Item $bin (Join-Path $caseRunDir 'run.exe') -Force
        $run = Invoke-Exe (Join-Path $caseRunDir 'run.exe') $caseRunDir $TimeoutSeconds
        Write-TextFile (Join-Path $LogDir ($Case.Name + '.stdout.txt')) $run.Stdout
        Write-TextFile (Join-Path $LogDir ($Case.Name + '.stderr.txt')) $run.Stderr
        Add-Result ($(if ($run.ExitCode -eq $Case.RunExit) { 'PASS' } else { 'FAIL' })) "m61m62_run_$($Case.Name)" "exit=$($run.ExitCode) expected=$($Case.RunExit)"
        if ($Case.ContainsKey('ExpectStdout')) {
            Add-Result ($(if ($run.Stdout -eq $Case.ExpectStdout) { 'PASS' } else { 'FAIL' })) "m61m62_stdout_$($Case.Name)" "bytes=$($run.Stdout.Length) expected_bytes=$($Case.ExpectStdout.Length) stdout=Build\M61M62\Logs\$($Case.Name).stdout.txt"
        }
    }
}

$outPath = Join-Path $GeneratedDir "m61m62_enum_scope_params_validation.txt"
Write-TextFile $outPath (($Results -join "`n") + "`n")
Write-Host "OUT|Build\Generated\m61m62_enum_scope_params_validation.txt"

if ($Results | Where-Object { $_ -like 'FAIL|*' }) { exit 1 }
exit 0
