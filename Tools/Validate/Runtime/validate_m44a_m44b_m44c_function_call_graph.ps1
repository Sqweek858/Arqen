param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M44ABC"
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
            Add-Result "PASS" "m44abc_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m44abc_driver_build" "dotnet publish failed; see Build\M44ABC\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m44abc_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M41_M45.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('function call graph') -and $docText.Contains('function_call_assign') -and $docText.Contains('define-before-call')) { "PASS" } else { "FAIL" })) "m44c_docs_function_call_graph" "Docs\Milestones\\M41_M45.md documents call graph hardening"

$spec = Join-Path $RepoRoot "Tests\CommandTests\misc\runtime_function_call_graph.command.txt"
$specText = if (Test-Path $spec) { Get-Content $spec -Raw } else { "" }
Add-Result ($(if ($specText.Contains('COMMAND_ID|runtime_function_call_graph') -and $specText.Contains('MILESTONE|M44') -and $specText.Contains('cyclic call graphs')) { "PASS" } else { "FAIL" })) "m44c_spec_function_call_graph" "Tests\CommandTests\misc\runtime_function_call_graph.command.txt records M44 contract"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m44abc') -and $slice.Contains('function_call_graph')) { "PASS" } else { "FAIL" })) "m44c_slice_aliases" "run_test_slice exposes m44abc/m44a/m44b/m44c"

$parserText = Get-Content (Join-Path $RepoRoot "Tools\M10GDriver\Parser\Parser.Statements.cs") -Raw
Add-Result ($(if ($parserText.Contains('ValidateFunctionCallGraph') -and $parserText.Contains('S170') -and $parserText.Contains('Recursive function call graph')) { "PASS" } else { "FAIL" })) "m44c_parser_call_graph_validation" "parser contains M44 call graph validation"

$registryGenerator = Join-Path $RepoRoot 'Tools\Generate\generate_runtime_action_registry.ps1'
if (Test-Path $registryGenerator) {
    Push-Location $RepoRoot
    try {
        & $registryGenerator *> (Join-Path $LogDir 'runtime_action_registry.build.log')
        $registryExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($registryExit -eq 0) { 'PASS' } else { 'FAIL' })) "m44c_runtime_action_registry_generation" "exit=$registryExit log=Build\M44ABC\Logs\runtime_action_registry.build.log"
} else {
    Add-Result 'FAIL' 'm44c_runtime_action_registry_generation' 'Tools\Generate\generate_runtime_action_registry.ps1 missing'
}

$catalogValidator = Join-Path $RepoRoot 'Tools\Validate\Core\validate_runtime_action_catalog.ps1'
if (Test-Path $catalogValidator) {
    Push-Location $RepoRoot
    try {
        & $catalogValidator *> (Join-Path $LogDir 'runtime_action_catalog.build.log')
        $catalogExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($catalogExit -eq 0) { 'PASS' } else { 'FAIL' })) "m44c_runtime_action_catalog_validation" "exit=$catalogExit log=Build\M44ABC\Logs\runtime_action_catalog.build.log"
} else {
    Add-Result 'FAIL' 'm44c_runtime_action_catalog_validation' 'Tools\Validate\Core\validate_runtime_action_catalog.ps1 missing'
}

$Cases = @(
    @{ Name='function_calls_function_void'; ExpectExit=0; ExpectStdout="log`nboot`n"; RequireIr='FUNCTION|name=log,function_call|path=|value_kind=static|value=|target=log,FUNCTION|name=boot'; Body=@'
define function called "log"
print string "log"
end function

define function called "boot"
call function "log"
print string "boot"
end function

call function "boot"
'@ },
    @{ Name='function_nested_typed_call_assign_int'; ExpectExit=0; ExpectStdout="42`n"; RequireIr='function_call_assign|path=int|value_kind=static|value=base|target=__fn_next_local_x,__fn_next_local_x,function_return_int'; Body=@'
define function called "base"
return int 41
end function

define function called "next"
define local runtime int called "x" be 0
set runtime int "x" to call function "base"
add 1 to "x"
return runtime int "x"
end function

define runtime int called "out" be 0
set runtime int "out" to call function "next"
print "out"
'@ },
    @{ Name='function_params_returns_locals_chain'; ExpectExit=0; ExpectStdout="42`n"; RequireIr='__fn_inc_param_x,__fn_inc_local_tmp,__fn_twice_param_v,__fn_twice_local_a,__fn_twice_local_b,function_call_assign|path=int|value_kind=static|value=inc|target=__fn_twice_local_a,function_call_assign|path=int|value_kind=static|value=twice|target=out'; Body=@'
define function called "inc" with runtime int "x"
define local runtime int called "tmp" be 0
set runtime int "tmp" to "x"
add 1 to "tmp"
return runtime int "tmp"
end function

define function called "twice" with runtime int "v"
define local runtime int called "a" be 0
define local runtime int called "b" be 0
set runtime int "a" to call function "inc" with runtime int "v"
set runtime int "b" to call function "inc" with runtime int "a"
return runtime int "b"
end function

define runtime int called "out" be 0
set runtime int "out" to call function "twice" with int 40
print "out"
'@ },
    @{ Name='function_nested_string_compose'; ExpectExit=0; ExpectStdout="Cryblo`n"; RequireIr='FUNCTION|name=prefix,function_call_assign|path=string|value_kind=static|value=prefix|target=__fn_compose_local_left,runtime_string_concat,function_call_assign|path=string|value_kind=static|value=compose|target=out'; Body=@'
define function called "prefix"
return string "Cry"
end function

define function called "compose" with runtime string "suffix"
define local runtime string called "left" be string ""
define local runtime string called "out" be string ""
set runtime string "left" to call function "prefix"
set runtime string "out" to "left" + "suffix"
return runtime string "out"
end function

define runtime string called "out" be string ""
set runtime string "out" to call function "compose" with string "blo"
print "out"
'@ },
    @{ Name='function_nested_bool_gate'; ExpectExit=0; ExpectStdout="ready`n"; RequireIr='function_call_assign|path=bool|value_kind=static|value=is_ready|target=__fn_gate_local_ok,runtime_if_bool,function_return_bool'; Body=@'
define function called "is_ready" with runtime bool "flag"
return runtime bool "flag"
end function

define function called "gate" with runtime bool "flag"
define local runtime bool called "ok" be false
set runtime bool "ok" to call function "is_ready" with runtime bool "flag"
runtime if "ok" is true
return bool true
end if
return bool false
end function

define runtime bool called "result" be false
set runtime bool "result" to call function "gate" with bool true
runtime if "result" is true
print string "ready"
end if
'@ },
    @{ Name='function_nested_direct_recursion_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "bad"
call function "bad"
end function
call function "bad"
'@ },
    @{ Name='function_nested_missing_function_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "bad"
call function "missing"
end function
call function "bad"
'@ },
    @{ Name='function_nested_type_mismatch_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "text"
return string "bad"
end function

define function called "bad"
define local runtime int called "x" be 0
set runtime int "x" to call function "text"
return runtime int "x"
end function

define runtime int called "out" be 0
set runtime int "out" to call function "bad"
'@ },
    @{ Name='function_nested_wrong_arg_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "inc" with runtime int "x"
return runtime int "x"
end function

define function called "bad"
define local runtime int called "x" be 0
set runtime int "x" to call function "inc" with string "oops"
return runtime int "x"
end function

define runtime int called "out" be 0
set runtime int "out" to call function "bad"
'@ },
    @{ Name='function_nested_forward_call_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "caller"
call function "later"
end function

define function called "later"
print string "later"
end function

call function "caller"
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
        Add-Result 'FAIL' ('m44abc_build_' + $case['Name']) "exit=$buildExit expected=$($case['ExpectExit'])"
        continue
    }
    Add-Result 'PASS' ('m44abc_build_' + $case['Name']) "exit=$buildExit"

    if ($case['ExpectExit'] -ne 0) { continue }

    if ($case.ContainsKey('RequireIr')) {
        $irPath = Join-Path $RepoRoot ('Build\IR\' + $case['Name'] + '.arqir')
        $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { '' }
        foreach ($needle in ($case['RequireIr'].Split(','))) {
            Add-Result ($(if ($irText.Contains($needle)) { 'PASS' } else { 'FAIL' })) ('m44abc_ir_' + $case['Name'] + '_' + ($needle -replace '[^A-Za-z0-9_]+','_')) "$needle present"
        }
    }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result 'FAIL' ('m44abc_run_' + $case['Name']) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result 'FAIL' ('m44abc_run_' + $case['Name']) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq 0) { 'PASS' } else { 'FAIL' })) ('m44abc_run_' + $case['Name']) "exit=$($run.ExitCode)"

    $stdoutPath = Join-Path $LogDir ($case['Name'] + '.stdout.txt')
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case['ExpectStdout'], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case['ExpectStdout'])
    Add-Result ($(if ($ok) { 'PASS' } else { 'FAIL' })) ('m44abc_stdout_' + $case['Name']) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=$($stdoutPath.Substring($RepoRoot.Length + 1))"
}

$outFile = Join-Path $GeneratedDir "m44abc_function_call_graph_validation.txt"
Set-Content -Path $outFile -Value $Results -Encoding UTF8
Write-Host "OUT|$($outFile.Substring($RepoRoot.Length + 1))"

if ($Results | Where-Object { $_ -like 'FAIL|*' }) { exit 1 }
exit 0
