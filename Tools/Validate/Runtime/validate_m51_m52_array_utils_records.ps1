param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M51M52"
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
            Add-Result "PASS" "m51m52_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m51m52_driver_build" "dotnet publish failed; see Build\M51M52\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m51m52_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M51_M55.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('fill runtime arrays') -and $docText.Contains('copy runtime arrays') -and $docText.Contains('runtime records') -and $docText.Contains('set runtime record')) { "PASS" } else { "FAIL" })) "m51m52_docs_array_utils_records" "Docs\Milestones\\M51_M55.md documents M51/M52"

$spec = Join-Path $RepoRoot "Tests\CommandTests\misc\runtime_array_utils_records.command.txt"
$specText = if (Test-Path $spec) { Get-Content $spec -Raw } else { "" }
Add-Result ($(if ($specText.Contains('COMMAND_ID|runtime_array_utils_records') -and $specText.Contains('MILESTONE|M51_M52') -and $specText.Contains('fill runtime') -and $specText.Contains('define record')) { "PASS" } else { "FAIL" })) "m51m52_spec_array_utils_records" "Tests\CommandTests\misc\runtime_array_utils_records.command.txt records M51/M52"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m51m52') -and $slice.Contains('array_utils_records')) { "PASS" } else { "FAIL" })) "m51m52_slice_aliases" "run_test_slice exposes m51m52/m51/m52"

$registryGenerator = Join-Path $RepoRoot 'Tools\Generate\generate_runtime_action_registry.ps1'
if (Test-Path $registryGenerator) {
    Push-Location $RepoRoot
    try {
        & $registryGenerator *> (Join-Path $LogDir 'runtime_action_registry.build.log')
        $registryExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($registryExit -eq 0) { 'PASS' } else { 'FAIL' })) "m51m52_runtime_action_registry_generation" "exit=$registryExit log=Build\M51M52\Logs\runtime_action_registry.build.log"
} else {
    Add-Result 'FAIL' 'm51m52_runtime_action_registry_generation' 'Tools\Generate\generate_runtime_action_registry.ps1 missing'
}

$catalogValidator = Join-Path $RepoRoot 'Tools\Validate\Core\validate_runtime_action_catalog.ps1'
if (Test-Path $catalogValidator) {
    Push-Location $RepoRoot
    try {
        & $catalogValidator *> (Join-Path $LogDir 'runtime_action_catalog.build.log')
        $catalogExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($catalogExit -eq 0) { 'PASS' } else { 'FAIL' })) "m51m52_runtime_action_catalog_validation" "exit=$catalogExit log=Build\M51M52\Logs\runtime_action_catalog.build.log"
} else {
    Add-Result 'FAIL' 'm51m52_runtime_action_catalog_validation' 'Tools\Validate\Core\validate_runtime_action_catalog.ps1 missing'
}

$Cases = @(
    @{ Name='runtime_array_fill_int_static'; BuildExit=0; RunExit=0; ExpectStdout="7`n"; RequireIr='target=__arr_values_0,target=__arr_values_1,target=__arr_values_2,value=__arr_values_2|target=out'; Body=@'
define runtime int array called "values" size 3
fill runtime int array "values" with 7
define runtime int called "out" be 0
set runtime int "out" to runtime int array "values" at 2
print "out"
'@ },
    @{ Name='runtime_array_fill_string_from_slot'; BuildExit=0; RunExit=0; ExpectStdout="Core`n"; RequireIr='target=__arr_parts_string_0,target=__arr_parts_string_1,value=label|target=__arr_parts_string_1'; Body=@'
define runtime string array called "parts" size 2
define runtime string called "label" be string "Core"
fill runtime string array "parts" with runtime string "label"
define runtime string called "out" be string ""
set runtime string "out" to runtime string array "parts" at 1
print "out"
'@ },
    @{ Name='runtime_array_copy_int_global'; BuildExit=0; RunExit=0; ExpectStdout="42`n"; RequireIr='value=__arr_source_1|target=__arr_dest_1,value=__arr_dest_1|target=out'; Body=@'
define runtime int array called "source" size 2
define runtime int array called "dest" size 2
set runtime int array "source" at 1 to 42
copy runtime int array "source" to runtime int array "dest"
define runtime int called "out" be 0
set runtime int "out" to runtime int array "dest" at 1
print "out"
'@ },
    @{ Name='runtime_array_fill_param_copyback'; BuildExit=0; RunExit=0; ExpectStdout="9`n"; RequireIr='params=int_array:items:__fn_reset_param_arr_items:3,value=9|target=__arr___fn_reset_param_arr_items_0,value=__arr___fn_reset_param_arr_items_2|target=__arr_values_2'; Body=@'
define runtime int array called "values" size 3

fill runtime int array "values" with 1

define function called "reset" with runtime int array "items" size 3
fill runtime int array "items" with 9
end function

call function "reset" with runtime int array "values"
define runtime int called "out" be 0
set runtime int "out" to runtime int array "values" at 2
print "out"
'@ },
    @{ Name='runtime_record_basic_fields'; BuildExit=0; RunExit=0; ExpectStdout="42`nready`nCryblo`n"; RequireIr='__rec_player_hp,__rec_player_alive,__rec_player_name,value=__rec_player_hp|target=hp_out,value=__rec_player_name|target=name_out'; Body=@'
define record called "Actor" with runtime int field "hp", runtime bool field "alive", runtime string field "name"
define runtime record "player" from "Actor"
set runtime record "player" field "hp" to 42
set runtime record "player" field "alive" to true
set runtime record "player" field "name" to string "Cryblo"

define runtime int called "hp_out" be 0
define runtime bool called "alive_out" be false
define runtime string called "name_out" be string ""
set runtime int "hp_out" to runtime record "player" field "hp"
set runtime bool "alive_out" to runtime record "player" field "alive"
set runtime string "name_out" to runtime record "player" field "name"
print "hp_out"
runtime if "alive_out" is true
print string "ready"
end if
print "name_out"
'@ },
    @{ Name='runtime_record_field_from_slot_in_function'; BuildExit=0; RunExit=0; ExpectStdout="77`n"; RequireIr='FUNCTION|name=write_score,value=source|target=__rec_player_score,function_call|path=|value_kind=static|value=|target=write_score'; Body=@'
define record called "Stats" with runtime int field "score"
define runtime record "player" from "Stats"
define runtime int called "source" be 77

define function called "write_score"
set runtime record "player" field "score" to runtime int "source"
end function

call function "write_score"
define runtime int called "out" be 0
set runtime int "out" to runtime record "player" field "score"
print "out"
'@ },
    @{ Name='runtime_array_fill_wrong_type_negative'; BuildExit=1; Body=@'
define runtime int array called "values" size 2
fill runtime int array "values" with string "bad"
'@ },
    @{ Name='runtime_array_copy_size_mismatch_negative'; BuildExit=1; Body=@'
define runtime int array called "left" size 2
define runtime int array called "right" size 3
copy runtime int array "left" to runtime int array "right"
'@ },
    @{ Name='runtime_record_duplicate_field_negative'; BuildExit=1; Body=@'
define record called "Bad" with runtime int field "x" and runtime bool field "x"
'@ },
    @{ Name='runtime_record_missing_type_negative'; BuildExit=1; Body=@'
define runtime record "player" from "Missing"
'@ },
    @{ Name='runtime_record_wrong_field_type_negative'; BuildExit=1; Body=@'
define record called "Actor" with runtime int field "hp"
define runtime record "player" from "Actor"
define runtime string called "out" be string ""
set runtime string "out" to runtime record "player" field "hp"
'@ },
    @{ Name='runtime_record_unknown_field_negative'; BuildExit=1; Body=@'
define record called "Actor" with runtime int field "hp"
define runtime record "player" from "Actor"
set runtime record "player" field "mana" to 1
'@ }
)

function Run-Case {
    param($Case)
    $sourcePath = Join-Path $SourceDir ($Case.Name + ".arq")
    $logPath = Join-Path $LogDir ($Case.Name + ".build.log")
    $stdoutPath = Join-Path $LogDir ($Case.Name + ".stdout.txt")
    $stderrPath = Join-Path $LogDir ($Case.Name + ".stderr.txt")
    Write-TextFile $sourcePath (New-Program $Case.Name $Case.Body)

    $exePath = Join-Path $BinDir ($Case.Name + ".exe")
    Push-Location $RepoRoot
    try {
        & $Driver $sourcePath -o $exePath *> $logPath
        $buildExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($buildExit -eq $Case.BuildExit) { 'PASS' } else { 'FAIL' })) ("m51m52_build_" + $Case.Name) "exit=$buildExit expected=$($Case.BuildExit)"

    if ($buildExit -ne 0 -or $Case.BuildExit -ne 0) { return }

    $irPath = Join-Path $RepoRoot ("Build\IR\" + $Case.Name + ".arqir")
    $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { "" }
    if ($Case.ContainsKey('RequireIr')) {
        foreach ($needle in ($Case.RequireIr -split ',')) {
            $trimmed = $needle.Trim()
            if ($trimmed -eq '') { continue }
            Add-Result ($(if ($irText.Contains($trimmed)) { 'PASS' } else { 'FAIL' })) ("m51m52_ir_" + $Case.Name + "_" + ($trimmed -replace '[^A-Za-z0-9_]+','_')) "$trimmed present"
        }
    }

    if (-not (Test-Path $exePath)) {
        Add-Result 'FAIL' ("m51m52_exe_" + $Case.Name) "missing exe"
        return
    }
    $caseRunDir = Join-Path $RunDir $Case.Name
    New-Item -ItemType Directory -Force $caseRunDir | Out-Null
    Copy-Item $exePath (Join-Path $caseRunDir ($Case.Name + ".exe")) -Force
    $run = Invoke-Exe (Join-Path $caseRunDir ($Case.Name + ".exe")) $caseRunDir $TimeoutSeconds
    [System.IO.File]::WriteAllText($stdoutPath, $run.Stdout, $Utf8NoBom)
    [System.IO.File]::WriteAllText($stderrPath, $run.Stderr, $Utf8NoBom)
    Add-Result ($(if ($run.ExitCode -eq $Case.RunExit) { 'PASS' } else { 'FAIL' })) ("m51m52_run_" + $Case.Name) "exit=$($run.ExitCode) expected=$($Case.RunExit)"
    if ($Case.ContainsKey('ExpectStdout')) {
        $expectedBytes = [System.Text.Encoding]::UTF8.GetBytes($Case.ExpectStdout)
        $actualBytes = [System.IO.File]::ReadAllBytes($stdoutPath)
        $ok = ($actualBytes.Length -eq $expectedBytes.Length)
        if ($ok) {
            for ($i = 0; $i -lt $actualBytes.Length; $i++) { if ($actualBytes[$i] -ne $expectedBytes[$i]) { $ok = $false; break } }
        }
        Add-Result ($(if ($ok) { 'PASS' } else { 'FAIL' })) ("m51m52_stdout_" + $Case.Name) "bytes=$($actualBytes.Length) expected_bytes=$($expectedBytes.Length) stdout=Build\M51M52\Logs\$($Case.Name).stdout.txt"
    }
}

foreach ($case in $Cases) { Run-Case $case }

$outPath = Join-Path $GeneratedDir "m51m52_array_utils_records_validation.txt"
[System.IO.File]::WriteAllLines($outPath, $Results, $Utf8NoBom)
Write-Host "OUT|Build\Generated\m51m52_array_utils_records_validation.txt"
if ($Results | Where-Object { $_.StartsWith('FAIL|') }) { exit 1 }
exit 0
