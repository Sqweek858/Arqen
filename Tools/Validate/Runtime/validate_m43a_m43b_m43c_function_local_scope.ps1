param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M43ABC"
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
            Add-Result "PASS" "m43abc_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m43abc_driver_build" "dotnet publish failed; see Build\M43ABC\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m43abc_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M41_M45.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('define local runtime') -and $docText.Contains('__fn_') -and $docText.Contains('function scope')) { "PASS" } else { "FAIL" })) "m43c_docs_function_local_scope" "Docs\Milestones\\M41_M45.md documents function locals"

$spec = Join-Path $RepoRoot "Tests\CommandTests\misc\runtime_function_locals.command.txt"
$specText = if (Test-Path $spec) { Get-Content $spec -Raw } else { "" }
Add-Result ($(if ($specText.Contains('COMMAND_ID|runtime_function_locals') -and $specText.Contains('MILESTONE|M43') -and $specText.Contains('duplicate local')) { "PASS" } else { "FAIL" })) "m43c_spec_function_locals" "Tests\CommandTests\misc\runtime_function_locals.command.txt records M43 contract"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m43abc') -and $slice.Contains('function_local_scope')) { "PASS" } else { "FAIL" })) "m43c_slice_aliases" "run_test_slice exposes m43abc/m43a/m43b/m43c"

$keywordRegistry = Join-Path $GeneratedDir 'keyword_registry.txt'
$keywordText = if (Test-Path $keywordRegistry) { Get-Content $keywordRegistry -Raw } else { '' }
Add-Result ($(if ($keywordText.Contains('KEYWORD|local')) { 'PASS' } else { 'FAIL' })) "m43c_keyword_registry_local" "keyword registry includes local"

$registryGenerator = Join-Path $RepoRoot 'Tools\Generate\generate_runtime_action_registry.ps1'
if (Test-Path $registryGenerator) {
    Push-Location $RepoRoot
    try {
        & $registryGenerator *> (Join-Path $LogDir 'runtime_action_registry.build.log')
        $registryExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($registryExit -eq 0) { 'PASS' } else { 'FAIL' })) "m43c_runtime_action_registry_generation" "exit=$registryExit log=Build\M43ABC\Logs\runtime_action_registry.build.log"
} else {
    Add-Result 'FAIL' 'm43c_runtime_action_registry_generation' 'Tools\Generate\generate_runtime_action_registry.ps1 missing'
}

$catalogValidator = Join-Path $RepoRoot 'Tools\Validate\Core\validate_runtime_action_catalog.ps1'
if (Test-Path $catalogValidator) {
    Push-Location $RepoRoot
    try {
        & $catalogValidator *> (Join-Path $LogDir 'runtime_action_catalog.build.log')
        $catalogExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($catalogExit -eq 0) { 'PASS' } else { 'FAIL' })) "m43c_runtime_action_catalog_validation" "exit=$catalogExit log=Build\M43ABC\Logs\runtime_action_catalog.build.log"
} else {
    Add-Result 'FAIL' 'm43c_runtime_action_catalog_validation' 'Tools\Validate\Core\validate_runtime_action_catalog.ps1 missing'
}

$Cases = @(
    @{ Name='function_local_int_return'; ExpectExit=0; ExpectStdout="42`n"; RequireIr='locals=int:tmp:,__fn_next_local_tmp,function_return_int|path=|value_kind=slot|value=__fn_next_local_tmp'; Body=@'
define function called "next" with runtime int "x"
define local runtime int called "tmp" be 0
set runtime int "tmp" to "x"
add 1 to "tmp"
return runtime int "tmp"
end function
define runtime int called "out" be 0
set runtime int "out" to call function "next" with int 41
print "out"
'@ },
    @{ Name='function_local_string_return'; ExpectExit=0; ExpectStdout="Cryblo`n"; RequireIr='locals=string:out:,__fn_join_local_out,runtime_string_concat,function_call_assign'; Body=@'
define function called "join" with runtime string "left", runtime string "right"
define local runtime string called "out" be string ""
set runtime string "out" to "left" + "right"
return runtime string "out"
end function
define runtime string called "value" be string ""
set runtime string "value" to call function "join" with string "Cry" and string "blo"
print "value"
'@ },
    @{ Name='function_local_bool_if'; ExpectExit=0; ExpectStdout="ready`n"; RequireIr='locals=bool:ok:,__fn_gate_local_ok,runtime_if_bool,function_return_bool'; Body=@'
define function called "gate" with runtime bool "flag"
define local runtime bool called "ok" be false
set runtime bool "ok" to "flag"
runtime if "ok" is true
return runtime bool "ok"
end if
return bool false
end function
define runtime bool called "result" be false
set runtime bool "result" to call function "gate" with bool true
runtime if "result" is true
print string "ready"
end if
'@ },
    @{ Name='function_local_while'; ExpectExit=0; ExpectStdout="3`n"; RequireIr='locals=int:i:,__fn_count_local_i,runtime_while_int,function_return_int'; Body=@'
define function called "count"
define local runtime int called "i" be 0
runtime while "i" is less than 3
add 1 to "i"
end while
return runtime int "i"
end function
define runtime int called "out" be 0
set runtime int "out" to call function "count"
print "out"
'@ },
    @{ Name='function_local_same_name_two_functions'; ExpectExit=0; ExpectStdout="1`n2`n"; RequireIr='__fn_a_local_tmp,__fn_b_local_tmp,locals=int:tmp:'; Body=@'
define function called "a"
define local runtime int called "tmp" be 1
return runtime int "tmp"
end function
define function called "b"
define local runtime int called "tmp" be 2
return runtime int "tmp"
end function
define runtime int called "out" be 0
set runtime int "out" to call function "a"
print "out"
set runtime int "out" to call function "b"
print "out"
'@ },
    @{ Name='function_local_shadows_global'; ExpectExit=0; ExpectStdout="5`n99`n"; RequireIr='__fn_shadow_local_tmp,function_return_int|path=|value_kind=slot|value=__fn_shadow_local_tmp'; Body=@'
define runtime int called "tmp" be 99
define function called "shadow"
define local runtime int called "tmp" be 5
return runtime int "tmp"
end function
define runtime int called "out" be 0
set runtime int "out" to call function "shadow"
print "out"
print "tmp"
'@ },
    @{ Name='function_local_outside_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define local runtime int called "tmp" be 0
print string "bad"
'@ },
    @{ Name='function_local_duplicate_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "bad"
define local runtime int called "tmp" be 0
define local runtime string called "tmp" be string "x"
return int 0
end function
call function "bad"
'@ },
    @{ Name='function_local_param_conflict_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "bad" with runtime int "x"
define local runtime int called "x" be 0
return runtime int "x"
end function
define runtime int called "out" be 0
set runtime int "out" to call function "bad" with int 1
'@ },
    @{ Name='function_local_unknown_after_function_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "make"
define local runtime int called "tmp" be 1
return runtime int "tmp"
end function
print "tmp"
'@ },
    @{ Name='function_local_wrong_return_type_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "bad"
define local runtime string called "tmp" be string "x"
return runtime int "tmp"
end function
define runtime int called "out" be 0
set runtime int "out" to call function "bad"
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
        Add-Result 'FAIL' ('m43abc_build_' + $case['Name']) "exit=$buildExit expected=$($case['ExpectExit'])"
        continue
    }
    Add-Result 'PASS' ('m43abc_build_' + $case['Name']) "exit=$buildExit"

    if ($case['ExpectExit'] -ne 0) { continue }

    if ($case.ContainsKey('RequireIr')) {
        $irPath = Join-Path $RepoRoot ('Build\IR\' + $case['Name'] + '.arqir')
        $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { '' }
        foreach ($needle in ($case['RequireIr'].Split(','))) {
            Add-Result ($(if ($irText.Contains($needle)) { 'PASS' } else { 'FAIL' })) ('m43abc_ir_' + $case['Name'] + '_' + ($needle -replace '[^A-Za-z0-9_]+','_')) "$needle present"
        }
    }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result 'FAIL' ('m43abc_run_' + $case['Name']) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result 'FAIL' ('m43abc_run_' + $case['Name']) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq 0) { 'PASS' } else { 'FAIL' })) ('m43abc_run_' + $case['Name']) "exit=$($run.ExitCode)"

    $stdoutPath = Join-Path $LogDir ($case['Name'] + '.stdout.txt')
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case['ExpectStdout'], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case['ExpectStdout'])
    Add-Result ($(if ($ok) { 'PASS' } else { 'FAIL' })) ('m43abc_stdout_' + $case['Name']) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=$($stdoutPath.Substring($RepoRoot.Length + 1))"
}

$outFile = Join-Path $GeneratedDir "m43abc_function_local_scope_validation.txt"
Set-Content -Path $outFile -Value $Results -Encoding UTF8
Write-Host "OUT|$($outFile.Substring($RepoRoot.Length + 1))"

if ($Results | Where-Object { $_ -like 'FAIL|*' }) { exit 1 }
exit 0
