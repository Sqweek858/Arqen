param(
    [int]$TimeoutSeconds = 10,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$OutRoot = Join-Path $RepoRoot "Build\M45M46"
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
            Add-Result "PASS" "m45m46_driver_build" "arqc_m10g.exe rebuilt"
        } else {
            Add-Result "FAIL" "m45m46_driver_build" "dotnet publish failed; see Build\M45M46\Logs\driver_publish.log"
        }
    } finally { Pop-Location }
}

$Driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Add-Result ($(if (Test-Path $Driver) { "PASS" } else { "FAIL" })) "m45m46_driver_exists" "Tools\arqc_m10g.exe"

$doc = Join-Path $RepoRoot "Docs\Milestones\\M41_M45.md"
$docText = if (Test-Path $doc) { Get-Content $doc -Raw } else { "" }
Add-Result ($(if ($docText.Contains('Runtime int arrays') -and $docText.Contains('dynamic runtime-int indexing') -and $docText.Contains('runtime_trap_if_bool_false')) { "PASS" } else { "FAIL" })) "m45m46_docs_runtime_int_arrays" "Docs\Milestones\\M41_M45.md documents arrays"

$spec = Join-Path $RepoRoot "Tests\CommandTests\misc\runtime_int_arrays.command.txt"
$specText = if (Test-Path $spec) { Get-Content $spec -Raw } else { "" }
Add-Result ($(if ($specText.Contains('COMMAND_ID|runtime_int_arrays') -and $specText.Contains('MILESTONE|M45_M46') -and $specText.Contains('runtime_trap_if_bool_false')) { "PASS" } else { "FAIL" })) "m45m46_spec_runtime_int_arrays" "Tests\CommandTests\misc\runtime_int_arrays.command.txt records M45/M46"

$slice = Get-Content (Join-Path $RepoRoot "Tools\Internal\Test\run_test_slice.ps1") -Raw
Add-Result ($(if ($slice.Contains('m45m46') -and $slice.Contains('runtime_int_arrays')) { "PASS" } else { "FAIL" })) "m45m46_slice_aliases" "run_test_slice exposes m45m46/m45/m46"

$catalog = Join-Path $RepoRoot "Docs\Reference\Runtime\RUNTIME_ACTION_CATALOG.txt"
$catalogText = if (Test-Path $catalog) { Get-Content $catalog -Raw } else { "" }
Add-Result ($(if ($catalogText.Contains('ACTION|runtime_trap_if_bool_false|fileio|supported|M45_M46|runtime_array')) { "PASS" } else { "FAIL" })) "m45m46_catalog_trap_action" "runtime action catalog includes bounds trap"

$registryGenerator = Join-Path $RepoRoot 'Tools\Generate\generate_runtime_action_registry.ps1'
if (Test-Path $registryGenerator) {
    Push-Location $RepoRoot
    try {
        & $registryGenerator *> (Join-Path $LogDir 'runtime_action_registry.build.log')
        $registryExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($registryExit -eq 0) { 'PASS' } else { 'FAIL' })) "m45m46_runtime_action_registry_generation" "exit=$registryExit log=Build\M45M46\Logs\runtime_action_registry.build.log"
} else {
    Add-Result 'FAIL' 'm45m46_runtime_action_registry_generation' 'Tools\Generate\generate_runtime_action_registry.ps1 missing'
}

$catalogValidator = Join-Path $RepoRoot 'Tools\Validate\Core\validate_runtime_action_catalog.ps1'
if (Test-Path $catalogValidator) {
    Push-Location $RepoRoot
    try {
        & $catalogValidator *> (Join-Path $LogDir 'runtime_action_catalog.build.log')
        $catalogExit = if ($null -eq $LASTEXITCODE) { 1 } else { [int]$LASTEXITCODE }
    } finally { Pop-Location }
    Add-Result ($(if ($catalogExit -eq 0) { 'PASS' } else { 'FAIL' })) "m45m46_runtime_action_catalog_validation" "exit=$catalogExit log=Build\M45M46\Logs\runtime_action_catalog.build.log"
} else {
    Add-Result 'FAIL' 'm45m46_runtime_action_catalog_validation' 'Tools\Validate\Core\validate_runtime_action_catalog.ps1 missing'
}

$Cases = @(
    @{ Name='runtime_int_array_static_set_get'; BuildExit=0; RunExit=0; ExpectStdout="42`n"; RequireIr='__arr_values_0,__arr_values_1,__arr_values_2,runtime_int_set|path=|value_kind=slot|value=__arr_values_2|target=out'; Body=@'
define runtime int array called "values" size 3
set runtime int array "values" at 0 to 40
set runtime int array "values" at 1 to 41
set runtime int array "values" at 2 to 42
define runtime int called "out" be 0
set runtime int "out" to runtime int array "values" at 2
print "out"
'@ },
    @{ Name='runtime_int_array_static_set_from_slot'; BuildExit=0; RunExit=0; ExpectStdout="77`n"; RequireIr='runtime_int_set|path=|value_kind=slot|value=source|target=__arr_values_1'; Body=@'
define runtime int array called "values" size 2
define runtime int called "source" be 77
set runtime int array "values" at 1 to "source"
define runtime int called "out" be 0
set runtime int "out" to runtime int array "values" at 1
print "out"
'@ },
    @{ Name='runtime_int_array_dynamic_set_get'; BuildExit=0; RunExit=0; ExpectStdout="99`n"; RequireIr='runtime_trap_if_bool_false,__arr_values_bounds_ok_,__arr_values_index_,runtime_if_int|path=eq|value_kind=static|value=1'; Body=@'
define runtime int array called "values" size 3
define runtime int called "i" be 1
set runtime int array "values" at runtime int "i" to 99
define runtime int called "out" be 0
set runtime int "out" to runtime int array "values" at runtime int "i"
print "out"
'@ },
    @{ Name='runtime_int_array_dynamic_get_target_same_as_index'; BuildExit=0; RunExit=0; ExpectStdout="42`n"; RequireIr='__arr_values_index_'; Body=@'
define runtime int array called "values" size 3
set runtime int array "values" at 2 to 42
define runtime int called "i" be 2
set runtime int "i" to runtime int array "values" at runtime int "i"
print "i"
'@ },
    @{ Name='runtime_int_array_inside_functions'; BuildExit=0; RunExit=0; ExpectStdout="42`n"; RequireIr='FUNCTION|name=fill,FUNCTION|name=read_last,__fn_read_last_local_tmp,function_call_assign|path=int|value_kind=static|value=read_last|target=out'; Body=@'
define runtime int array called "values" size 3

define function called "fill"
set runtime int array "values" at 0 to 40
set runtime int array "values" at 1 to 41
set runtime int array "values" at 2 to 42
end function

define function called "read_last"
define local runtime int called "tmp" be 0
set runtime int "tmp" to runtime int array "values" at 2
return runtime int "tmp"
end function

call function "fill"
define runtime int called "out" be 0
set runtime int "out" to call function "read_last"
print "out"
'@ },
    @{ Name='runtime_int_array_dynamic_bounds_trap'; BuildExit=0; RunExit=1; ExpectStdout=""; RequireIr='runtime_trap_if_bool_false'; Body=@'
define runtime int array called "values" size 2
define runtime int called "i" be 5
define runtime int called "out" be 0
set runtime int "out" to runtime int array "values" at runtime int "i"
print "out"
'@ },
    @{ Name='runtime_int_array_size_zero_negative'; BuildExit=1; Body=@'
define runtime int array called "values" size 0
'@ },
    @{ Name='runtime_int_array_static_oob_negative'; BuildExit=1; Body=@'
define runtime int array called "values" size 2
set runtime int array "values" at 2 to 42
'@ },
    @{ Name='runtime_int_array_missing_negative'; BuildExit=1; Body=@'
define runtime int called "out" be 0
set runtime int "out" to runtime int array "missing" at 0
'@ },
    @{ Name='runtime_int_array_wrong_dynamic_index_negative'; BuildExit=1; Body=@'
define runtime int array called "values" size 2
define runtime string called "idx" be string "1"
define runtime int called "out" be 0
set runtime int "out" to runtime int array "values" at runtime int "idx"
'@ },
    @{ Name='runtime_int_array_symbol_collision_negative'; BuildExit=1; Body=@'
define runtime int called "values" be 0
define runtime int array called "values" size 2
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
        Add-Result 'FAIL' ('m45m46_build_' + $case['Name']) "exit=$buildExit expected=$($case['BuildExit'])"
        continue
    }
    Add-Result 'PASS' ('m45m46_build_' + $case['Name']) "exit=$buildExit"

    if ($case['BuildExit'] -ne 0) { continue }

    if ($case.ContainsKey('RequireIr')) {
        $irPath = Join-Path $RepoRoot ('Build\IR\' + $case['Name'] + '.arqir')
        $irText = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { '' }
        foreach ($needle in ($case['RequireIr'].Split(','))) {
            Add-Result ($(if ($irText.Contains($needle)) { 'PASS' } else { 'FAIL' })) ('m45m46_ir_' + $case['Name'] + '_' + ($needle -replace '[^A-Za-z0-9_]+','_')) "$needle present"
        }
    }

    $run = Invoke-Exe $exePath $runCaseDir $TimeoutSeconds
    if ($run.StartFailed) {
        Add-Result 'FAIL' ('m45m46_run_' + $case['Name']) "start_failed=$($run.Stderr)"
        continue
    }
    if ($run.TimedOut) {
        Add-Result 'FAIL' ('m45m46_run_' + $case['Name']) "timeout=${TimeoutSeconds}s"
        continue
    }
    Add-Result ($(if ($run.ExitCode -eq $case['RunExit']) { 'PASS' } else { 'FAIL' })) ('m45m46_run_' + $case['Name']) "exit=$($run.ExitCode) expected=$($case['RunExit'])"

    $stdoutPath = Join-Path $LogDir ($case['Name'] + '.stdout.txt')
    Write-TextFile $stdoutPath $run.Stdout
    $ok = [string]::Equals($run.Stdout, $case['ExpectStdout'], [System.StringComparison]::Ordinal)
    $actualBytes = [System.Text.Encoding]::UTF8.GetByteCount($run.Stdout)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetByteCount($case['ExpectStdout'])
    Add-Result ($(if ($ok) { 'PASS' } else { 'FAIL' })) ('m45m46_stdout_' + $case['Name']) "bytes=$actualBytes expected_bytes=$expectedBytes stdout=$($stdoutPath.Substring($RepoRoot.Length + 1))"
}

$outFile = Join-Path $GeneratedDir "m45m46_runtime_int_arrays_validation.txt"
Set-Content -Path $outFile -Value $Results -Encoding UTF8
Write-Host "OUT|$($outFile.Substring($RepoRoot.Length + 1))"

if ($Results | Where-Object { $_ -like 'FAIL|*' }) { exit 1 }
exit 0
