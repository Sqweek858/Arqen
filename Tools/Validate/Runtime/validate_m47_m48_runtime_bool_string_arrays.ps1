param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M47M48"
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
            Add-Result "PASS" "m47m48_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m47m48_driver_build" "dotnet publish failed; see Build\M47M48\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m47m48_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M46_M50.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('runtime bool arrays') -and $docText.Contains('runtime string arrays') -and $docText.Contains('array length helper') -and $docText.Contains('runtime_trap_if_bool_false')) { "PASS" } else { "FAIL" })) "m47m48_docs_bool_string_arrays" "Docs\Milestones\\M46_M50.md documents M47/M48"

$spec = Join-Path $RepoRoot "Tests\CommandTests\misc\runtime_bool_string_arrays.command.txt"
$specText = if (Test-Path $spec) { Get-Content $spec -Raw } else { "" }
Add-Result ($(if ($specText.Contains('COMMAND_ID|runtime_bool_string_arrays') -and $specText.Contains('MILESTONE|M47_M48') -and $specText.Contains('length of runtime')) { "PASS" } else { "FAIL" })) "m47m48_spec_bool_string_arrays" "Tests\CommandTests\misc\runtime_bool_string_arrays.command.txt records M47/M48"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m47m48') -and $slice.Contains('runtime_bool_string_arrays')) { "PASS" } else { "FAIL" })) "m47m48_slice_aliases" "run_test_slice exposes m47m48/m47/m48"

$registryGenerator = Join-Path $RepoRoot 'Tools\Generate\generate_runtime_action_registry.ps1'
if (Test-Path $registryGenerator) {
    Push-Location $RepoRoot
    try {
        & $registryGenerator *> (Join-Path $LogDir 'runtime_action_registry.build.log')
        $registryExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($registryExit -eq 0) { 'PASS' } else { 'FAIL' })) "m47m48_runtime_action_registry_generation" "exit=$registryExit log=Build\M47M48\Logs\runtime_action_registry.build.log"
} else {
    Add-Result 'FAIL' 'm47m48_runtime_action_registry_generation' 'Tools\Generate\generate_runtime_action_registry.ps1 missing'
}

$catalogValidator = Join-Path $RepoRoot 'Tools\Validate\Core\validate_runtime_action_catalog.ps1'
if (Test-Path $catalogValidator) {
    Push-Location $RepoRoot
    try {
        & $catalogValidator *> (Join-Path $LogDir 'runtime_action_catalog.build.log')
        $catalogExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($catalogExit -eq 0) { 'PASS' } else { 'FAIL' })) "m47m48_runtime_action_catalog_validation" "exit=$catalogExit log=Build\M47M48\Logs\runtime_action_catalog.build.log"
} else {
    Add-Result 'FAIL' 'm47m48_runtime_action_catalog_validation' 'Tools\Validate\Core\validate_runtime_action_catalog.ps1 missing'
}

$Cases = @(
    @{ Name='runtime_bool_array_static_set_get'; BuildExit=0; RunExit=0; ExpectStdout="ready`n"; RequireIr='__arr_flags_bool_1,runtime_bool_set|path=|value_kind=slot|value=__arr_flags_bool_1|target=ok'; Body=@'
define runtime bool array called "flags" size 2
set runtime bool array "flags" at 1 to true
define runtime bool called "ok" be false
set runtime bool "ok" to runtime bool array "flags" at 1
runtime if "ok" is true
print string "ready"
end if
'@ },
    @{ Name='runtime_bool_array_dynamic_set_get'; BuildExit=0; RunExit=0; ExpectStdout="hit`n"; RequireIr='runtime_trap_if_bool_false,__arr_flags_bounds_ok_,__arr_flags_index_,runtime_if_int|path=eq|value_kind=static|value=1'; Body=@'
define runtime bool array called "flags" size 2
define runtime int called "i" be 1
set runtime bool array "flags" at runtime int "i" to true
define runtime bool called "ok" be false
set runtime bool "ok" to runtime bool array "flags" at runtime int "i"
runtime if "ok" is true
print string "hit"
end if
'@ },
    @{ Name='runtime_string_array_static_set_get'; BuildExit=0; RunExit=0; ExpectStdout="blo`n"; RequireIr='__arr_parts_string_1,runtime_string_set|path=|value_kind=slot|value=__arr_parts_string_1|target=out'; Body=@'
define runtime string array called "parts" size 2
set runtime string array "parts" at 0 to string "Cry"
set runtime string array "parts" at 1 to string "blo"
define runtime string called "out" be string ""
set runtime string "out" to runtime string array "parts" at 1
print "out"
'@ },
    @{ Name='runtime_string_array_dynamic_set_get'; BuildExit=0; RunExit=0; ExpectStdout="Core`n"; RequireIr='runtime_trap_if_bool_false,__arr_parts_bounds_ok_,__arr_parts_index_,runtime_if_int|path=eq|value_kind=static|value=1'; Body=@'
define runtime string array called "parts" size 2
define runtime int called "i" be 1
set runtime string array "parts" at runtime int "i" to string "Core"
define runtime string called "out" be string ""
set runtime string "out" to runtime string array "parts" at runtime int "i"
print "out"
'@ },
    @{ Name='runtime_array_length_helper'; BuildExit=0; RunExit=0; ExpectStdout="3`n2`n4`n"; RequireIr='runtime_int_set|path=|value_kind=static|value=3|target=len_int,runtime_int_set|path=|value_kind=static|value=2|target=len_bool,runtime_int_set|path=|value_kind=static|value=4|target=len_string'; Body=@'
define runtime int array called "values" size 3
define runtime bool array called "flags" size 2
define runtime string array called "names" size 4
define runtime int called "len_int" be 0
define runtime int called "len_bool" be 0
define runtime int called "len_string" be 0
set runtime int "len_int" to length of runtime int array "values"
set runtime int "len_bool" to length of runtime bool array "flags"
set runtime int "len_string" to length of runtime string array "names"
print "len_int"
print "len_bool"
print "len_string"
'@ },
    @{ Name='runtime_string_array_inside_function'; BuildExit=0; RunExit=0; ExpectStdout="Cryblo`n"; RequireIr='FUNCTION|name=read_name,__fn_read_name_local_out,function_call_assign|path=string|value_kind=static|value=read_name|target=out'; Body=@'
define runtime string array called "names" size 2
set runtime string array "names" at 0 to string "Cryblo"

define function called "read_name"
define local runtime string called "out" be string ""
set runtime string "out" to runtime string array "names" at 0
return runtime string "out"
end function

define runtime string called "out" be string ""
set runtime string "out" to call function "read_name"
print "out"
'@ },
    @{ Name='runtime_string_array_dynamic_bounds_trap'; BuildExit=0; RunExit=1; ExpectStdout=""; RequireIr='runtime_trap_if_bool_false'; Body=@'
define runtime string array called "parts" size 2
define runtime int called "i" be 7
define runtime string called "out" be string ""
set runtime string "out" to runtime string array "parts" at runtime int "i"
print "out"
'@ },
    @{ Name='runtime_bool_array_wrong_value_negative'; BuildExit=1; Body=@'
define runtime bool array called "flags" size 2
set runtime bool array "flags" at 0 to string "bad"
'@ },
    @{ Name='runtime_string_array_wrong_get_target_negative'; BuildExit=1; Body=@'
define runtime string array called "parts" size 2
define runtime int called "out" be 0
set runtime int "out" to runtime string array "parts" at 0
'@ },
    @{ Name='runtime_bool_array_static_oob_negative'; BuildExit=1; Body=@'
define runtime bool array called "flags" size 2
set runtime bool array "flags" at 2 to true
'@ },
    @{ Name='runtime_string_array_missing_negative'; BuildExit=1; Body=@'
define runtime string called "out" be string ""
set runtime string "out" to runtime string array "missing" at 0
'@ },
    @{ Name='runtime_string_array_wrong_dynamic_index_negative'; BuildExit=1; Body=@'
define runtime string array called "parts" size 2
define runtime string called "idx" be string "1"
define runtime string called "out" be string ""
set runtime string "out" to runtime string array "parts" at runtime int "idx"
'@ },
    @{ Name='runtime_array_symbol_collision_negative'; BuildExit=1; Body=@'
define runtime bool array called "slots" size 2
define runtime string array called "slots" size 2
'@ }
)

foreach ($case in $Cases) {
    $sourcePath = Join-Path $SourceDir ($case['Name'] + '.arq')
    $exePath = Join-Path $BinDir ($case['Name'] + '.exe')
    $runCaseDir = Join-Path $RunDir $case['Name']
    New-Item -ItemType Directory -Force $runCaseDir | Out-Null
    Write-TextFile $sourcePath (New-Program $case['Name'] $case['Body'])

    Push-Location $RepoRoot
    try {
        & $Driver $sourcePath -o $exePath *> (Join-Path $LogDir ($case['Name'] + '.build.log'))
        $buildExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }

    if ($buildExit -ne $case['BuildExit']) {
        Add-Result 'FAIL' ('m47m48_build_' + $case['Name']) "exit=$buildExit expected=$($case['BuildExit'])"
        continue
    }
    Add-Result 'PASS' ('m47m48_build_' + $case['Name']) "exit=$buildExit"

    if ($case['BuildExit'] -ne 0) { continue }

    if ($case.ContainsKey('RequireIr')) {
        $irPath = Join-Path $RepoRoot ('Build\IR\' + $case['Name'] + '.arqir')
        $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { '' }
        foreach ($needle in ($case['RequireIr'].Split(','))) {
            Add-Result ($(if ($irText.Contains($needle)) { 'PASS' } else { 'FAIL' })) ('m47m48_ir_' + $case['Name'] + '_' + ($needle -replace '[^A-Za-z0-9_]+','_')) "$needle present"
        }
    }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result 'FAIL' ('m47m48_run_' + $case['Name']) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result 'FAIL' ('m47m48_run_' + $case['Name']) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq $case['RunExit']) { 'PASS' } else { 'FAIL' })) ('m47m48_run_' + $case['Name']) "exit=$($run.ExitCode) expected=$($case['RunExit'])"

    $stdoutPath = Join-Path $LogDir ($case['Name'] + '.stdout.txt')
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case['ExpectStdout'], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case['ExpectStdout'])
    Add-Result ($(if ($ok) { 'PASS' } else { 'FAIL' })) ('m47m48_stdout_' + $case['Name']) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=$($stdoutPath.Substring($RepoRoot.Length + 1))"
}

$outFile = Join-Path $GeneratedDir "m47m48_runtime_bool_string_arrays_validation.txt"
Set-Content -Path $outFile -Value $Results -Encoding UTF8
Write-Host "OUT|$($outFile.Substring($RepoRoot.Length + 1))"

if ($Results | Where-Object { $_ -like 'FAIL|*' }) { exit 1 }
exit 0
