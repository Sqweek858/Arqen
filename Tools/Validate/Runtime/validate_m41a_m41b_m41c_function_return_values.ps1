param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M41ABC"
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
            Add-Result "PASS" "m41abc_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m41abc_driver_build" "dotnet publish failed; see Build\M41ABC\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m41abc_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M41_M45.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('function_return_int') -and $docText.Contains('function_call_assign') -and $docText.Contains('typed return values')) { "PASS" } else { "FAIL" })) "m41c_docs_function_return_values" "Docs\Milestones\\M41_M45.md documents typed function return values"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m41abc') -and $slice.Contains('function_return_values')) { "PASS" } else { "FAIL" })) "m41c_slice_aliases" "run_test_slice exposes m41abc/m41a/m41b/m41c"

$catalog = Join-Path $RepoRoot 'Docs\Reference\Runtime\RUNTIME_ACTION_CATALOG.txt'
$catalogText = if (Test-Path $catalog) { Get-Content $catalog -Raw } else { '' }
Add-Result ($(if ($catalogText.Contains('ACTION|function_call_assign|fileio|supported|M41|runtime_function') -and $catalogText.Contains('ACTION|function_return_int|fileio|supported|M41|runtime_function') -and $catalogText.Contains('ACTION|function_return_string|fileio|supported|M41|runtime_function')) { 'PASS' } else { 'FAIL' })) "m41c_runtime_action_catalog_typed_returns" "Docs\Reference\Runtime\RUNTIME_ACTION_CATALOG.txt includes M41 return actions"

$registryGenerator = Join-Path $RepoRoot 'Tools\Generate\generate_runtime_action_registry.ps1'
if (Test-Path $registryGenerator) {
    Push-Location $RepoRoot
    try {
        & $registryGenerator *> (Join-Path $LogDir 'runtime_action_registry.build.log')
        $registryExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($registryExit -eq 0) { 'PASS' } else { 'FAIL' })) "m41c_runtime_action_registry_generation" "exit=$registryExit log=Build\M41ABC\Logs\runtime_action_registry.build.log"
} else {
    Add-Result 'FAIL' 'm41c_runtime_action_registry_generation' 'Tools\Generate\generate_runtime_action_registry.ps1 missing'
}

$catalogValidator = Join-Path $RepoRoot 'Tools\Validate\Core\validate_runtime_action_catalog.ps1'
if (Test-Path $catalogValidator) {
    Push-Location $RepoRoot
    try {
        & $catalogValidator *> (Join-Path $LogDir 'runtime_action_catalog.build.log')
        $catalogExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($catalogExit -eq 0) { 'PASS' } else { 'FAIL' })) "m41c_runtime_action_catalog_validation" "exit=$catalogExit log=Build\M41ABC\Logs\runtime_action_catalog.build.log"
} else {
    Add-Result 'FAIL' 'm41c_runtime_action_catalog_validation' 'Tools\Validate\Core\validate_runtime_action_catalog.ps1 missing'
}

$Cases = @(
    @{ Name='function_return_int_static_assign'; ExpectExit=0; ExpectStdout="42`n"; RequireIr='function_return_int,function_call_assign'; Body=@'
define function called "answer"
return int 42
end function
define runtime int called "x" be 0
set runtime int "x" to call function "answer"
print "x"
'@ },
    @{ Name='function_return_bool_static_assign'; ExpectExit=0; ExpectStdout="ready`n"; RequireIr='function_return_bool,function_call_assign'; Body=@'
define function called "ready_fn"
return bool true
end function
define runtime bool called "ready" be false
set runtime bool "ready" to call function "ready_fn"
runtime if "ready" is true
print string "ready"
end if
'@ },
    @{ Name='function_return_string_static_assign'; ExpectExit=0; ExpectStdout="Cryblo`n"; RequireIr='function_return_string,function_call_assign'; Body=@'
define function called "name_fn"
return string "Cryblo"
end function
define runtime string called "name" be string ""
set runtime string "name" to call function "name_fn"
print "name"
'@ },
    @{ Name='function_return_runtime_slots'; ExpectExit=0; ExpectStdout="15`nCryblo`n"; RequireIr='function_return_int,function_return_string,function_call_assign'; Body=@'
define runtime int called "seed" be 15
define runtime string called "left" be string "Cry"
define runtime string called "right" be string "blo"
define runtime string called "full" be string ""
define function called "get_seed"
return runtime int "seed"
end function
define function called "get_name"
set runtime string "full" to "left" + "right"
return runtime string "full"
end function
define runtime int called "x" be 0
define runtime string called "name" be string ""
set runtime int "x" to call function "get_seed"
set runtime string "name" to call function "get_name"
print "x"
print "name"
'@ },
    @{ Name='function_return_early_typed_if_while'; ExpectExit=0; ExpectStdout="3`n"; RequireIr='function_return_int,function_return'; Body=@'
define runtime int called "i" be 0
define function called "stop_at_three"
runtime while "i" is less than 9
add 1 to "i"
runtime if "i" equals 3
return runtime int "i"
end if
end while
return int 0
end function
define runtime int called "result" be 0
set runtime int "result" to call function "stop_at_three"
print "result"
'@ },
    @{ Name='function_return_void_assign_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "noop"
print string "x"
end function
define runtime int called "x" be 0
set runtime int "x" to call function "noop"
'@ },
    @{ Name='function_return_type_mismatch_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "answer"
return int 42
end function
define runtime string called "s" be string ""
set runtime string "s" to call function "answer"
'@ },
    @{ Name='function_return_mixed_types_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime bool called "flag" be true
define function called "bad"
runtime if "flag" is true
return int 1
end if
return string "bad"
end function
define runtime int called "x" be 0
set runtime int "x" to call function "bad"
'@ },
    @{ Name='function_return_runtime_string_requires_slot_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime int called "count" be 7
define function called "bad"
return runtime string "count"
end function
call function "bad"
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
        Add-Result 'FAIL' ('m41abc_build_' + $case['Name']) "exit=$buildExit expected=$($case['ExpectExit'])"
        continue
    }
    Add-Result 'PASS' ('m41abc_build_' + $case['Name']) "exit=$buildExit"

    if ($case['ExpectExit'] -ne 0) { continue }

    if ($case.ContainsKey('RequireIr')) {
        $irPath = Join-Path $RepoRoot ('Build\IR\' + $case['Name'] + '.arqir')
        $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { '' }
        foreach ($needle in ($case['RequireIr'].Split(','))) {
            Add-Result ($(if ($irText.Contains($needle)) { 'PASS' } else { 'FAIL' })) ('m41abc_ir_' + $case['Name'] + '_' + $needle) "$needle present"
        }
    }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result 'FAIL' ('m41abc_run_' + $case['Name']) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result 'FAIL' ('m41abc_run_' + $case['Name']) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq 0) { 'PASS' } else { 'FAIL' })) ('m41abc_run_' + $case['Name']) "exit=$($run.ExitCode)"

    $stdoutPath = Join-Path $LogDir ($case['Name'] + '.stdout.txt')
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case['ExpectStdout'], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case['ExpectStdout'])
    Add-Result ($(if ($ok) { 'PASS' } else { 'FAIL' })) ('m41abc_stdout_' + $case['Name']) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=Build\M41ABC\Logs\$($case['Name']).stdout.txt"
}

$outPath = Join-Path $GeneratedDir 'm41abc_function_return_values_validation.txt'
[System.IO.File]::WriteAllLines($outPath, $Results, $Utf8NoBom)
Write-Host 'OUT|Build\Generated\m41abc_function_return_values_validation.txt'

if ($Results | Where-Object { $_.StartsWith('FAIL|') }) { exit 1 }
exit 0
