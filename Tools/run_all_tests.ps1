param(
    [switch]$SkipUi
)

$ErrorActionPreference = "SilentlyContinue"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Experiments = Join-Path $RepoRoot "Experiments"
$script:Total = 0
$script:Passed = 0
$script:Failures = @()
$script:StructuredResults = @()

function Add-Check {
    param(
        [string]$Name,
        [bool]$Pass,
        [string]$Note = ""
    )

    $script:Total += 1
    $group = if ($Name.StartsWith("M12_")) { "M12" } elseif ($Name.StartsWith("M11_")) { "M11" } elseif ($Name.StartsWith("M10O_")) { "M10O" } elseif ($Name.StartsWith("M10N_")) { "M10N" } elseif ($Name.StartsWith("M10L_")) { "M10L" } elseif ($Name.StartsWith("M10JK")) { "M10JK" } else { "REGRESSION" }
    $resultName = if ($Name.StartsWith("M12_")) { $Name.Substring(4) } elseif ($Name.StartsWith("M11_")) { $Name.Substring(4) } elseif ($Name.StartsWith("M10O_")) { $Name.Substring(5) } elseif ($Name.StartsWith("M10N_")) { $Name.Substring(5) } elseif ($Name.StartsWith("M10L_")) { $Name.Substring(5) } else { $Name }
    if ($Pass) {
        $script:Passed += 1
        $script:StructuredResults += "PASS|$group|$resultName"
        Write-Host ("{0} PASS {1}" -f $Name, $Note)
    } else {
        $script:Failures += "$Name $Note"
        $script:StructuredResults += "FAIL|$group|$resultName|$Note"
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
        [string]$Exe,
        [string[]]$Titles = @("Arqen Byte Zero", "Arqen", "Hello")
    )

    $r = Invoke-UiExe -Dir $Dir -Exe $Exe -Titles $Titles
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

function Test-Pe-Signature {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x100) {
        return $false
    }
    if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        return $false
    }
    $pe = [BitConverter]::ToUInt32($bytes, 0x3C)
    if (($pe + 4) -ge $bytes.Length) {
        return $false
    }
    return ([BitConverter]::ToUInt32($bytes, $pe) -eq 0x00004550)
}

function Manifest-Has {
    param(
        [string]$Path,
        [string]$Needle
    )

    if (-not (Test-Path $Path)) {
        return $false
    }
    return (Get-Content $Path -Raw).Contains($Needle)
}

function Manifest-Value {
    param(
        [string]$Path,
        [string]$Key
    )

    if (-not (Test-Path $Path)) {
        return ""
    }
    foreach ($line in Get-Content $Path) {
        if ($line.StartsWith("$Key|")) {
            return $line.Substring($Key.Length + 1)
        }
    }
    return ""
}

function Run-M10JK-Tests {
    Write-Host ""
    Write-Host "M10JK build/backend hardening tests"

    $driver = Join-Path $RepoRoot "Tools\arqc_m10jk.ps1"
    $backendTests = Join-Path $RepoRoot "Tests\Backend\WindowsX64PE"
    Add-Check "M10JK_DRIVER_EXISTS" (Test-Path $driver)

    $sampleExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Samples\hello_m10.arq", "--rebuild")
    $sampleExe = Join-Path $RepoRoot "Build\EXE\hello_m10.exe"
    $sampleManifest = Join-Path $RepoRoot "Build\Manifests\hello_m10.build.txt"
    $sampleLexStage = Join-Path $RepoRoot "Build\Manifests\hello_m10.lex.stage.txt"
    $sampleParseStage = Join-Path $RepoRoot "Build\Manifests\hello_m10.parse.stage.txt"
    $sampleBackendStage = Join-Path $RepoRoot "Build\Manifests\hello_m10.backend.stage.txt"
    $sampleCodegenStage = Join-Path $RepoRoot "Build\Manifests\hello_m10.codegen.stage.txt"
    $sampleArtifactIndex = Join-Path $RepoRoot "Build\artifact_index.txt"
    Add-Check "M10JK_VALID_BUILD" ($sampleExit -eq 0 -and (Test-Path $sampleExe) -and (Test-Path $sampleManifest))
    Add-Check "M10JK_VALID_MANIFEST" ((Manifest-Has $sampleManifest "STATUS|success") -and (Manifest-Has $sampleManifest "COMPILER_VERSION|0.10.0-bootstrap") -and (Manifest-Has $sampleManifest "SOURCE_HASH|"))
    Add-Check "M10JK_STAGE_MANIFESTS" ((Test-Path $sampleLexStage) -and (Test-Path $sampleParseStage) -and (Test-Path $sampleBackendStage) -and (Test-Path $sampleCodegenStage) -and (Manifest-Has $sampleBackendStage "STATUS|pass") -and (Manifest-Has $sampleCodegenStage "STATUS|skipped"))
    Add-Check "M10JK_PE_SIGNATURE" (Test-Pe-Signature $sampleExe)
    Add-Check "M10JK_ARTIFACT_INDEX" ((Test-Path $sampleArtifactIndex) -and (Get-Content $sampleArtifactIndex -Raw).Contains("ARTIFACT|Build/EXE/hello_m10.exe"))
    Check-Ui "M10JK_VALID_EXE" (Join-Path $RepoRoot "Build\EXE") ".\hello_m10.exe"

    $unknownExe = Join-Path $RepoRoot "Build\EXE\invalid_unknown_variable.exe"
    Remove-Item $unknownExe -Force -ErrorAction SilentlyContinue
    $unknownExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\Backend\WindowsX64PE\invalid_unknown_variable.arq")
    $unknownManifest = Join-Path $RepoRoot "Build\Manifests\invalid_unknown_variable.build.txt"
    Add-Check "M10JK_UNKNOWN_VARIABLE" ($unknownExit -ne 0 -and -not (Test-Path $unknownExe) -and (Manifest-Has $unknownManifest "STATUS|failure") -and (Manifest-Has $unknownManifest "FAILED_STAGE|semantic"))

    $plusExe = Join-Path $RepoRoot "Build\EXE\invalid_broken_plus.exe"
    Remove-Item $plusExe -Force -ErrorAction SilentlyContinue
    $plusExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\Backend\WindowsX64PE\invalid_broken_plus.arq")
    $plusManifest = Join-Path $RepoRoot "Build\Manifests\invalid_broken_plus.build.txt"
    Add-Check "M10JK_BROKEN_PLUS" ($plusExit -ne 0 -and -not (Test-Path $plusExe) -and (Manifest-Has $plusManifest "FAILED_STAGE|parser"))

    $badCharExe = Join-Path $RepoRoot "Build\EXE\invalid_bad_char.exe"
    Remove-Item $badCharExe -Force -ErrorAction SilentlyContinue
    $badCharExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\Backend\WindowsX64PE\invalid_bad_char.arq")
    $badCharManifest = Join-Path $RepoRoot "Build\Manifests\invalid_bad_char.build.txt"
    Add-Check "M10JK_BAD_CHAR" ($badCharExit -ne 0 -and -not (Test-Path $badCharExe) -and (Manifest-Has $badCharManifest "FAILED_STAGE|lexer"))

    $longExe = Join-Path $RepoRoot "Build\EXE\invalid_too_long_string.exe"
    Remove-Item $longExe -Force -ErrorAction SilentlyContinue
    $longExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\Backend\WindowsX64PE\invalid_too_long_string.arq")
    $longManifest = Join-Path $RepoRoot "Build\Manifests\invalid_too_long_string.build.txt"
    $longError = Join-Path $RepoRoot "Build\Errors\invalid_too_long_string.backend.error.txt"
    $longAllErrors = Join-Path $RepoRoot "Build\Diagnostics\invalid_too_long_string.all_errors.txt"
    Add-Check "M10JK_TOO_LONG_STRING" ($longExit -ne 0 -and -not (Test-Path $longExe) -and (Manifest-Has $longManifest "FAILED_STAGE|backend") -and (Manifest-Has $longManifest "ERROR_PATH|Build/Diagnostics/invalid_too_long_string.all_errors.txt") -and (Manifest-Has $longAllErrors "B003"))

    $unsupportedExe = Join-Path $RepoRoot "Build\EXE\invalid_unsupported_action.exe"
    Remove-Item $unsupportedExe -Force -ErrorAction SilentlyContinue
    $unsupportedExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @("--backend-only", ".\Tests\Backend\WindowsX64PE\invalid_unsupported_action.arqir", "-o", ".\Build\EXE\invalid_unsupported_action.exe")
    $unsupportedManifest = Join-Path $RepoRoot "Build\Manifests\invalid_unsupported_action.build.txt"
    $unsupportedError = Join-Path $RepoRoot "Build\Errors\invalid_unsupported_action.backend.error.txt"
    Add-Check "M10JK_UNSUPPORTED_ACTION" ($unsupportedExit -ne 0 -and -not (Test-Path $unsupportedExe) -and (Manifest-Has $unsupportedManifest "FAILED_STAGE|backend") -and (Manifest-Has $unsupportedError "B001"))

    $templateExe = Join-Path $RepoRoot "Build\EXE\valid_template_failure.exe"
    Remove-Item $templateExe -Force -ErrorAction SilentlyContinue
    $templateExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\Backend\WindowsX64PE\valid_template_failure.arq", "--template", ".\Backends\WindowsX64PE\Templates\missing_template.exe")
    $templateManifest = Join-Path $RepoRoot "Build\Manifests\valid_template_failure.build.txt"
    $templateError = Join-Path $RepoRoot "Build\Errors\valid_template_failure.backend.error.txt"
    Add-Check "M10JK_TEMPLATE_FAILURE" ($templateExit -ne 0 -and -not (Test-Path $templateExe) -and (Manifest-Has $templateManifest "FAILED_STAGE|backend") -and (Manifest-Has $templateError "B002"))
}

function Run-M10L-Tests {
    Write-Host ""
    Write-Host "M10L command integration automation tests"

    $generated = Join-Path $RepoRoot "Build\Generated"
    New-Item -ItemType Directory -Force -Path $generated | Out-Null

    $specExit = Invoke-Stage $RepoRoot ".\Tools\validate_command_specs.ps1"
    $specOut = Join-Path $generated "command_spec_validation.txt"
    $specText = if (Test-Path $specOut) { Get-Content $specOut -Raw } else { "" }
    Add-Check "M10L_command_spec_validation" ($specExit -eq 0 -and $specText.Contains("PASS|let") -and $specText.Contains("PASS|message_text") -and $specText.Contains("PASS|BlendMixToCode") -and $specText.Contains("PASS|comments") -and $specText.Contains("PASS|show_message") -and $specText.Contains("PASS|set_title_to"))

    $keywordExit = Invoke-Stage $RepoRoot ".\Tools\generate_keyword_registry.ps1"
    $keywordOut = Join-Path $generated "keyword_registry.txt"
    $keywordText = if (Test-Path $keywordOut) { Get-Content $keywordOut -Raw } else { "" }
    Add-Check "M10L_keyword_registry_generation" ($keywordExit -eq 0 -and $keywordText.Contains("KEYWORD|program") -and $keywordText.Contains("KEYWORD|show") -and $keywordText.Contains("KEYWORD|set") -and $keywordText.Contains("KEYWORD|blend") -and $keywordText.Contains("KEYWORD|mix") -and $keywordText.Contains("KEYWORD|to") -and $keywordText.Contains("KEYWORD|code") -and $keywordText.Contains("KEYWORD|true") -and $keywordText.Contains("KEYWORD|false"))

    $ruleExit = Invoke-Stage $RepoRoot ".\Tools\generate_parser_rule_registry.ps1"
    $ruleOut = Join-Path $generated "parser_rule_registry.txt"
    $ruleText = if (Test-Path $ruleOut) { Get-Content $ruleOut -Raw } else { "" }
    Add-Check "M10L_parser_rule_registry_generation" ($ruleExit -eq 0 -and $ruleText.Contains("RULE|program|starts=KEYWORD(program)|ast=Program") -and $ruleText.Contains("RULE|message_text|starts=KEYWORD(message),KEYWORD(text)|ast=MessageText") -and $ruleText.Contains("RULE|show_message|starts=KEYWORD(show),KEYWORD(message)|ast=ShowMessage") -and $ruleText.Contains("RULE|set_title_to|starts=KEYWORD(set),KEYWORD(title),KEYWORD(to)|ast=SetTitle") -and $ruleText.Contains("RULE|BlendMixToCode|starts=KEYWORD(blend),KEYWORD(mix),KEYWORD(to),KEYWORD(code)|ast=BlendMixToCode"))

    $indexExit = Invoke-Stage $RepoRoot ".\Tools\generate_command_test_index.ps1"
    $indexOut = Join-Path $generated "command_test_index.txt"
    $indexText = if (Test-Path $indexOut) { Get-Content $indexOut -Raw } else { "" }
    Add-Check "M10L_command_test_index_generation" ($indexExit -eq 0 -and $indexText.Contains("TEST|let|valid|Tests\CommandTests\let\valid_basic.arq") -and $indexText.Contains("TEST|message_text|invalid|Tests\CommandTests\message_text\invalid_unknown_variable.arq") -and $indexText.Contains("TEST|blend_mix_to_code|valid|Tests\CommandTests\blend_mix_to_code\valid_code_0.arq") -and $indexText.Contains("TEST|comments|valid|Tests\CommandTests\comments\valid_full_line_comment.arq") -and $indexText.Contains("TEST|show_message|valid|Tests\CommandTests\show_message\valid_literal.arq") -and $indexText.Contains("TEST|set_title_to|valid|Tests\CommandTests\set_title_to\valid_literal.arq"))

    $statusExit = Invoke-Stage $RepoRoot ".\Tools\generate_command_status.ps1"
    $statusOut = Join-Path $generated "command_status.txt"
    $statusText = if (Test-Path $statusOut) { Get-Content $statusOut -Raw } else { "" }
    Add-Check "M10L_command_status_generation" ($statusExit -eq 0 -and $statusText.Contains("COMMAND|message_text|spec=yes|tests=yes|lexer=yes|parser=yes|ast=yes|semantic=yes|ir=yes|backend=yes|status=stable") -and $statusText.Contains("COMMAND|BlendMixToCode|spec=yes|tests=yes|lexer=yes|parser=yes|ast=yes|semantic=yes|ir=yes|backend=yes|status=stable") -and $statusText.Contains("COMMAND|comments|spec=yes|tests=yes|lexer=yes|parser=no|ast=none|semantic=yes|ir=none|backend=none|status=stable") -and $statusText.Contains("COMMAND|show_message|spec=yes|tests=yes|lexer=yes|parser=yes|ast=yes|semantic=yes|ir=yes|backend=yes|status=stable") -and $statusText.Contains("COMMAND|set_title_to|spec=yes|tests=yes|lexer=yes|parser=yes|ast=yes|semantic=yes|ir=yes|backend=yes|status=stable") -and -not $statusText.Contains("COMMAND|BlendMixToCode|spec=draft"))
}

function Diagnostic-ErrorCount {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return -1
    }
    foreach ($line in Get-Content $Path) {
        if ($line.StartsWith("ERROR_COUNT|")) {
            return [int]($line.Split("|")[1])
        }
    }
    return -1
}

function Run-M10N-Tests {
    Write-Host ""
    Write-Host "M10N unified diagnostics tests"

    $validExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Samples\hello_m10.arq")
    $validDiag = Join-Path $RepoRoot "Build\Diagnostics\hello_m10.all_errors.txt"
    $validManifest = Join-Path $RepoRoot "Build\Manifests\hello_m10.build.txt"
    Add-Check "M10N_valid_zero_diagnostics" ($validExit -eq 0 -and (Manifest-Has $validDiag "STATUS|success") -and (Manifest-Has $validDiag "ERROR_COUNT|0") -and (Manifest-Has $validManifest "DIAGNOSTICS_PATH|Build/Diagnostics/hello_m10.all_errors.txt") -and (Manifest-Has $validManifest "ERROR_COUNT|0"))

    $fourExe = Join-Path $RepoRoot "Build\EXE\four_errors_playground.exe"
    Remove-Item $fourExe -Force -ErrorAction SilentlyContinue
    $fourExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\Diagnostics\four_errors_playground.arq")
    $fourDiag = Join-Path $RepoRoot "Build\Diagnostics\four_errors_playground.all_errors.txt"
    $fourManifest = Join-Path $RepoRoot "Build\Manifests\four_errors_playground.build.txt"
    $fourText = if (Test-Path $fourDiag) { Get-Content $fourDiag -Raw } else { "" }
    $fourCount = Diagnostic-ErrorCount $fourDiag
    $fourHasAll = $fourText.Contains("P020|lint") -and $fourText.Contains('Expected keyword "title", got "tile".') -and $fourText.Contains("P030|lint") -and $fourText.Contains('Expected exit code after "exit".') -and (($fourText.Split("L002|lint").Count - 1) -ge 2)
    Add-Check "M10N_four_errors_detected" ($fourExit -ne 0 -and $fourCount -ge 4 -and $fourHasAll)
    Add-Check "M10N_four_errors_no_exe" (-not (Test-Path $fourExe) -and (Manifest-Has $fourManifest "STATUS|failure") -and (Manifest-Has $fourManifest "STAGES_SKIPPED|parser,semantic,ir,codegen,backend"))

    $semanticExe = Join-Path $RepoRoot "Build\EXE\unknown_variable_diagnostic.exe"
    Remove-Item $semanticExe -Force -ErrorAction SilentlyContinue
    $semanticExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\Diagnostics\unknown_variable_diagnostic.arq")
    $semanticDiag = Join-Path $RepoRoot "Build\Diagnostics\unknown_variable_diagnostic.all_errors.txt"
    $semanticManifest = Join-Path $RepoRoot "Build\Manifests\unknown_variable_diagnostic.build.txt"
    Add-Check "M10N_semantic_error_aggregated" ($semanticExit -ne 0 -and -not (Test-Path $semanticExe) -and (Manifest-Has $semanticDiag "S010|semantic") -and (Manifest-Has $semanticManifest "FAILED_STAGE|semantic") -and (Manifest-Has $semanticManifest "STAGES_SKIPPED|ir,codegen,backend"))

    $backendExe = Join-Path $RepoRoot "Build\EXE\invalid_too_long_string.exe"
    Remove-Item $backendExe -Force -ErrorAction SilentlyContinue
    $backendExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\Backend\WindowsX64PE\invalid_too_long_string.arq")
    $backendDiag = Join-Path $RepoRoot "Build\Diagnostics\invalid_too_long_string.all_errors.txt"
    $backendManifest = Join-Path $RepoRoot "Build\Manifests\invalid_too_long_string.build.txt"
    Add-Check "M10N_backend_error_aggregated" ($backendExit -ne 0 -and -not (Test-Path $backendExe) -and (Manifest-Has $backendDiag "B003|backend") -and (Manifest-Has $backendManifest "FAILED_STAGE|backend"))
}

function Run-M10O-Tests {
    Write-Host ""
    Write-Host "M10O build cache tests"

    $cacheRoot = Join-Path $RepoRoot "Build\Cache"
    $cleanExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @("--clean-cache")
    $cacheItems = @(Get-ChildItem $cacheRoot -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne ".gitkeep" })
    Add-Check "M10O_cache_clean_flag" ($cleanExit -eq 0 -and $cacheItems.Count -eq 0)

    $validInput = ".\Tests\Cache\cache_valid.arq"
    $validStem = "cache_valid"
    $validManifest = Join-Path $RepoRoot "Build\Manifests\$validStem.build.txt"
    $validDiag = Join-Path $RepoRoot "Build\Diagnostics\$validStem.all_errors.txt"
    $validExe = Join-Path $RepoRoot "Build\EXE\$validStem.exe"

    $firstExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @($validInput)
    $firstCachePath = Manifest-Value $validManifest "CACHE_PATH"
    Add-Check "M10O_cache_miss_first_build" ($firstExit -eq 0 -and (Test-Path $validExe) -and ((Manifest-Has $validManifest "CACHE_STATUS|store") -or (Manifest-Has $validManifest "CACHE_STATUS|miss")) -and (Test-Path (Join-Path $RepoRoot $firstCachePath)) -and (Manifest-Has $validDiag "ERROR_COUNT|0"))

    $secondExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @($validInput)
    Add-Check "M10O_cache_hit_second_build" ($secondExit -eq 0 -and (Manifest-Has $validManifest "CACHE_STATUS|hit") -and (Test-Path $validExe) -and (Test-Pe-Signature $validExe) -and (Manifest-Has $validDiag "ERROR_COUNT|0"))
    Add-Check "M10O_cache_hit_no_stage_rerun" ((Manifest-Has $validManifest "STAGES_SKIPPED|lexer,parser,semantic,ir,codegen,backend") -and (Manifest-Has $validManifest "CACHE_STATUS|hit"))

    $invalidExe = Join-Path $RepoRoot "Build\EXE\cache_invalid.exe"
    Remove-Item $invalidExe -Force -ErrorAction SilentlyContinue
    $invalidExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\Cache\cache_invalid.arq")
    $invalidManifest = Join-Path $RepoRoot "Build\Manifests\cache_invalid.build.txt"
    $invalidDiag = Join-Path $RepoRoot "Build\Diagnostics\cache_invalid.all_errors.txt"
    Add-Check "M10O_cache_invalid_source_no_artifact" ($invalidExit -ne 0 -and -not (Test-Path $invalidExe) -and (Manifest-Has $invalidDiag "S010|semantic") -and (Manifest-Has $invalidManifest "STATUS|failure") -and -not (Manifest-Has $invalidManifest "CACHE_STATUS|hit"))

    $rebuildExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @($validInput, "--rebuild")
    Add-Check "M10O_cache_rebuild_flag" ($rebuildExit -eq 0 -and (Manifest-Has $validManifest "CACHE_STATUS|store") -and (Manifest-Has $validManifest "CACHE_REASON|rebuild") -and (Test-Path $validExe))

    $noCacheExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @($validInput, "--no-cache")
    Add-Check "M10O_cache_no_cache_flag" ($noCacheExit -eq 0 -and (Manifest-Has $validManifest "CACHE_STATUS|bypass") -and (Manifest-Has $validManifest "CACHE_REASON|no-cache") -and (Test-Path $validExe))

    $customExe = Join-Path $RepoRoot "Build\EXE\cache_custom.exe"
    Remove-Item $customExe -Force -ErrorAction SilentlyContinue
    $customExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @($validInput, "-o", ".\Build\EXE\cache_custom.exe")
    Add-Check "M10O_cache_custom_output" ($customExit -eq 0 -and (Manifest-Has $validManifest "CACHE_STATUS|hit") -and (Manifest-Has $validManifest "ARTIFACT_PATH|Build/EXE/cache_custom.exe") -and (Test-Path $customExe) -and (Test-Pe-Signature $customExe))

    $backendOnlyExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @("--backend-only", ".\Build\IR\hello_m10.arqir", "-o", ".\Build\EXE\hello_m10_from_ir.exe")
    $backendOnlyManifest = Join-Path $RepoRoot "Build\Manifests\hello_m10.build.txt"
    Add-Check "M10O_cache_backend_only_bypass" ($backendOnlyExit -eq 0 -and (Manifest-Has $backendOnlyManifest "CACHE_STATUS|bypass") -and (Manifest-Has $backendOnlyManifest "CACHE_REASON|backend-only") -and (Test-Path (Join-Path $RepoRoot "Build\EXE\hello_m10_from_ir.exe")))
}

function Run-M11-InvalidBlendCase {
    param(
        [string]$CheckName,
        [string]$File,
        [string]$WantCode,
        [string]$WantStage
    )

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($File)
    $input = ".\Tests\CommandTests\blend_mix_to_code\$File"
    $exe = Join-Path $RepoRoot "Build\EXE\$stem.exe"
    Remove-Item $exe -Force -ErrorAction SilentlyContinue

    $exit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @($input, "--rebuild")
    $diag = Join-Path $RepoRoot "Build\Diagnostics\$stem.all_errors.txt"
    $manifest = Join-Path $RepoRoot "Build\Manifests\$stem.build.txt"
    $diagText = if (Test-Path $diag) { Get-Content $diag -Raw } else { "" }
    $manifestText = if (Test-Path $manifest) { Get-Content $manifest -Raw } else { "" }
    $count = Diagnostic-ErrorCount $diag
    $backendSkipped = $manifestText.Contains("STAGES_SKIPPED|") -and $manifestText.Contains("backend")

    Add-Check $CheckName ($exit -ne 0 -and -not (Test-Path $exe) -and $count -gt 0 -and $diagText.Contains($WantCode) -and $diagText.Contains($WantStage) -and $backendSkipped)
}

function Run-M11-Tests {
    Write-Host ""
    Write-Host "M11 BlendMixToCode tests"

    $validStem = "valid_code_0"
    $validExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\blend_mix_to_code\valid_code_0.arq", "--rebuild")
    $validExe = Join-Path $RepoRoot "Build\EXE\$validStem.exe"
    $validAstPath = Join-Path $RepoRoot "Build\AST\$validStem.ast"
    $validIrPath = Join-Path $RepoRoot "Build\IR\$validStem.arqir"
    $validDiag = Join-Path $RepoRoot "Build\Diagnostics\$validStem.all_errors.txt"
    $validAst = if (Test-Path $validAstPath) { Get-Content $validAstPath -Raw } else { "" }
    $validIr = if (Test-Path $validIrPath) { Get-Content $validIrPath -Raw } else { "" }

    Add-Check "M11_blend_valid_build" ($validExit -eq 0 -and (Test-Path $validExe) -and (Manifest-Has $validDiag "ERROR_COUNT|0"))
    Add-Check "M11_blend_valid_ast" ($validAst.Contains("BLEND_MIX_TO_CODE|0"))
    Add-Check "M11_blend_valid_ir_exit" ($validIr.Contains("op=exit") -and $validIr.Contains("type=int|value=0") -and -not $validIr.Contains("ExitProcess") -and -not $validIr.Contains("MessageBoxW") -and -not $validIr.Contains("RVA") -and -not $validIr.Contains("IAT"))
    Check-Ui "M11_blend_valid_exe" (Join-Path $RepoRoot "Build\EXE") ".\valid_code_0.exe" -Titles @("Arqen Blend", "Blend works")

    Run-M11-InvalidBlendCase "M11_blend_missing_mix" "invalid_missing_mix.arq" "P040" "parser"
    Run-M11-InvalidBlendCase "M11_blend_missing_to" "invalid_missing_to.arq" "P041" "parser"
    Run-M11-InvalidBlendCase "M11_blend_missing_code_keyword" "invalid_missing_code_keyword.arq" "P042" "parser"
    Run-M11-InvalidBlendCase "M11_blend_missing_exit_code" "invalid_missing_exit_code.arq" "P043" "parser"
    Run-M11-InvalidBlendCase "M11_blend_nonzero_code" "invalid_nonzero_code.arq" "S021" "semantic"
    Run-M11-InvalidBlendCase "M11_blend_bool_code" "invalid_bool_code.arq" "P043" "parser"

    $exitCompat = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Samples\hello_m10.arq", "--rebuild")
    $exitAstPath = Join-Path $RepoRoot "Build\AST\hello_m10.ast"
    $exitDiag = Join-Path $RepoRoot "Build\Diagnostics\hello_m10.all_errors.txt"
    $exitAst = if (Test-Path $exitAstPath) { Get-Content $exitAstPath -Raw } else { "" }
    Add-Check "M11_exit_still_works" ($exitCompat -eq 0 -and (Test-Path (Join-Path $RepoRoot "Build\EXE\hello_m10.exe")) -and $exitAst.Contains("EXIT|0") -and (Manifest-Has $exitDiag "ERROR_COUNT|0"))
}

function Run-M12-InvalidCase {
    param(
        [string]$CheckName,
        [string]$SourcePath,
        [string]$WantCode,
        [string]$WantStage
    )

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $exe = Join-Path $RepoRoot "Build\EXE\$stem.exe"
    Remove-Item $exe -Force -ErrorAction SilentlyContinue

    $exit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @($SourcePath, "--rebuild")
    $diag = Join-Path $RepoRoot "Build\Diagnostics\$stem.all_errors.txt"
    $manifest = Join-Path $RepoRoot "Build\Manifests\$stem.build.txt"
    $diagText = if (Test-Path $diag) { Get-Content $diag -Raw } else { "" }
    $manifestText = if (Test-Path $manifest) { Get-Content $manifest -Raw } else { "" }
    $count = Diagnostic-ErrorCount $diag
    $backendSkipped = $manifestText.Contains("STAGES_SKIPPED|") -and $manifestText.Contains("backend")

    Add-Check $CheckName ($exit -ne 0 -and -not (Test-Path $exe) -and $count -gt 0 -and $diagText.Contains($WantCode) -and $diagText.Contains($WantStage) -and $backendSkipped)
}

function Run-M12-Tests {
    Write-Host ""
    Write-Host "M12 comfort command tests"

    $commentsFullExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\comments\valid_full_line_comment.arq", "--rebuild")
    $commentsFullAst = Get-Content (Join-Path $RepoRoot "Build\AST\valid_full_line_comment.ast") -Raw
    $commentsFullIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_full_line_comment.arqir") -Raw
    Add-Check "M12_comments_full_line" ($commentsFullExit -eq 0 -and $commentsFullAst.Contains("MESSAGE|Full comment works") -and -not $commentsFullAst.Contains("ignored full line comment") -and -not $commentsFullIr.Contains("ignored full line comment"))

    $commentsTrailingExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\comments\valid_trailing_comment.arq", "--rebuild")
    $commentsTrailingAst = Get-Content (Join-Path $RepoRoot "Build\AST\valid_trailing_comment.ast") -Raw
    $commentsTrailingIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_trailing_comment.arqir") -Raw
    Add-Check "M12_comments_trailing" ($commentsTrailingExit -eq 0 -and $commentsTrailingAst.Contains("MESSAGE|Trailing comment works") -and -not $commentsTrailingAst.Contains("ignored message comment") -and -not $commentsTrailingIr.Contains("ignored message comment"))

    $commentsStringExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\comments\valid_comment_inside_string.arq", "--rebuild")
    $commentsStringAst = Get-Content (Join-Path $RepoRoot "Build\AST\valid_comment_inside_string.ast") -Raw
    Add-Check "M12_comments_inside_string" ($commentsStringExit -eq 0 -and $commentsStringAst.Contains("MESSAGE|not // a comment inside string"))

    Run-M12-InvalidCase "M12_comments_single_slash_invalid" ".\Tests\CommandTests\comments\invalid_single_slash.arq" "L001" "lexer"

    $showLiteralExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\show_message\valid_literal.arq", "--rebuild")
    $showLiteralAst = Get-Content (Join-Path $RepoRoot "Build\AST\valid_literal.ast") -Raw
    $showLiteralIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_literal.arqir") -Raw
    Add-Check "M12_show_message_literal" ($showLiteralExit -eq 0 -and $showLiteralAst.Contains("SHOW_MESSAGE|Show literal works") -and $showLiteralIr.Contains("op=show_message"))

    $showConcatExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\show_message\valid_concat_variable.arq", "--rebuild")
    $showConcatAst = Get-Content (Join-Path $RepoRoot "Build\AST\valid_concat_variable.ast") -Raw
    Add-Check "M12_show_message_concat" ($showConcatExit -eq 0 -and $showConcatAst.Contains("SHOW_MESSAGE|Hello, Sqweek"))

    Run-M12-InvalidCase "M12_show_message_unknown_variable" ".\Tests\CommandTests\show_message\invalid_unknown_variable.arq" "S010" "semantic"
    Run-M12-InvalidCase "M12_show_message_bool_error" ".\Tests\CommandTests\show_message\invalid_bool_concat.arq" "S011" "semantic"
    Run-M12-InvalidCase "M12_show_message_missing_expression" ".\Tests\CommandTests\show_message\invalid_missing_expression.arq" "P061" "parser"

    $setTitleLiteralExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\set_title_to\valid_literal.arq", "--rebuild")
    $setTitleLiteralAst = Get-Content (Join-Path $RepoRoot "Build\AST\valid_literal.ast") -Raw
    $setTitleLiteralIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_literal.arqir") -Raw
    Add-Check "M12_set_title_literal" ($setTitleLiteralExit -eq 0 -and $setTitleLiteralAst.Contains("SET_TITLE|Set Title Literal") -and $setTitleLiteralIr.Contains("CONST|id=str_0|type=text|value=Set Title Literal"))

    $setTitleConcatExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\set_title_to\valid_concat_variable.arq", "--rebuild")
    $setTitleConcatAst = Get-Content (Join-Path $RepoRoot "Build\AST\valid_concat_variable.ast") -Raw
    Add-Check "M12_set_title_concat_if_supported" ($setTitleConcatExit -eq 0 -and $setTitleConcatAst.Contains("SET_TITLE|Hello, Sqweek"))

    Run-M12-InvalidCase "M12_set_title_missing_to" ".\Tests\CommandTests\set_title_to\invalid_missing_to.arq" "P051" "parser"
    Run-M12-InvalidCase "M12_set_title_missing_expression" ".\Tests\CommandTests\set_title_to\invalid_missing_expression.arq" "P052" "parser"
    Run-M12-InvalidCase "M12_set_title_unknown_variable" ".\Tests\CommandTests\set_title_to\invalid_unknown_variable.arq" "S010" "semantic"

    $oldExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Samples\hello_m10.arq", "--rebuild")
    $oldAst = Get-Content (Join-Path $RepoRoot "Build\AST\hello_m10.ast") -Raw
    Add-Check "M12_old_title_still_works" ($oldExit -eq 0 -and $oldAst.Contains("TITLE|Arqen Byte Zero") -and -not $oldAst.Contains("SET_TITLE|"))
    Add-Check "M12_old_message_text_still_works" ($oldExit -eq 0 -and $oldAst.Contains("MESSAGE|Hello, Sqweek") -and -not $oldAst.Contains("SHOW_MESSAGE|"))
    Add-Check "M12_exit_still_works" ($oldExit -eq 0 -and $oldAst.Contains("EXIT|0"))

    $blendExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\blend_mix_to_code\valid_code_0.arq", "--rebuild")
    $blendAst = Get-Content (Join-Path $RepoRoot "Build\AST\valid_code_0.ast") -Raw
    Add-Check "M12_blend_still_works" ($blendExit -eq 0 -and $blendAst.Contains("BLEND_MIX_TO_CODE|0"))
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

Run-M10JK-Tests

Run-M10L-Tests

Run-M10N-Tests

Run-M10O-Tests

Run-M11-Tests

Run-M12-Tests

Write-Host ""
Write-Host "=== Regression summary ==="

Write-Host ""
Write-Host ("Total: {0}/{1} passed" -f $script:Passed, $script:Total)

$testResultsPath = Join-Path $RepoRoot "Build\Logs\test_results.txt"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $testResultsPath) | Out-Null
$script:StructuredResults += "TOTAL|$script:Total"
$script:StructuredResults += "PASSED|$script:Passed"
$script:StructuredResults += "FAILED|$($script:Total - $script:Passed)"
Set-Content -Path $testResultsPath -Value $script:StructuredResults -Encoding UTF8

if ($script:Failures.Count -gt 0) {
    Write-Host "Failures:"
    foreach ($failure in $script:Failures) {
        Write-Host " - $failure"
    }
    exit 1
}

exit 0
