param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M39ABC"
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
            Add-Result "PASS" "m39abc_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m39abc_driver_build" "dotnet publish failed; see Build\M39ABC\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m39abc_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M36_M40.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('FUNCTION|') -and $docText.Contains('function_call') -and $docText.Contains('call/ret')) { "PASS" } else { "FAIL" })) "m39c_docs_function_ir_runtime" "Docs\Milestones\\M36_M40.md documents function IR/runtime"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m39abc') -and $slice.Contains('function_ir_runtime')) { "PASS" } else { "FAIL" })) "m39c_slice_aliases" "run_test_slice exposes m39abc/m39a/m39b/m39c"

$catalog = Join-Path $RepoRoot 'Docs\Reference\Runtime\RUNTIME_ACTION_CATALOG.txt'
$catalogText = if (Test-Path $catalog) { Get-Content $catalog -Raw } else { '' }
Add-Result ($(if ($catalogText.Contains('ACTION|function_call|fileio|supported|M39|runtime_function')) { 'PASS' } else { 'FAIL' })) "m39c_runtime_action_catalog_function_call" "Docs\Reference\Runtime\RUNTIME_ACTION_CATALOG.txt includes function_call"

$registryGenerator = Join-Path $RepoRoot 'Tools\Generate\generate_runtime_action_registry.ps1'
if (Test-Path $registryGenerator) {
    Push-Location $RepoRoot
    try {
        & $registryGenerator *> (Join-Path $LogDir 'runtime_action_registry.build.log')
        $registryExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($registryExit -eq 0) { 'PASS' } else { 'FAIL' })) "m39c_runtime_action_registry_generation" "exit=$registryExit log=Build\M39ABC\Logs\runtime_action_registry.build.log"
} else {
    Add-Result 'FAIL' 'm39c_runtime_action_registry_generation' 'Tools\Generate\generate_runtime_action_registry.ps1 missing'
}

$catalogValidator = Join-Path $RepoRoot 'Tools\Validate\Core\validate_runtime_action_catalog.ps1'
if (Test-Path $catalogValidator) {
    Push-Location $RepoRoot
    try {
        & $catalogValidator *> (Join-Path $LogDir 'runtime_action_catalog.build.log')
        $catalogExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($catalogExit -eq 0) { 'PASS' } else { 'FAIL' })) "m39c_runtime_action_catalog_validation" "exit=$catalogExit log=Build\M39ABC\Logs\runtime_action_catalog.build.log"
} else {
    Add-Result 'FAIL' 'm39c_runtime_action_catalog_validation' 'Tools\Validate\Core\validate_runtime_action_catalog.ps1 missing'
}

$Cases = @(
    @{ Name='function_ir_call_ret_basic'; ExpectExit=0; ExpectStdout="boot`n"; RequireIrFunctionDefinition=$true; RequireIrCall=$true; Body=@'
define function called "boot"
print string "boot"
end function
call function "boot"
'@ },
    @{ Name='function_body_not_auto_executed'; ExpectExit=0; ExpectStdout="main`n"; RequireIrFunctionDefinition=$true; RequireIrCall=$false; Body=@'
define function called "hidden"
print string "hidden"
end function
define runtime bool called "go" be true
runtime if "go" is true
print string "main"
end if
'@ },
    @{ Name='function_call_inside_runtime_while'; ExpectExit=0; ExpectStdout="1`n2`n3`n"; RequireIrFunctionDefinition=$true; RequireIrCall=$true; Body=@'
define runtime int called "i" be 0
define function called "tick"
add 1 to "i"
print "i"
end function
runtime while "i" is less than 3
call function "tick"
end while
'@ },
    @{ Name='function_call_multiple_times_runtime_state'; ExpectExit=0; ExpectStdout="1`n2`n"; RequireIrFunctionDefinition=$true; RequireIrCall=$true; Body=@'
define runtime int called "i" be 0
define function called "tick"
add 1 to "i"
print "i"
end function
call function "tick"
call function "tick"
'@ },
    @{ Name='function_contains_runtime_string_ops'; ExpectExit=0; ExpectStdout="Cryblo`nryb`n"; RequireIrFunctionDefinition=$true; RequireIrCall=$true; Body=@'
define runtime string called "left" be string "Cry"
define runtime string called "right" be string "blo"
define runtime string called "full" be string ""
define runtime string called "part" be string ""
define function called "compose"
set runtime string "full" to "left" + "right"
set runtime string "part" to substring "full" from 1 length 3
print "full"
print "part"
end function
call function "compose"
'@ },
    @{ Name='function_missing_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
call function "missing"
'@ },
    @{ Name='function_duplicate_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "dup"
print string "a"
end function
define function called "dup"
print string "b"
end function
'@ },
    @{ Name='function_recursive_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "loop"
call function "loop"
end function
call function "loop"
'@ },
    @{ Name='function_nested_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "outer"
define function called "inner"
print string "bad"
end function
end function
call function "outer"
'@ },
    @{ Name='function_break_outside_while_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "bad"
break
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
        Add-Result 'FAIL' ('m39abc_build_' + $case['Name']) "exit=$buildExit expected=$($case['ExpectExit'])"
        continue
    }
    Add-Result 'PASS' ('m39abc_build_' + $case['Name']) "exit=$buildExit"

    if ($case['ExpectExit'] -ne 0) { continue }

    $irPath = Join-Path $RepoRoot ('Build\IR\' + $case['Name'] + '.arqir')
    $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { '' }
    $requiresFunctionDefinition = $case.ContainsKey('RequireIrFunctionDefinition') -and [bool]$case['RequireIrFunctionDefinition']
    $requiresFunctionCall = $case.ContainsKey('RequireIrCall') -and [bool]$case['RequireIrCall']
    if ($requiresFunctionDefinition -or $requiresFunctionCall) {
        $hasFunctionDefinition = $irText.Contains('FUNCTION|name=')
        $hasFunctionCall = $irText.Contains('op=function_call')
        $ok = ($hasFunctionDefinition -eq $requiresFunctionDefinition) -and ($hasFunctionCall -eq $requiresFunctionCall)
        $note = "FUNCTION=$hasFunctionDefinition expected=$requiresFunctionDefinition function_call=$hasFunctionCall expected=$requiresFunctionCall"
        Add-Result ($(if ($ok) { 'PASS' } else { 'FAIL' })) ('m39abc_ir_function_model_' + $case['Name']) $note
    }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result 'FAIL' ('m39abc_run_' + $case['Name']) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result 'FAIL' ('m39abc_run_' + $case['Name']) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq 0) { 'PASS' } else { 'FAIL' })) ('m39abc_run_' + $case['Name']) "exit=$($run.ExitCode)"

    $stdoutPath = Join-Path $LogDir ($case['Name'] + '.stdout.txt')
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case['ExpectStdout'], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case['ExpectStdout'])
    Add-Result ($(if ($ok) { 'PASS' } else { 'FAIL' })) ('m39abc_stdout_' + $case['Name']) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=Build\M39ABC\Logs\$($case['Name']).stdout.txt"
}

$outPath = Join-Path $GeneratedDir 'm39abc_function_ir_runtime_validation.txt'
[System.IO.File]::WriteAllLines($outPath, $Results, $Utf8NoBom)
Write-Host 'OUT|Build\Generated\m39abc_function_ir_runtime_validation.txt'

if ($Results | Where-Object { $_.StartsWith('FAIL|') }) { exit 1 }
exit 0
