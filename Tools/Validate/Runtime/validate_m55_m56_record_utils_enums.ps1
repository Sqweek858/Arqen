param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M55M56"
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
            Add-Result "PASS" "m55m56_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m55m56_driver_build" "dotnet publish failed; see Build\M55M56\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m55m56_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M51_M55.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('copy runtime record') -and $docText.Contains('reset runtime record') -and $docText.Contains('runtime enums')) { "PASS" } else { "FAIL" })) "m55m56_docs_record_utils_enums" "Docs\Milestones\\M51_M55.md documents M55/M56"

$spec = Join-Path $RepoRoot "Tests\CommandTests\misc\runtime_record_utils_enums.command.txt"
$specText = if (Test-Path $spec) { Get-Content $spec -Raw } else { "" }
Add-Result ($(if ($specText.Contains('COMMAND_ID|runtime_record_utils_enums') -and $specText.Contains('MILESTONE|M55_M56') -and $specText.Contains('define runtime enum')) { "PASS" } else { "FAIL" })) "m55m56_spec_record_utils_enums" "Tests\CommandTests\misc\runtime_record_utils_enums.command.txt records M55/M56"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m55m56') -and $slice.Contains('record_utils_enums')) { "PASS" } else { "FAIL" })) "m55m56_slice_aliases" "run_test_slice exposes m55m56/m55/m56"

$registryGenerator = Join-Path $RepoRoot 'Tools\Generate\generate_runtime_action_registry.ps1'
if (Test-Path $registryGenerator) {
    Push-Location $RepoRoot
    try { & $registryGenerator *> (Join-Path $LogDir 'runtime_action_registry.build.log'); $registryExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE } } finally { Pop-Location }
    Add-Result ($(if ($registryExit -eq 0) { 'PASS' } else { 'FAIL' })) "m55m56_runtime_action_registry_generation" "exit=$registryExit log=Build\M55M56\Logs\runtime_action_registry.build.log"
} else { Add-Result 'FAIL' 'm55m56_runtime_action_registry_generation' 'Tools\Generate\generate_runtime_action_registry.ps1 missing' }

$catalogValidator = Join-Path $RepoRoot 'Tools\Validate\Core\validate_runtime_action_catalog.ps1'
if (Test-Path $catalogValidator) {
    Push-Location $RepoRoot
    try { & $catalogValidator *> (Join-Path $LogDir 'runtime_action_catalog.build.log'); $catalogExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE } } finally { Pop-Location }
    Add-Result ($(if ($catalogExit -eq 0) { 'PASS' } else { 'FAIL' })) "m55m56_runtime_action_catalog_validation" "exit=$catalogExit log=Build\M55M56\Logs\runtime_action_catalog.build.log"
} else { Add-Result 'FAIL' 'm55m56_runtime_action_catalog_validation' 'Tools\Validate\Core\validate_runtime_action_catalog.ps1 missing' }

$Cases = @(
    @{ Name='runtime_record_copy_global'; BuildExit=0; RunExit=0; ExpectStdout="88`nCryblo`n"; RequireIr='value=__rec_source_hp|target=__rec_dest_hp,value=__rec_source_name|target=__rec_dest_name'; Body=@'
define record called "Actor" with runtime int field "hp", runtime string field "name"
define runtime record "source" from "Actor"
define runtime record "dest" from "Actor"
set runtime record "source" field "hp" to 88
set runtime record "source" field "name" to string "Cryblo"
copy runtime record "source" to runtime record "dest"
define runtime int called "hp_out" be 0
define runtime string called "name_out" be string ""
set runtime int "hp_out" to runtime record "dest" field "hp"
set runtime string "name_out" to runtime record "dest" field "name"
print "hp_out"
print "name_out"
'@ },
    @{ Name='runtime_record_reset'; BuildExit=0; RunExit=0; ExpectStdout="0`n"; RequireIr='target=__rec_player_hp,value=0|target=__rec_player_hp'; Body=@'
define record called "Actor" with runtime int field "hp", runtime bool field "alive"
define runtime record "player" from "Actor"
set runtime record "player" field "hp" to 77
set runtime record "player" field "alive" to true
reset runtime record "player"
define runtime int called "hp_out" be 1
set runtime int "hp_out" to runtime record "player" field "hp"
print "hp_out"
'@ },
    @{ Name='runtime_record_array_copy_reset'; BuildExit=0; RunExit=0; ExpectStdout="44`n0`n"; RequireIr='value=__recarr_source_1_hp|target=__recarr_dest_1_hp,value=0|target=__recarr_dest_1_hp'; Body=@'
define record called "Actor" with runtime int field "hp"
define runtime record array called "source" from "Actor" size 2
define runtime record array called "dest" from "Actor" size 2
set runtime record array "source" at 1 field "hp" to 44
copy runtime record array "source" to runtime record array "dest"
define runtime int called "out" be 0
set runtime int "out" to runtime record array "dest" at 1 field "hp"
print "out"
reset runtime record array "dest"
set runtime int "out" to runtime record array "dest" at 1 field "hp"
print "out"
'@ },
    @{ Name='runtime_enum_basic_if'; BuildExit=0; RunExit=0; ExpectStdout="moving`n"; RequireIr='target=__enum_state,value=1|target=__enum_state,runtime_if_int|path=eq|value_kind=static|value=1|target=__enum_state'; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define runtime enum "state" from "ActorState" be "Idle"
set runtime enum "state" to "Moving"
runtime if enum "state" is "Moving"
print string "moving"
end if
'@ },
    @{ Name='runtime_enum_copy_if_not'; BuildExit=0; RunExit=0; ExpectStdout="dead`n"; RequireIr='value=__enum_source|target=__enum_dest,runtime_if_int|path=ne|value_kind=static|value=0|target=__enum_dest'; Body=@'
define enum called "ActorState" with "Idle", "Moving", "Dead"
define runtime enum "source" from "ActorState" be "Dead"
define runtime enum "dest" from "ActorState" be "Idle"
set runtime enum "dest" to runtime enum "source"
runtime if enum "dest" is not "Idle"
print string "dead"
end if
'@ },
    @{ Name='runtime_record_copy_wrong_type_negative'; BuildExit=1; Body=@'
define record called "Actor" with runtime int field "hp"
define record called "Stats" with runtime int field "score"
define runtime record "actor" from "Actor"
define runtime record "stats" from "Stats"
copy runtime record "actor" to runtime record "stats"
'@ },
    @{ Name='runtime_record_array_copy_size_negative'; BuildExit=1; Body=@'
define record called "Actor" with runtime int field "hp"
define runtime record array called "a" from "Actor" size 2
define runtime record array called "b" from "Actor" size 3
copy runtime record array "a" to runtime record array "b"
'@ },
    @{ Name='runtime_record_reset_missing_negative'; BuildExit=1; Body=@'
reset runtime record "missing"
'@ },
    @{ Name='runtime_enum_duplicate_value_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Idle"
'@ },
    @{ Name='runtime_enum_unknown_value_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Moving"
define runtime enum "state" from "ActorState" be "Dead"
'@ },
    @{ Name='runtime_enum_wrong_source_type_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Dead"
define enum called "DoorState" with "Open", "Closed"
define runtime enum "actor" from "ActorState" be "Idle"
define runtime enum "door" from "DoorState" be "Open"
set runtime enum "actor" to runtime enum "door"
'@ },
    @{ Name='runtime_if_enum_unknown_value_negative'; BuildExit=1; Body=@'
define enum called "ActorState" with "Idle", "Dead"
define runtime enum "actor" from "ActorState" be "Idle"
runtime if enum "actor" is "Moving"
print string "nope"
end if
'@ }
)

foreach ($Case in $Cases) {
    $src = Join-Path $SourceDir ($Case.Name + '.arq')
    $bin = Join-Path $BinDir ($Case.Name + '.exe')
    $program = New-Program $Case.Name $Case.Body
    Write-TextFile $src $program

    Push-Location $RepoRoot
    try { & $Driver $src -o $bin *> (Join-Path $LogDir ($Case.Name + '.build.log')); $buildExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE } } finally { Pop-Location }
    Add-Result ($(if ($buildExit -eq $Case.BuildExit) { 'PASS' } else { 'FAIL' })) "m55m56_build_$($Case.Name)" "exit=$buildExit expected=$($Case.BuildExit)"

    $irPath = Join-Path $RepoRoot "Build\IR\$($Case.Name).arqir"
    $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { "" }
    if ($Case.ContainsKey('RequireIr') -and $Case.BuildExit -eq 0) {
        foreach ($needle in ($Case.RequireIr -split ',')) {
            $safe = ($needle -replace '[^A-Za-z0-9_]+','_').Trim('_')
            Add-Result ($(if ($irText.Contains($needle)) { 'PASS' } else { 'FAIL' })) "m55m56_ir_$($Case.Name)_$safe" "$needle present"
        }
    }

    if ($buildExit -eq 0 -and $Case.ContainsKey('RunExit')) {
        $caseRunDir = Join-Path $RunDir $Case.Name
        New-Item -ItemType Directory -Force $caseRunDir | Out-Null
        Copy-Item $bin (Join-Path $caseRunDir 'run.exe') -Force
        $run = Invoke-Exe (Join-Path $caseRunDir 'run.exe') $caseRunDir $TimeoutSeconds
        Write-TextFile (Join-Path $LogDir ($Case.Name + '.stdout.txt')) $run.Stdout
        Write-TextFile (Join-Path $LogDir ($Case.Name + '.stderr.txt')) $run.Stderr
        Add-Result ($(if ($run.ExitCode -eq $Case.RunExit) { 'PASS' } else { 'FAIL' })) "m55m56_run_$($Case.Name)" "exit=$($run.ExitCode) expected=$($Case.RunExit)"
        if ($Case.ContainsKey('ExpectStdout')) {
            Add-Result ($(if ($run.Stdout -eq $Case.ExpectStdout) { 'PASS' } else { 'FAIL' })) "m55m56_stdout_$($Case.Name)" "bytes=$($run.Stdout.Length) expected_bytes=$($Case.ExpectStdout.Length) stdout=Build\M55M56\Logs\$($Case.Name).stdout.txt"
        }
    }
}

$outPath = Join-Path $GeneratedDir "m55m56_record_utils_enums_validation.txt"
Write-TextFile $outPath (($Results -join "`n") + "`n")
Write-Host "OUT|Build\Generated\m55m56_record_utils_enums_validation.txt"

if ($Results | Where-Object { $_ -like 'FAIL|*' }) { exit 1 }
exit 0
