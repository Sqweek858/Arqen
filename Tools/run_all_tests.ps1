param(
    [switch]$SkipUi
)

$ErrorActionPreference = "SilentlyContinue"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Experiments = Join-Path $RepoRoot "Experiments"
$script:Total = 0
$script:Passed = 0
$script:Failures = @()

function Add-Check {
    param(
        [string]$Name,
        [bool]$Pass,
        [string]$Note = ""
    )

    $script:Total += 1
    if ($Pass) {
        $script:Passed += 1
        Write-Host ("{0} PASS {1}" -f $Name, $Note)
    } else {
        $script:Failures += "$Name $Note"
        Write-Host ("{0} FAIL {1}" -f $Name, $Note)
    }
}

function Invoke-Stage {
    param(
        [string]$Dir,
        [string]$Exe,
        [string[]]$StageArgs = @()
    )

    Push-Location $Dir
    & $Exe @StageArgs | Out-Null
    $exit = $LASTEXITCODE
    Pop-Location
    return $exit
}

function Invoke-UiExe {
    param(
        [string]$Dir,
        [string]$Exe,
        [string[]]$Titles = @("Arqen Byte Zero", "Arqen", "Hello")
    )

    if ($SkipUi) {
        return @{ Exit = $null; Activated = $false; TimedOut = $false; Skipped = $true }
    }

    Push-Location $Dir
    $proc = Start-Process -FilePath $Exe -PassThru
    Pop-Location

    $ws = New-Object -ComObject WScript.Shell
    $activated = $false
    $sentEnter = $false

    for ($i = 0; $i -lt 40 -and -not $proc.HasExited; $i++) {
        Start-Sleep -Milliseconds 100
        $proc.Refresh()
        if ($proc.MainWindowHandle -ne 0 -and $ws.AppActivate($proc.Id)) {
            $activated = $true
            Start-Sleep -Milliseconds 100
            $ws.SendKeys("{ENTER}")
            $sentEnter = $true
            break
        } else {
            foreach ($title in $Titles) {
                if ($title.Length -lt 8) {
                    continue
                }
                if ($ws.AppActivate($title)) {
                    $activated = $true
                    Start-Sleep -Milliseconds 100
                    $ws.SendKeys("{ENTER}")
                    $sentEnter = $true
                    break
                }
            }
        }
        if ($i -ge 2 -and (($i - 2) % 3) -eq 0 -and -not $proc.HasExited) {
            $ws.SendKeys("{ENTER}")
            $sentEnter = $true
        }
        if ($activated) { break }
    }

    $proc.WaitForExit(5000) | Out-Null
    if (-not $proc.HasExited) {
        $proc.Kill()
        return @{ Exit = $null; Activated = ($activated -or $sentEnter); TimedOut = $true; Skipped = $false }
    }

    return @{ Exit = $proc.ExitCode; Activated = ($activated -or $sentEnter); TimedOut = $false; Skipped = $false }
}

function Check-Ui {
    param(
        [string]$Name,
        [string]$Dir,
        [string]$Exe
    )

    $r = Invoke-UiExe -Dir $Dir -Exe $Exe
    if ($r.Skipped) {
        Add-Check $Name $true "SKIPPED_UI"
    } else {
        Add-Check $Name ($r.Exit -eq 0 -and $r.Activated -and -not $r.TimedOut) ("exit={0} ui={1}" -f $r.Exit, $r.Activated)
    }
}

function Run-M10-Fixtures {
    $dir = Join-Path $Experiments "M10_SimpleExpressions"
    $tests = Join-Path $dir "tests"
    $backup = Join-Path $dir "m10.saved.by_tests.arq"
    Copy-Item (Join-Path $dir "m10.arq") $backup -Force

    $cases = @(
        @{ Name = "valid_name_concat"; File = "valid_name_concat.arq"; Want = "OK"; Message = "Hello, Sqweek" },
        @{ Name = "valid_string_concat"; File = "valid_string_concat.arq"; Want = "OK"; Message = "Hello from M10" },
        @{ Name = "unknown_variable"; File = "unknown_variable.arq"; Want = "S010" },
        @{ Name = "type_mismatch_bool"; File = "type_mismatch_bool.arq"; Want = "S011" },
        @{ Name = "message_expects_text"; File = "message_expects_text.arq"; Want = "S012" },
        @{ Name = "broken_plus"; File = "broken_plus.arq"; Want = "P011" }
    )

    $ok = 0
    foreach ($case in $cases) {
        Copy-Item (Join-Path $tests $case.File) (Join-Path $dir "m10.arq") -Force
        Remove-Item (Join-Path $dir "m10.tokens.txt"), (Join-Path $dir "m10.ast.txt"), (Join-Path $dir "m10.exe"), (Join-Path $dir "arqen_m10_error.txt"), (Join-Path $dir "arqen_codegen_error.txt") -ErrorAction SilentlyContinue

        $lex = Invoke-Stage $dir ".\arq_lexer_m10_tokens.exe"
        $parse = Invoke-Stage $dir ".\arq_parser_m10.exe"
        $passed = $false

        if ($case.Want -eq "OK") {
            $codegen = Invoke-Stage $dir ".\arqc_m10.exe"
            $ast = ""
            if (Test-Path (Join-Path $dir "m10.ast.txt")) {
                $ast = Get-Content (Join-Path $dir "m10.ast.txt") -Raw
            }
            $passed = ($lex -eq 0 -and $parse -eq 0 -and $codegen -eq 0 -and $ast.Contains($case.Message))
        } else {
            $err = ""
            if (Test-Path (Join-Path $dir "arqen_m10_error.txt")) {
                $err = Get-Content (Join-Path $dir "arqen_m10_error.txt") -Raw
            }
            $passed = ($lex -eq 0 -and $parse -eq 1 -and $err.Contains("Error $($case.Want)"))
        }

        if ($passed) { $ok += 1 }
    }

    Copy-Item $backup (Join-Path $dir "m10.arq") -Force
    Remove-Item $backup -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $dir "m10.tokens.txt"), (Join-Path $dir "m10.ast.txt"), (Join-Path $dir "m10.exe"), (Join-Path $dir "arqen_m10_error.txt"), (Join-Path $dir "arqen_codegen_error.txt") -ErrorAction SilentlyContinue
    Invoke-Stage $dir ".\arq_lexer_m10_tokens.exe" | Out-Null
    Invoke-Stage $dir ".\arq_parser_m10.exe" | Out-Null
    Invoke-Stage $dir ".\arqc_m10.exe" | Out-Null
    Write-Host ("M10_FIXTURES {0}/6" -f $ok)
    return ($ok -eq 6)
}

function Run-M10G-Driver-Tests {
    $driver = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
    $tests = Join-Path $Experiments "M10G_CorePipelineUpgrade\tests"

    $sampleExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10g.exe" @(".\Samples\hello_m10.arq")
    Add-Check "M10G_DRIVER_SAMPLE" ($sampleExit -eq 0 -and (Test-Path (Join-Path $RepoRoot "Build\EXE\hello_m10.exe")))
    Check-Ui "M10G_OUT" (Join-Path $RepoRoot "Build\EXE") ".\hello_m10.exe"

    $cases = @(
        @{ Name = "M10G_VALID_NAME"; File = "valid_name_concat.arq"; Want = "OK"; Message = "Hello, Sqweek" },
        @{ Name = "M10G_VALID_STRING"; File = "valid_string_concat.arq"; Want = "OK"; Message = "Hello from M10" },
        @{ Name = "M10G_ARBITRARY_VARS"; File = "valid_arbitrary_variables.arq"; Want = "OK"; Message = "Hello, Sqweek" },
        @{ Name = "M10G_UNKNOWN_VAR"; File = "unknown_variable.arq"; Want = "S010"; Stage = "semantic" },
        @{ Name = "M10G_DUPLICATE_VAR"; File = "duplicate_variable.arq"; Want = "S001"; Stage = "semantic" },
        @{ Name = "M10G_BOOL_MISMATCH"; File = "type_mismatch_bool.arq"; Want = "S011"; Stage = "semantic" },
        @{ Name = "M10G_MESSAGE_TEXT_TYPE"; File = "message_expects_text.arq"; Want = "S012"; Stage = "semantic" },
        @{ Name = "M10G_BROKEN_PLUS"; File = "broken_plus.arq"; Want = "P011"; Stage = "parse" }
    )

    foreach ($case in $cases) {
        $input = Join-Path $tests $case.File
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($input)
        $exit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10g.exe" @($input)

        if ($case.Want -eq "OK") {
            $astPath = Join-Path $RepoRoot "Build\AST\$stem.ast"
            $ast = ""
            if (Test-Path $astPath) {
                $ast = Get-Content $astPath -Raw
            }
            Add-Check $case.Name ($exit -eq 0 -and $ast.Contains("MESSAGE|$($case.Message)"))
        } else {
            $errPath = Join-Path $RepoRoot "Build\Errors\$stem.$($case.Stage).error.txt"
            $err = ""
            if (Test-Path $errPath) {
                $err = Get-Content $errPath -Raw
            }
            Add-Check $case.Name ($exit -eq 1 -and $err.Contains("Error $($case.Want)"))
        }
    }
}

function Run-Command-Tests {
    $root = Join-Path $RepoRoot "Tests\CommandTests"
    if (-not (Test-Path $root)) {
        Write-Host "Command tests folder missing; skipping."
        return
    }

    Write-Host ""
    Write-Host "Command tests"

    $folders = Get-ChildItem $root -Directory | Sort-Object Name
    foreach ($folder in $folders) {
        $expectedPath = Join-Path $folder.FullName "expected.txt"
        if (-not (Test-Path $expectedPath)) {
            Add-Check ("CMD_{0}_EXPECTED" -f $folder.Name.ToUpperInvariant()) $false "missing expected.txt"
            continue
        }

        $lines = Get-Content $expectedPath | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") }
        foreach ($line in $lines) {
            $parts = $line.Split("|")
            if ($parts.Length -lt 4) {
                Add-Check ("CMD_{0}_BAD_EXPECTED" -f $folder.Name.ToUpperInvariant()) $false $line
                continue
            }

            $file = $parts[0]
            $wantExit = [int]$parts[1]
            $kind = $parts[2]
            $want = $parts[3]
            $stage = if ($parts.Length -ge 5) { $parts[4] } else { "" }
            $input = Join-Path $folder.FullName $file
            $stem = [System.IO.Path]::GetFileNameWithoutExtension($input)
            $exit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10g.exe" @($input)
            $name = "CMD_{0}_{1}" -f $folder.Name.ToUpperInvariant(), $stem.ToUpperInvariant()

            if ($kind -eq "MESSAGE") {
                $astPath = Join-Path $RepoRoot "Build\AST\$stem.ast"
                $ast = ""
                if (Test-Path $astPath) {
                    $ast = Get-Content $astPath -Raw
                }
                Add-Check $name ($exit -eq $wantExit -and $ast.Contains("MESSAGE|$want"))
            } elseif ($kind -eq "ERROR") {
                $errPath = Join-Path $RepoRoot "Build\Errors\$stem.$stage.error.txt"
                $err = ""
                if (Test-Path $errPath) {
                    $err = Get-Content $errPath -Raw
                }
                Add-Check $name ($exit -eq $wantExit -and $err.Contains("Error $want"))
            } else {
                Add-Check $name $false "unknown expected kind $kind"
            }
        }
    }
}

function Run-M10I-Backend-Tests {
    Write-Host ""
    Write-Host "M10I backend architecture tests"

    $sampleExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10g.exe" @(".\Samples\hello_m10.arq")
    $irPath = Join-Path $RepoRoot "Build\IR\hello_m10.arqir"
    $manifestPath = Join-Path $RepoRoot "Build\Manifests\hello_m10.manifest.txt"
    $exePath = Join-Path $RepoRoot "Build\EXE\hello_m10.exe"

    Add-Check "M10I_SAMPLE_BUILD" ($sampleExit -eq 0 -and (Test-Path $irPath) -and (Test-Path $manifestPath) -and (Test-Path $exePath))

    $ir = ""
    if (Test-Path $irPath) {
        $ir = Get-Content $irPath -Raw
    }

    Add-Check "M10I_IR_VERSION" ($ir.Contains("ARQIR|version=0"))
    Add-Check "M10I_IR_ACTION_SHOW" ($ir.Contains("op=show_message"))
    Add-Check "M10I_IR_ACTION_EXIT" ($ir.Contains("op=exit"))
    Add-Check "M10I_IR_NO_WINDOWS_API" (-not $ir.Contains("MessageBoxW") -and -not $ir.Contains("ExitProcess"))
    Add-Check "M10I_IR_NO_PE_DETAILS" (-not $ir.Contains("RVA") -and -not $ir.Contains("IAT") -and -not $ir.Contains("PE32") -and -not $ir.Contains("offset"))

    $manifest = ""
    if (Test-Path $manifestPath) {
        $manifest = Get-Content $manifestPath -Raw
    }
    Add-Check "M10I_MANIFEST" ($manifest.Contains("BACKEND|WindowsX64PE_MessageBoxBackend") -and $manifest.Contains("IR|Build/IR/hello_m10.arqir"))

    $backendOut = Join-Path $RepoRoot "Build\EXE\hello_m10_from_ir.exe"
    $backendExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10g.exe" @("--backend-only", ".\Build\IR\hello_m10.arqir", "-o", ".\Build\EXE\hello_m10_from_ir.exe")
    Add-Check "M10I_BACKEND_ONLY" ($backendExit -eq 0 -and (Test-Path $backendOut))
    Check-Ui "M10I_BACKEND_OUT" (Join-Path $RepoRoot "Build\EXE") ".\hello_m10_from_ir.exe"
}

Write-Host "=== Smoke tests ==="
Write-Host "Arqen smoke tests"
Write-Host "Root: $RepoRoot"

$m1 = Join-Path $Experiments "M1_ExitProcess"
Add-Check "M1" ((Invoke-Stage $m1 ".\arqen_m1_exitprocess_v3_fixed_text_flags.exe") -eq 0)

$m2 = Join-Path $Experiments "M2_MessageBoxW"
Check-Ui "M2" $m2 ".\arqen_m2_messagebox_v2_fixed_messagebox_call.exe"

$m4a = Join-Path $Experiments "M4A_StaticExeWriter"
Add-Check "M4A_GEN" ((Invoke-Stage $m4a ".\arqen_generator_m4a.exe") -eq 0)
Check-Ui "M4A_OUT" (Join-Path $m4a "output") ".\generated_hello.exe"

$m4b = Join-Path $Experiments "M4B_TemplatePatch"
Add-Check "M4B_GEN" ((Invoke-Stage $m4b ".\arqen_generator_m4b.exe") -eq 0)
Check-Ui "M4B_OUT" (Join-Path $m4b "output") ".\generated_hello_m4b.exe"

$m4c = Join-Path $Experiments "M4C_StrictArqReader"
Add-Check "M4C_GEN" ((Invoke-Stage $m4c ".\arqen_generator_m4c.exe") -eq 0)
Check-Ui "M4C_OUT" (Join-Path $m4c "output") ".\generated_hello_m4c.exe"

$m5 = Join-Path $Experiments "M5_CLI_Minimal"
Add-Check "M5_CLI" ((Invoke-Stage $m5 ".\arqc_m5.exe" -StageArgs @("hello_m5.arq")) -eq 0)
Check-Ui "M5_OUT" $m5 ".\hello_m5.exe"

$m6d = Join-Path $Experiments "M6D_LexerErrors"
$m6dBackup = Join-Path $m6d "m6d_input.saved.by_tests.arq"
Copy-Item (Join-Path $m6d "m6d_input.arq") $m6dBackup -Force
$m6dCases = @(
    @{ Name = "M6D_VALID"; File = "valid_ok.arq"; Want = 0 },
    @{ Name = "M6D_L001"; File = "unknown_character.arq"; Want = 1 },
    @{ Name = "M6D_L002"; File = "unterminated_string.arq"; Want = 2 },
    @{ Name = "M6D_L003"; File = "invalid_integer.arq"; Want = 3 },
    @{ Name = "M6D_L004"; File = "unexpected_control.arq"; Want = 4 }
)
foreach ($case in $m6dCases) {
    Copy-Item (Join-Path $m6d "tests\$($case.File)") (Join-Path $m6d "m6d_input.arq") -Force
    Remove-Item (Join-Path $m6d "m6d.tokens.txt"), (Join-Path $m6d "arqen_lexer_error.txt") -ErrorAction SilentlyContinue
    Add-Check $case.Name ((Invoke-Stage $m6d ".\arq_lexer_m6d.exe") -eq $case.Want)
}
Copy-Item $m6dBackup (Join-Path $m6d "m6d_input.arq") -Force
Remove-Item $m6dBackup -ErrorAction SilentlyContinue

$m7b = Join-Path $Experiments "M7B_TokenStreamParser"
Add-Check "M7B_LEX" ((Invoke-Stage $m7b ".\arq_lexer_m7b_tokens.exe") -eq 0)
Add-Check "M7B_PARSE" ((Invoke-Stage $m7b ".\arq_parser_m7b.exe") -eq 0)

$m8 = Join-Path $Experiments "M8_AST_Codegen"
Add-Check "M8_LEX" ((Invoke-Stage $m8 ".\arq_lexer_m8_tokens.exe") -eq 0)
Add-Check "M8_PARSE" ((Invoke-Stage $m8 ".\arq_parser_m8.exe") -eq 0)
Add-Check "M8_CODEGEN" ((Invoke-Stage $m8 ".\arqc_m8.exe") -eq 0)
Check-Ui "M8_OUT" $m8 ".\hello_m8.exe"

$m9 = Join-Path $Experiments "M9_LetVariables"
Add-Check "M9_LEX" ((Invoke-Stage $m9 ".\arq_lexer_m9_tokens.exe") -eq 0)
Add-Check "M9_PARSE" ((Invoke-Stage $m9 ".\arq_parser_m9.exe") -eq 0)

$m9b = Join-Path $Experiments "M9B_LetVariablesComplete"
Add-Check "M9B_LEX" ((Invoke-Stage $m9b ".\arq_lexer_m9b_tokens.exe") -eq 0)
Add-Check "M9B_PARSE" ((Invoke-Stage $m9b ".\arq_parser_m9b.exe") -eq 0)

$m10 = Join-Path $Experiments "M10_SimpleExpressions"
Add-Check "M10_LEX" ((Invoke-Stage $m10 ".\arq_lexer_m10_tokens.exe") -eq 0)
Add-Check "M10_PARSE" ((Invoke-Stage $m10 ".\arq_parser_m10.exe") -eq 0)
Add-Check "M10_CODEGEN" ((Invoke-Stage $m10 ".\arqc_m10.exe") -eq 0)
Check-Ui "M10_OUT" $m10 ".\m10.exe"

$fixturesOk = Run-M10-Fixtures
if ($fixturesOk) {
    Write-Host "M10_FIXTURES PASS"
} else {
    Write-Host "M10_FIXTURES FAIL"
    $script:Failures += "M10_FIXTURES"
}

Run-M10G-Driver-Tests

Run-Command-Tests

Run-M10I-Backend-Tests

Write-Host ""
Write-Host "=== Regression summary ==="

Write-Host ""
Write-Host ("Total: {0}/{1} passed" -f $script:Passed, $script:Total)

if ($script:Failures.Count -gt 0) {
    Write-Host "Failures:"
    foreach ($failure in $script:Failures) {
        Write-Host " - $failure"
    }
    exit 1
}

exit 0
