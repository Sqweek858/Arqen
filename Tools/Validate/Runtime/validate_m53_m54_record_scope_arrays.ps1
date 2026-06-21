param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M53M54"
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
            Add-Result "PASS" "m53m54_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m53m54_driver_build" "dotnet publish failed; see Build\M53M54\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m53m54_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M51_M55.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('local runtime records') -and $docText.Contains('runtime record parameters') -and $docText.Contains('runtime record arrays')) { "PASS" } else { "FAIL" })) "m53m54_docs_record_scope_arrays" "Docs\Milestones\\M51_M55.md documents M53/M54"

$spec = Join-Path $RepoRoot "Tests\CommandTests\misc\runtime_record_scope_arrays.command.txt"
$specText = if (Test-Path $spec) { Get-Content $spec -Raw } else { "" }
Add-Result ($(if ($specText.Contains('COMMAND_ID|runtime_record_scope_arrays') -and $specText.Contains('MILESTONE|M53_M54') -and $specText.Contains('define runtime record array')) { "PASS" } else { "FAIL" })) "m53m54_spec_record_scope_arrays" "Tests\CommandTests\misc\runtime_record_scope_arrays.command.txt records M53/M54"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m53m54') -and $slice.Contains('record_scope_arrays')) { "PASS" } else { "FAIL" })) "m53m54_slice_aliases" "run_test_slice exposes m53m54/m53/m54"

$registryGenerator = Join-Path $RepoRoot 'Tools\Generate\generate_runtime_action_registry.ps1'
if (Test-Path $registryGenerator) {
    Push-Location $RepoRoot
    try { & $registryGenerator *> (Join-Path $LogDir 'runtime_action_registry.build.log'); $registryExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE } } finally { Pop-Location }
    Add-Result ($(if ($registryExit -eq 0) { 'PASS' } else { 'FAIL' })) "m53m54_runtime_action_registry_generation" "exit=$registryExit log=Build\M53M54\Logs\runtime_action_registry.build.log"
} else { Add-Result 'FAIL' 'm53m54_runtime_action_registry_generation' 'Tools\Generate\generate_runtime_action_registry.ps1 missing' }

$catalogValidator = Join-Path $RepoRoot 'Tools\Validate\Core\validate_runtime_action_catalog.ps1'
if (Test-Path $catalogValidator) {
    Push-Location $RepoRoot
    try { & $catalogValidator *> (Join-Path $LogDir 'runtime_action_catalog.build.log'); $catalogExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE } } finally { Pop-Location }
    Add-Result ($(if ($catalogExit -eq 0) { 'PASS' } else { 'FAIL' })) "m53m54_runtime_action_catalog_validation" "exit=$catalogExit log=Build\M53M54\Logs\runtime_action_catalog.build.log"
} else { Add-Result 'FAIL' 'm53m54_runtime_action_catalog_validation' 'Tools\Validate\Core\validate_runtime_action_catalog.ps1 missing' }

$Cases = @(
    @{ Name='runtime_local_record_return'; BuildExit=0; RunExit=0; ExpectStdout="42`n"; RequireIr='FUNCTION|name=make_hp,__rec___fn_make_hp_local_rec_npc_hp,value=__rec___fn_make_hp_local_rec_npc_hp|target=__fn_make_hp_local_tmp'; Body=@'
define record called "Actor" with runtime int field "hp", runtime string field "name"

define function called "make_hp"
define local runtime record "npc" from "Actor"
set runtime record "npc" field "hp" to 42
define local runtime int called "tmp" be 0
set runtime int "tmp" to runtime record "npc" field "hp"
return runtime int "tmp"
end function

define runtime int called "out" be 0
set runtime int "out" to call function "make_hp"
print "out"
'@ },
    @{ Name='runtime_record_param_copyback'; BuildExit=0; RunExit=0; ExpectStdout="95`n"; RequireIr='params=record:Actor:target:__fn_damage_param_rec_target,value=__rec_player_hp|target=__rec___fn_damage_param_rec_target_hp,value=__rec___fn_damage_param_rec_target_hp|target=__rec_player_hp'; Body=@'
define record called "Actor" with runtime int field "hp"
define runtime record "player" from "Actor"
set runtime record "player" field "hp" to 100

define function called "damage" with runtime record "target" from "Actor"
define local runtime int called "hp" be 0
set runtime int "hp" to runtime record "target" field "hp"
remove 5 from "hp"
set runtime record "target" field "hp" to runtime int "hp"
end function

call function "damage" with runtime record "player"
define runtime int called "out" be 0
set runtime int "out" to runtime record "player" field "hp"
print "out"
'@ },
    @{ Name='runtime_record_array_static_fields'; BuildExit=0; RunExit=0; ExpectStdout="77`nCore`n"; RequireIr='__recarr_actors_0_hp,__recarr_actors_1_hp,__recarr_actors_1_name,value=__recarr_actors_1_hp|target=hp_out,value=__recarr_actors_1_name|target=name_out'; Body=@'
define record called "Actor" with runtime int field "hp", runtime string field "name"
define runtime record array called "actors" from "Actor" size 2
set runtime record array "actors" at 1 field "hp" to 77
set runtime record array "actors" at 1 field "name" to string "Core"
define runtime int called "hp_out" be 0
define runtime string called "name_out" be string ""
set runtime int "hp_out" to runtime record array "actors" at 1 field "hp"
set runtime string "name_out" to runtime record array "actors" at 1 field "name"
print "hp_out"
print "name_out"
'@ },
    @{ Name='runtime_record_array_dynamic_index'; BuildExit=0; RunExit=0; ExpectStdout="Drone`n"; RequireIr='runtime_trap_if_bool_false,__arr_actors_bounds_ok_,__arr_actors_index_,runtime_if_int|path=eq|value_kind=static|value=1,value=__recarr_actors_1_name|target=out'; Body=@'
define record called "Actor" with runtime string field "name"
define runtime record array called "actors" from "Actor" size 2
define runtime int called "i" be 1
set runtime record array "actors" at runtime int "i" field "name" to string "Drone"
define runtime string called "out" be string ""
set runtime string "out" to runtime record array "actors" at runtime int "i" field "name"
print "out"
'@ },
    @{ Name='runtime_record_array_dynamic_bounds_trap'; BuildExit=0; RunExit=1; ExpectStdout=""; RequireIr='runtime_trap_if_bool_false'; Body=@'
define record called "Actor" with runtime int field "hp"
define runtime record array called "actors" from "Actor" size 2
define runtime int called "i" be 3
set runtime record array "actors" at runtime int "i" field "hp" to 1
'@ },
    @{ Name='runtime_local_record_outside_negative'; BuildExit=1; Body=@'
define record called "Actor" with runtime int field "hp"
define local runtime record "npc" from "Actor"
'@ },
    @{ Name='runtime_record_param_wrong_type_negative'; BuildExit=1; Body=@'
define record called "Actor" with runtime int field "hp"
define record called "Stats" with runtime int field "score"
define runtime record "stats" from "Stats"

define function called "damage" with runtime record "target" from "Actor"
end function

call function "damage" with runtime record "stats"
'@ },
    @{ Name='runtime_record_array_wrong_field_type_negative'; BuildExit=1; Body=@'
define record called "Actor" with runtime int field "hp"
define runtime record array called "actors" from "Actor" size 2
define runtime string called "out" be string ""
set runtime string "out" to runtime record array "actors" at 0 field "hp"
'@ },
    @{ Name='runtime_record_array_unknown_field_negative'; BuildExit=1; Body=@'
define record called "Actor" with runtime int field "hp"
define runtime record array called "actors" from "Actor" size 2
set runtime record array "actors" at 0 field "name" to string "bad"
'@ }
)

foreach ($case in $Cases) {
    $src = Join-Path $SourceDir ($case.Name + '.arq')
    $bin = Join-Path $BinDir ($case.Name + '.exe')
    $program = New-Program $case.Name $case.Body
    Write-TextFile $src $program

    Push-Location $RepoRoot
    try { & $Driver $src -o $bin *> (Join-Path $LogDir ($case.Name + '.build.log')); $buildExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE } } finally { Pop-Location }
    Add-Result ($(if ($buildExit -eq $case.BuildExit) { 'PASS' } else { 'FAIL' })) "m53m54_build_$($case.Name)" "exit=$buildExit expected=$($case.BuildExit)"

    $irPath = Join-Path $RepoRoot "Build\IR\$($case.Name).arqir"
    $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { "" }
    if ($case.ContainsKey('RequireIr') -and $case.BuildExit -eq 0) {
        foreach ($needle in ($case.RequireIr -split ',')) {
            $safe = ($needle -replace '[^A-Za-z0-9_]+','_').Trim('_')
            Add-Result ($(if ($irText.Contains($needle)) { 'PASS' } else { 'FAIL' })) "m53m54_ir_$($case.Name)_$safe" "$needle present"
        }
    }

    if ($buildExit -eq 0 -and $case.ContainsKey('RunExit')) {
        $caseRunDir = Join-Path $RunDir $case.Name
        New-Item -ItemType Directory -Force $caseRunDir | Out-Null
        Copy-Item $bin (Join-Path $caseRunDir 'run.exe') -Force
        $run = Invoke-Exe (Join-Path $caseRunDir 'run.exe') $caseRunDir $TimeoutSeconds
        Write-TextFile (Join-Path $LogDir ($case.Name + '.stdout.txt')) $run.Stdout
        Write-TextFile (Join-Path $LogDir ($case.Name + '.stderr.txt')) $run.Stderr
        Add-Result ($(if ($run.ExitCode -eq $case.RunExit) { 'PASS' } else { 'FAIL' })) "m53m54_run_$($case.Name)" "exit=$($run.ExitCode) expected=$($case.RunExit)"
        if ($case.ContainsKey('ExpectStdout')) {
            Add-Result ($(if ($run.Stdout -eq $case.ExpectStdout) { 'PASS' } else { 'FAIL' })) "m53m54_stdout_$($case.Name)" "bytes=$($run.Stdout.Length) expected_bytes=$($case.ExpectStdout.Length) stdout=Build\M53M54\Logs\$($case.Name).stdout.txt"
        }
    }
}

$outPath = Join-Path $GeneratedDir "m53m54_record_scope_arrays_validation.txt"
Write-TextFile $outPath (($Results -join "`n") + "`n")
Write-Host "OUT|Build\Generated\m53m54_record_scope_arrays_validation.txt"

if ($Results | Where-Object { $_ -like 'FAIL|*' }) { exit 1 }
exit 0
