param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M42ABC"
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
            Add-Result "PASS" "m42abc_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m42abc_driver_build" "dotnet publish failed; see Build\M42ABC\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m42abc_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M41_M45.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('typed parameters') -and $docText.Contains('__fn_') -and $docText.Contains('internal runtime slots')) { "PASS" } else { "FAIL" })) "m42c_docs_function_parameters" "Docs\Milestones\\M41_M45.md documents M42 function parameters"

$spec = Join-Path $RepoRoot "Tests\CommandTests\misc\runtime_function_params.command.txt"
$specText = if (Test-Path $spec) { Get-Content $spec -Raw } else { "" }
Add-Result ($(if ($specText.Contains('COMMAND|runtime_function_params|M42') -and $specText.Contains('missing argument') -and $specText.Contains('wrong argument type')) { "PASS" } else { "FAIL" })) "m42c_spec_function_parameters" "Tests\CommandTests\misc\runtime_function_params.command.txt records M42 contract"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m42abc') -and $slice.Contains('function_parameters')) { "PASS" } else { "FAIL" })) "m42c_slice_aliases" "run_test_slice exposes m42abc/m42a/m42b/m42c"

$registryGenerator = Join-Path $RepoRoot 'Tools\Generate\generate_runtime_action_registry.ps1'
if (Test-Path $registryGenerator) {
    Push-Location $RepoRoot
    try {
        & $registryGenerator *> (Join-Path $LogDir 'runtime_action_registry.build.log')
        $registryExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($registryExit -eq 0) { 'PASS' } else { 'FAIL' })) "m42c_runtime_action_registry_generation" "exit=$registryExit log=Build\M42ABC\Logs\runtime_action_registry.build.log"
} else {
    Add-Result 'FAIL' 'm42c_runtime_action_registry_generation' 'Tools\Generate\generate_runtime_action_registry.ps1 missing'
}

$catalogValidator = Join-Path $RepoRoot 'Tools\Validate\Core\validate_runtime_action_catalog.ps1'
if (Test-Path $catalogValidator) {
    Push-Location $RepoRoot
    try {
        & $catalogValidator *> (Join-Path $LogDir 'runtime_action_catalog.build.log')
        $catalogExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($catalogExit -eq 0) { 'PASS' } else { 'FAIL' })) "m42c_runtime_action_catalog_validation" "exit=$catalogExit log=Build\M42ABC\Logs\runtime_action_catalog.build.log"
} else {
    Add-Result 'FAIL' 'm42c_runtime_action_catalog_validation' 'Tools\Validate\Core\validate_runtime_action_catalog.ps1 missing'
}

$Cases = @(
    @{ Name='function_param_int_static_return'; ExpectExit=0; ExpectStdout="42`n"; RequireIr='params=int:x:,target=__fn_next_param_x,function_return_int|path=|value_kind=slot|value=__fn_next_param_x,function_call_assign'; Body=@'
define function called "next" with runtime int "x"
add 1 to "x"
return runtime int "x"
end function
define runtime int called "out" be 0
set runtime int "out" to call function "next" with int 41
print "out"
'@ },
    @{ Name='function_param_string_static_return'; ExpectExit=0; ExpectStdout="Cryblo`n"; RequireIr='params=string:name:,runtime_string_set,function_call_assign'; Body=@'
define function called "echo" with runtime string "name"
return runtime string "name"
end function
define runtime string called "out" be string ""
set runtime string "out" to call function "echo" with string "Cryblo"
print "out"
'@ },
    @{ Name='function_param_bool_static_return'; ExpectExit=0; ExpectStdout="ready`n"; RequireIr='params=bool:flag:,runtime_bool_set,function_call_assign'; Body=@'
define function called "gate" with runtime bool "flag"
return runtime bool "flag"
end function
define runtime bool called "ok" be false
set runtime bool "ok" to call function "gate" with bool true
runtime if "ok" is true
print string "ready"
end if
'@ },
    @{ Name='function_param_runtime_slot_copy'; ExpectExit=0; ExpectStdout="5`n10`n9`n"; RequireIr='target=__fn_next_param_x,function_return_int|path=|value_kind=slot|value=__fn_next_param_x,function_call_assign'; Body=@'
define runtime int called "source" be 4
define function called "next" with runtime int "x"
add 1 to "x"
return runtime int "x"
end function
define runtime int called "out" be 0
set runtime int "out" to call function "next" with runtime int "source"
print "out"
set runtime int "source" to 9
set runtime int "out" to call function "next" with runtime int "source"
print "out"
print "source"
'@ },
    @{ Name='function_param_multiple_string_join'; ExpectExit=0; ExpectStdout="Cryblo`n"; RequireIr='params=string:left:,runtime_string_concat,function_call_assign'; Body=@'
define runtime string called "scratch" be string ""
define function called "join" with runtime string "left", runtime string "right"
set runtime string "scratch" to "left" + "right"
return runtime string "scratch"
end function
define runtime string called "out" be string ""
set runtime string "out" to call function "join" with string "Cry" and string "blo"
print "out"
'@ },
    @{ Name='function_param_void_call_with_arg'; ExpectExit=0; ExpectStdout="hello`n"; RequireIr='function_call,runtime_string_set,__fn_say_param_text'; Body=@'
define function called "say" with runtime string "text"
print "text"
end function
call function "say" with string "hello"
'@ },
    @{ Name='function_param_missing_arg_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "next" with runtime int "x"
return runtime int "x"
end function
define runtime int called "out" be 0
set runtime int "out" to call function "next"
'@ },
    @{ Name='function_param_extra_arg_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "noop"
print string "x"
end function
call function "noop" with int 1
'@ },
    @{ Name='function_param_wrong_type_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "next" with runtime int "x"
return runtime int "x"
end function
define runtime int called "out" be 0
set runtime int "out" to call function "next" with string "bad"
'@ },
    @{ Name='function_param_duplicate_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "bad" with runtime int "x", runtime string "x"
print string "bad"
end function
call function "bad" with int 1 and string "x"
'@ },
    @{ Name='function_param_shadow_global_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime int called "x" be 0
define function called "bad" with runtime int "x"
return runtime int "x"
end function
call function "bad" with int 1
'@ },
    @{ Name='function_param_runtime_arg_wrong_slot_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime string called "name" be string "Cryblo"
define function called "next" with runtime int "x"
return runtime int "x"
end function
define runtime int called "out" be 0
set runtime int "out" to call function "next" with runtime int "name"
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

    if ($buildExit -ne $case['ExpectExit']) {
        Add-Result 'FAIL' ('m42abc_build_' + $case['Name']) "exit=$buildExit expected=$($case['ExpectExit'])"
        continue
    }
    Add-Result 'PASS' ('m42abc_build_' + $case['Name']) "exit=$buildExit"

    if ($case['ExpectExit'] -ne 0) { continue }

    if ($case.ContainsKey('RequireIr')) {
        $irPath = Join-Path $RepoRoot ('Build\IR\' + $case['Name'] + '.arqir')
        $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { '' }
        foreach ($needle in ($case['RequireIr'].Split(','))) {
            Add-Result ($(if ($irText.Contains($needle)) { 'PASS' } else { 'FAIL' })) ('m42abc_ir_' + $case['Name'] + '_' + ($needle -replace '[^A-Za-z0-9_]+','_')) "$needle present"
        }
    }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result 'FAIL' ('m42abc_run_' + $case['Name']) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result 'FAIL' ('m42abc_run_' + $case['Name']) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq 0) { 'PASS' } else { 'FAIL' })) ('m42abc_run_' + $case['Name']) "exit=$($run.ExitCode)"

    $stdoutPath = Join-Path $LogDir ($case['Name'] + '.stdout.txt')
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case['ExpectStdout'], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case['ExpectStdout'])
    Add-Result ($(if ($ok) { 'PASS' } else { 'FAIL' })) ('m42abc_stdout_' + $case['Name']) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=Build\M42ABC\Logs\$($case['Name']).stdout.txt"
}

$outPath = Join-Path $GeneratedDir 'm42abc_function_parameters_validation.txt'
[System.IO.File]::WriteAllLines($outPath, $Results, $Utf8NoBom)

$failures = @($Results | Where-Object { $_.StartsWith('FAIL|') })
if ($failures.Count -gt 0) { exit 1 }
exit 0
