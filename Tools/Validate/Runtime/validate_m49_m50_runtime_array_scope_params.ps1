param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M49M50"
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
            Add-Result "PASS" "m49m50_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m49m50_driver_build" "dotnet publish failed; see Build\M49M50\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m49m50_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M46_M50.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('local runtime arrays') -and $docText.Contains('array parameters') -and $docText.Contains('copy-in/copy-back') -and $docText.Contains('define local runtime int array')) { "PASS" } else { "FAIL" })) "m49m50_docs_array_scope_params" "Docs\Milestones\\M46_M50.md documents M49/M50"

$spec = Join-Path $RepoRoot "Tests\CommandTests\misc\runtime_array_scope_params.command.txt"
$specText = if (Test-Path $spec) { Get-Content $spec -Raw } else { "" }
Add-Result ($(if ($specText.Contains('COMMAND_ID|runtime_array_scope_params') -and $specText.Contains('MILESTONE|M49_M50') -and $specText.Contains('define local runtime')) { "PASS" } else { "FAIL" })) "m49m50_spec_array_scope_params" "Tests\CommandTests\misc\runtime_array_scope_params.command.txt records M49/M50"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m49m50') -and $slice.Contains('runtime_array_scope_params')) { "PASS" } else { "FAIL" })) "m49m50_slice_aliases" "run_test_slice exposes m49m50/m49/m50"

$registryGenerator = Join-Path $RepoRoot 'Tools\Generate\generate_runtime_action_registry.ps1'
if (Test-Path $registryGenerator) {
    Push-Location $RepoRoot
    try {
        & $registryGenerator *> (Join-Path $LogDir 'runtime_action_registry.build.log')
        $registryExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($registryExit -eq 0) { 'PASS' } else { 'FAIL' })) "m49m50_runtime_action_registry_generation" "exit=$registryExit log=Build\M49M50\Logs\runtime_action_registry.build.log"
} else {
    Add-Result 'FAIL' 'm49m50_runtime_action_registry_generation' 'Tools\Generate\generate_runtime_action_registry.ps1 missing'
}

$catalogValidator = Join-Path $RepoRoot 'Tools\Validate\Core\validate_runtime_action_catalog.ps1'
if (Test-Path $catalogValidator) {
    Push-Location $RepoRoot
    try {
        & $catalogValidator *> (Join-Path $LogDir 'runtime_action_catalog.build.log')
        $catalogExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($catalogExit -eq 0) { 'PASS' } else { 'FAIL' })) "m49m50_runtime_action_catalog_validation" "exit=$catalogExit log=Build\M49M50\Logs\runtime_action_catalog.build.log"
} else {
    Add-Result 'FAIL' 'm49m50_runtime_action_catalog_validation' 'Tools\Validate\Core\validate_runtime_action_catalog.ps1 missing'
}

$Cases = @(
    @{ Name='runtime_local_int_array_return'; BuildExit=0; RunExit=0; ExpectStdout="42`n"; RequireIr='__fn_read_local_local_arr_values,__arr___fn_read_local_local_arr_values_2,function_call_assign|path=int|value_kind=static|value=read_local|target=out'; Body=@'
define function called "read_local"
define local runtime int array called "values" size 3
set runtime int array "values" at 2 to 42
define local runtime int called "tmp" be 0
set runtime int "tmp" to runtime int array "values" at 2
return runtime int "tmp"
end function

define runtime int called "out" be 0
set runtime int "out" to call function "read_local"
print "out"
'@ },
    @{ Name='runtime_local_array_shadow_global'; BuildExit=0; RunExit=0; ExpectStdout="42`n5`n"; RequireIr='__fn_read_local_local_arr_values,__arr_values_0'; Body=@'
define runtime int array called "values" size 1
set runtime int array "values" at 0 to 5

define function called "read_local"
define local runtime int array called "values" size 1
set runtime int array "values" at 0 to 42
define local runtime int called "tmp" be 0
set runtime int "tmp" to runtime int array "values" at 0
return runtime int "tmp"
end function

define runtime int called "local_out" be 0
define runtime int called "global_out" be 0
set runtime int "local_out" to call function "read_local"
set runtime int "global_out" to runtime int array "values" at 0
print "local_out"
print "global_out"
'@ },
    @{ Name='runtime_local_string_array_dynamic'; BuildExit=0; RunExit=0; ExpectStdout="Core`n"; RequireIr='__fn_read_local_local_arr_parts,__arr___fn_read_local_local_arr_parts_string_1,runtime_trap_if_bool_false'; Body=@'
define function called "read_local"
define local runtime string array called "parts" size 2
define local runtime int called "i" be 1
set runtime string array "parts" at runtime int "i" to string "Core"
define local runtime string called "out" be string ""
set runtime string "out" to runtime string array "parts" at runtime int "i"
return runtime string "out"
end function

define runtime string called "out" be string ""
set runtime string "out" to call function "read_local"
print "out"
'@ },
    @{ Name='runtime_array_param_int_copyback'; BuildExit=0; RunExit=0; ExpectStdout="42`n"; RequireIr='params=int_array:items:__fn_bump_first_param_arr_items:2,__arr___fn_bump_first_param_arr_items_0,__arr_values_0|target=__arr___fn_bump_first_param_arr_items_0,__arr___fn_bump_first_param_arr_items_0|target=__arr_values_0'; Body=@'
define runtime int array called "values" size 2
set runtime int array "values" at 0 to 40

define function called "bump_first" with runtime int array "items" size 2
define local runtime int called "tmp" be 0
set runtime int "tmp" to runtime int array "items" at 0
add 2 to "tmp"
set runtime int array "items" at 0 to "tmp"
end function

call function "bump_first" with runtime int array "values"
define runtime int called "out" be 0
set runtime int "out" to runtime int array "values" at 0
print "out"
'@ },
    @{ Name='runtime_array_param_string_return'; BuildExit=0; RunExit=0; ExpectStdout="blo`n"; RequireIr='params=string_array:items:__fn_read_at_param_arr_items:2,int:idx:__fn_read_at_param_idx,function_call_assign|path=string|value_kind=static|value=read_at|target=out'; Body=@'
define runtime string array called "names" size 2
set runtime string array "names" at 0 to string "Cry"
set runtime string array "names" at 1 to string "blo"
define runtime int called "i" be 1

define function called "read_at" with runtime string array "items" size 2 and runtime int "idx"
define local runtime string called "out" be string ""
set runtime string "out" to runtime string array "items" at runtime int "idx"
return runtime string "out"
end function

define runtime string called "out" be string ""
set runtime string "out" to call function "read_at" with runtime string array "names" and runtime int "i"
print "out"
'@ },
    @{ Name='runtime_local_array_outside_negative'; BuildExit=1; Body=@'
define local runtime int array called "values" size 2
'@ },
    @{ Name='runtime_local_array_param_conflict_negative'; BuildExit=1; Body=@'
define function called "bad" with runtime int array "items" size 2
define local runtime int array called "items" size 2
end function
'@ },
    @{ Name='runtime_array_param_wrong_type_negative'; BuildExit=1; Body=@'
define runtime int array called "values" size 2

define function called "accept" with runtime bool array "items" size 2
end function

call function "accept" with runtime int array "values"
'@ },
    @{ Name='runtime_array_param_size_mismatch_negative'; BuildExit=1; Body=@'
define runtime int array called "values" size 2

define function called "accept" with runtime int array "items" size 3
end function

call function "accept" with runtime int array "values"
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
        Add-Result 'FAIL' ('m49m50_build_' + $case['Name']) "exit=$buildExit expected=$($case['BuildExit'])"
        continue
    }
    Add-Result 'PASS' ('m49m50_build_' + $case['Name']) "exit=$buildExit"

    if ($case['BuildExit'] -ne 0) { continue }

    if ($case.ContainsKey('RequireIr')) {
        $irPath = Join-Path $RepoRoot ('Build\IR\' + $case['Name'] + '.arqir')
        $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { '' }
        foreach ($needle in ($case['RequireIr'].Split(','))) {
            Add-Result ($(if ($irText.Contains($needle)) { 'PASS' } else { 'FAIL' })) ('m49m50_ir_' + $case['Name'] + '_' + ($needle -replace '[^A-Za-z0-9_]+','_')) "$needle present"
        }
    }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result 'FAIL' ('m49m50_run_' + $case['Name']) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result 'FAIL' ('m49m50_run_' + $case['Name']) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq $case['RunExit']) { 'PASS' } else { 'FAIL' })) ('m49m50_run_' + $case['Name']) "exit=$($run.ExitCode) expected=$($case['RunExit'])"

    $stdoutPath = Join-Path $LogDir ($case['Name'] + '.stdout.txt')
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case['ExpectStdout'], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case['ExpectStdout'])
    Add-Result ($(if ($ok) { 'PASS' } else { 'FAIL' })) ('m49m50_stdout_' + $case['Name']) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=Build\M49M50\Logs\$($case['Name']).stdout.txt"
}

$ValidationPath = Join-Path $GeneratedDir "m49m50_runtime_array_scope_params_validation.txt"
[System.IO.File]::WriteAllLines($ValidationPath, $Results, $Utf8NoBom)
$failed = @($Results | Where-Object { $_.StartsWith('FAIL|') })
if ($failed.Count -gt 0) { exit 1 }
exit 0
