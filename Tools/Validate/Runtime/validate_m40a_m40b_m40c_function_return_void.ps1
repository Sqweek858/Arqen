param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M40ABC"
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
            Add-Result "PASS" "m40abc_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m40abc_driver_build" "dotnet publish failed; see Build\M40ABC\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m40abc_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M36_M40.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('function_return') -and $docText.Contains('return') -and $docText.Contains('no return values')) { "PASS" } else { "FAIL" })) "m40c_docs_function_return_void" "Docs\Milestones\\M36_M40.md documents void return"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m40abc') -and $slice.Contains('function_return_void')) { "PASS" } else { "FAIL" })) "m40c_slice_aliases" "run_test_slice exposes m40abc/m40a/m40b/m40c"

$catalog = Join-Path $RepoRoot 'Docs\Reference\Runtime\RUNTIME_ACTION_CATALOG.txt'
$catalogText = if (Test-Path $catalog) { Get-Content $catalog -Raw } else { '' }
Add-Result ($(if ($catalogText.Contains('ACTION|function_return|fileio|supported|M40|runtime_function')) { 'PASS' } else { 'FAIL' })) "m40c_runtime_action_catalog_function_return" "Docs\Reference\Runtime\RUNTIME_ACTION_CATALOG.txt includes function_return"

$registryGenerator = Join-Path $RepoRoot 'Tools\Generate\generate_runtime_action_registry.ps1'
if (Test-Path $registryGenerator) {
    Push-Location $RepoRoot
    try {
        & $registryGenerator *> (Join-Path $LogDir 'runtime_action_registry.build.log')
        $registryExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($registryExit -eq 0) { 'PASS' } else { 'FAIL' })) "m40c_runtime_action_registry_generation" "exit=$registryExit log=Build\M40ABC\Logs\runtime_action_registry.build.log"
} else {
    Add-Result 'FAIL' 'm40c_runtime_action_registry_generation' 'Tools\Generate\generate_runtime_action_registry.ps1 missing'
}

$catalogValidator = Join-Path $RepoRoot 'Tools\Validate\Core\validate_runtime_action_catalog.ps1'
if (Test-Path $catalogValidator) {
    Push-Location $RepoRoot
    try {
        & $catalogValidator *> (Join-Path $LogDir 'runtime_action_catalog.build.log')
        $catalogExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($catalogExit -eq 0) { 'PASS' } else { 'FAIL' })) "m40c_runtime_action_catalog_validation" "exit=$catalogExit log=Build\M40ABC\Logs\runtime_action_catalog.build.log"
} else {
    Add-Result 'FAIL' 'm40c_runtime_action_catalog_validation' 'Tools\Validate\Core\validate_runtime_action_catalog.ps1 missing'
}

$Cases = @(
    @{ Name='function_return_basic'; ExpectExit=0; ExpectStdout="before`n"; RequireIrFunctionReturn=$true; Body=@'
define function called "early"
print string "before"
return
print string "after"
end function
call function "early"
'@ },
    @{ Name='function_return_inside_runtime_if'; ExpectExit=0; ExpectStdout="enter`ndone`n"; RequireIrFunctionReturn=$true; Body=@'
define runtime bool called "stop" be true
define function called "check"
print string "enter"
runtime if "stop" is true
return
end if
print string "bad"
end function
call function "check"
print string "done"
'@ },
    @{ Name='function_return_inside_runtime_while'; ExpectExit=0; ExpectStdout="3`n"; RequireIrFunctionReturn=$true; Body=@'
define runtime int called "i" be 0
define function called "loop"
runtime while "i" is less than 5
add 1 to "i"
runtime if "i" equals 3
return
end if
end while
print string "bad"
end function
call function "loop"
print "i"
'@ },
    @{ Name='function_without_return_still_returns'; ExpectExit=0; ExpectStdout="normal`ndone`n"; RequireIrFunctionReturn=$false; Body=@'
define function called "normal"
print string "normal"
end function
call function "normal"
print string "done"
'@ },
    @{ Name='function_return_multiple_calls'; ExpectExit=0; ExpectStdout="hit`nhit`nafter`n"; RequireIrFunctionReturn=$true; Body=@'
define runtime bool called "skip" be true
define function called "once"
print string "hit"
runtime if "skip" is true
return
end if
print string "bad"
end function
call function "once"
call function "once"
print string "after"
'@ },
    @{ Name='function_return_outside_function_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
return
'@ },
    @{ Name='function_return_unknown_type_rejected_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "bad"
return float 1
end function
call function "bad"
'@ },
    @{ Name='function_return_missing_value_rejected_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define function called "bad"
return int
end function
call function "bad"
'@ },
    @{ Name='function_return_top_level_runtime_if_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime bool called "go" be true
runtime if "go" is true
return
end if
'@ },
    @{ Name='function_return_top_level_runtime_while_negative'; ExpectExit=1; ExpectStdout=$null; Body=@'
define runtime int called "i" be 0
runtime while "i" is less than 1
return
end while
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
        Add-Result 'FAIL' ('m40abc_build_' + $case['Name']) "exit=$buildExit expected=$($case['ExpectExit'])"
        continue
    }
    Add-Result 'PASS' ('m40abc_build_' + $case['Name']) "exit=$buildExit"

    if ($case['ExpectExit'] -ne 0) { continue }

    $irPath = Join-Path $RepoRoot ('Build\IR\' + $case['Name'] + '.arqir')
    $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { '' }
    if ($case.ContainsKey('RequireIrFunctionReturn')) {
        $expectedReturn = [bool]$case['RequireIrFunctionReturn']
        $hasReturn = $irText.Contains('op=function_return')
        Add-Result ($(if ($hasReturn -eq $expectedReturn) { 'PASS' } else { 'FAIL' })) ('m40abc_ir_function_return_' + $case['Name']) "function_return=$hasReturn expected=$expectedReturn"
    }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result 'FAIL' ('m40abc_run_' + $case['Name']) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result 'FAIL' ('m40abc_run_' + $case['Name']) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq 0) { 'PASS' } else { 'FAIL' })) ('m40abc_run_' + $case['Name']) "exit=$($run.ExitCode)"

    $stdoutPath = Join-Path $LogDir ($case['Name'] + '.stdout.txt')
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case['ExpectStdout'], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case['ExpectStdout'])
    Add-Result ($(if ($ok) { 'PASS' } else { 'FAIL' })) ('m40abc_stdout_' + $case['Name']) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=Build\M40ABC\Logs\$($case['Name']).stdout.txt"
}

$outPath = Join-Path $GeneratedDir 'm40abc_function_return_void_validation.txt'
[System.IO.File]::WriteAllLines($outPath, $Results, $Utf8NoBom)
Write-Host 'OUT|Build\Generated\m40abc_function_return_void_validation.txt'

if ($Results | Where-Object { $_.StartsWith('FAIL|') }) { exit 1 }
exit 0
