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
    $group = if ($Name.StartsWith("M14A_")) { "M14A" } elseif ($Name.StartsWith("M13B_")) { "M13B" } elseif ($Name.StartsWith("M13_")) { "M13" } elseif ($Name.StartsWith("M12B_")) { "M12B" } elseif ($Name.StartsWith("M12_")) { "M12" } elseif ($Name.StartsWith("M11_")) { "M11" } elseif ($Name.StartsWith("M10O_")) { "M10O" } elseif ($Name.StartsWith("M10N_")) { "M10N" } elseif ($Name.StartsWith("M10L_")) { "M10L" } elseif ($Name.StartsWith("M10JK")) { "M10JK" } else { "REGRESSION" }
    $resultName = if ($Name.StartsWith("M14A_")) { $Name.Substring(5) } elseif ($Name.StartsWith("M13B_")) { $Name.Substring(5) } elseif ($Name.StartsWith("M13_")) { $Name.Substring(4) } elseif ($Name.StartsWith("M12B_")) { $Name.Substring(5) } elseif ($Name.StartsWith("M12_")) { $Name.Substring(4) } elseif ($Name.StartsWith("M11_")) { $Name.Substring(4) } elseif ($Name.StartsWith("M10O_")) { $Name.Substring(5) } elseif ($Name.StartsWith("M10N_")) { $Name.Substring(5) } elseif ($Name.StartsWith("M10L_")) { $Name.Substring(5) } else { $Name }
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

function Remove-M12B-Skeleton {
    param([string]$CommandId)

    if ([string]::IsNullOrWhiteSpace($CommandId)) {
        return
    }

    $specPath = Join-Path $RepoRoot "Specs\Commands\$CommandId.command.txt"
    if (Test-Path $specPath) {
        $specText = Get-Content $specPath -Raw
        if ($specText.Contains("STATUS skeleton")) {
            Remove-Item $specPath -Force -ErrorAction SilentlyContinue
        }
    }

    $skeletonDir = Join-Path $RepoRoot "Tests\CommandSkeletons\$CommandId"
    $expectedRoot = Join-Path $RepoRoot "Tests\CommandSkeletons"
    $resolved = [IO.Path]::GetFullPath($skeletonDir)
    $rootResolved = [IO.Path]::GetFullPath($expectedRoot)
    if ($resolved.StartsWith($rootResolved, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $skeletonDir)) {
        Remove-Item $skeletonDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-M12B-VerifyCommand {
    param(
        [string]$CheckName,
        [string]$CommandId
    )

    $exit = Invoke-Stage $RepoRoot "powershell" @("-ExecutionPolicy", "Bypass", "-File", ".\Tools\CommandAutomation\verify_command_integration.ps1", "-CommandId", $CommandId)
    $norm = $CommandId.Trim().ToLowerInvariant() -replace '[\s-]+', '_'
    $outPath = Join-Path $RepoRoot "Build\Generated\CommandSkeletons\$norm.integration_verification.txt"
    $text = if (Test-Path $outPath) { Get-Content $outPath -Raw } else { "" }
    Add-Check $CheckName ($exit -eq 0 -and $text.Contains("PASS|spec_exists") -and $text.Contains("PASS|command_status") -and -not $text.Contains("FAIL|"))
}

function Run-M12B-Tests {
    Write-Host ""
    Write-Host "M12B command skeleton automation tests"

    $id = "m12b_skeleton_probe"
    $specPath = Join-Path $RepoRoot "Specs\Commands\$id.command.txt"
    $testDir = Join-Path $RepoRoot "Tests\CommandSkeletons\$id"
    $generatedDir = Join-Path $RepoRoot "Build\Generated\CommandSkeletons"
    $touchMap = Join-Path $generatedDir "$id.touch_map.txt"
    $checklist = Join-Path $generatedDir "$id.implementation_checklist.txt"
    $verifyOut = Join-Path $generatedDir "$id.integration_verification.txt"

    Remove-M12B-Skeleton $id
    Remove-Item $touchMap, $checklist, $verifyOut -Force -ErrorAction SilentlyContinue

    Add-Check "M12B_skeleton_generator_exists" (Test-Path (Join-Path $RepoRoot "Tools\CommandAutomation\new_command_skeleton.ps1"))
    Add-Check "M12B_integration_verifier_exists" (Test-Path (Join-Path $RepoRoot "Tools\CommandAutomation\verify_command_integration.ps1"))

    $dryRunExit = Invoke-Stage $RepoRoot "powershell" @(
        "-ExecutionPolicy", "Bypass",
        "-File", ".\Tools\CommandAutomation\new_command_skeleton.ps1",
        "-CommandId", $id,
        "-Syntax", "probe stop <int>",
        "-Tokens", "KEYWORD(probe) KEYWORD(stop) INT",
        "-Ast", "ProbeStop(code)",
        "-Semantic", "code must be int, only 0 supported initially",
        "-Ir", "exit",
        "-Backend", "WindowsX64PE:exit",
        "-Category", "final_statement",
        "-DryRun"
    )
    Add-Check "M12B_skeleton_dry_run" ($dryRunExit -eq 0 -and -not (Test-Path $specPath) -and -not (Test-Path $testDir))

    $generationExit = Invoke-Stage $RepoRoot "powershell" @(
        "-ExecutionPolicy", "Bypass",
        "-File", ".\Tools\CommandAutomation\new_command_skeleton.ps1",
        "-CommandId", $id,
        "-Syntax", "probe stop <int>",
        "-Tokens", "KEYWORD(probe) KEYWORD(stop) INT",
        "-Ast", "ProbeStop(code)",
        "-Semantic", "code must be int, only 0 supported initially",
        "-Ir", "exit",
        "-Backend", "WindowsX64PE:exit",
        "-Category", "final_statement",
        "-Force"
    )
    Add-Check "M12B_skeleton_generation" ($generationExit -eq 0 -and (Test-Path $specPath) -and (Test-Path (Join-Path $testDir "expected.txt")))
    Add-Check "M12B_touch_map_generated" ((Test-Path $touchMap) -and (Get-Content $touchMap -Raw).Contains("TOUCH|parser|required"))
    Add-Check "M12B_checklist_generated" ((Test-Path $checklist) -and (Get-Content $checklist -Raw).Contains("CHECK|parser_rule_added|pending"))

    Invoke-Stage $RepoRoot ".\Tools\validate_command_specs.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_keyword_registry.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_parser_rule_registry.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_test_index.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_status.ps1" | Out-Null
    $statusText = Get-Content (Join-Path $RepoRoot "Build\Generated\command_status.txt") -Raw
    Add-Check "M12B_skeleton_status_not_stable" ($statusText.Contains("COMMAND|$id|") -and $statusText.Contains("status=skeleton") -and -not $statusText.Contains("COMMAND|$id|spec=yes|tests=yes|lexer=yes|parser=yes|ast=yes|semantic=yes|ir=yes|backend=yes|status=stable"))

    Test-M12B-VerifyCommand "M12B_verify_blend_mix_to_code" "blend_mix_to_code"
    Test-M12B-VerifyCommand "M12B_verify_show_message" "show_message"
    Test-M12B-VerifyCommand "M12B_verify_set_title_to" "set_title_to"
    Test-M12B-VerifyCommand "M12B_verify_comments" "comments"

    $wrapperExit = Invoke-Stage $RepoRoot "powershell" @(
        "-ExecutionPolicy", "Bypass",
        "-File", ".\Tools\new_command_scaffold.ps1",
        "-Name", "wrapper probe",
        "-Syntax", "wrapper probe <int>",
        "-Tokens", "KEYWORD(wrapper) KEYWORD(probe) INT",
        "-Ast", "WrapperProbe(code)",
        "-Semantic", "generated wrapper skeleton",
        "-Ir", "none",
        "-Backend", "none",
        "-Category", "draft",
        "-DryRun"
    )
    $validateExit = Invoke-Stage $RepoRoot ".\Tools\validate_command_specs.ps1"
    Add-Check "M12B_existing_wrappers_still_work" ($wrapperExit -eq 0 -and $validateExit -eq 0)

    Remove-M12B-Skeleton $id
    Invoke-Stage $RepoRoot ".\Tools\generate_keyword_registry.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_parser_rule_registry.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_test_index.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_status.ps1" | Out-Null
}

function Run-M13-ValidCase {
    param(
        [string]$CheckName,
        [string]$SourcePath,
        [string]$SelectedText,
        [string]$RejectedText = "",
        [switch]$RunUi
    )

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $exit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @($SourcePath, "--rebuild")
    $exe = Join-Path $RepoRoot "Build\EXE\$stem.exe"
    $astPath = Join-Path $RepoRoot "Build\AST\$stem.ast"
    $irPath = Join-Path $RepoRoot "Build\IR\$stem.arqir"
    $diag = Join-Path $RepoRoot "Build\Diagnostics\$stem.all_errors.txt"
    $ast = if (Test-Path $astPath) { Get-Content $astPath -Raw } else { "" }
    $ir = if (Test-Path $irPath) { Get-Content $irPath -Raw } else { "" }
    $irLines = @($ir -split "\r?\n")
    $diagOk = (Manifest-Has $diag "ERROR_COUNT|0")
    $selectedOk = $ast.Contains("MESSAGE|$SelectedText") -and ($irLines -contains "CONST|id=str_1|type=text|value=$SelectedText")
    $rejectedOk = ([string]::IsNullOrWhiteSpace($RejectedText) -or (-not ($irLines -contains "CONST|id=str_1|type=text|value=$RejectedText")))
    $flowOk = $ast.Contains("IF_COMPILE_TIME|") -and $ast.Contains("IF_BRANCH_SELECTED|")
    $uiOk = $true

    if ($RunUi) {
        $ui = Invoke-UiExe -Dir (Join-Path $RepoRoot "Build\EXE") -Exe ".\$stem.exe" -Titles @("M13 If", "M13 Compare", $SelectedText)
        $uiOk = $ui.Skipped -or ($ui.Exit -eq 0 -and $ui.Activated -and -not $ui.TimedOut)
    }

    Add-Check $CheckName ($exit -eq 0 -and (Test-Path $exe) -and $diagOk -and $selectedOk -and $rejectedOk -and $flowOk -and $uiOk)
}

function Run-M13-InvalidCase {
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

function Run-M13-Tests {
    Write-Host ""
    Write-Host "M13 comparison and compile-time if tests"

    Run-M13-ValidCase "M13_comparison_int_is_true" ".\Tests\CommandTests\comparison_is\valid_int_is_true.arq" "int true" "int false"
    Run-M13-ValidCase "M13_comparison_text_is_true" ".\Tests\CommandTests\comparison_is\valid_text_is_true.arq" "text true" "text false"
    Run-M13-ValidCase "M13_comparison_bool_is_true" ".\Tests\CommandTests\comparison_is\valid_bool_is_true.arq" "bool true" "bool false"
    Run-M13-ValidCase "M13_comparison_is_not" ".\Tests\CommandTests\comparison_is\valid_is_not_true.arq" "is not true" "is not false"
    Run-M13-InvalidCase "M13_comparison_type_mismatch" ".\Tests\CommandTests\comparison_is\invalid_type_mismatch_int_text.arq" "S021" "semantic"
    Run-M13-InvalidCase "M13_comparison_unknown_variable" ".\Tests\CommandTests\comparison_is\invalid_unknown_variable.arq" "S020" "semantic"

    Run-M13-ValidCase "M13_if_true_branch" ".\Tests\CommandTests\if_compile_time\valid_if_true_branch.arq" "true branch" "false branch"
    Run-M13-ValidCase "M13_if_false_else_branch" ".\Tests\CommandTests\if_compile_time\valid_if_false_else_branch.arq" "false branch" "true branch"
    Run-M13-ValidCase "M13_if_without_else_false" ".\Tests\CommandTests\if_compile_time\valid_if_without_else_false.arq" "after if" "should not appear"
    Run-M13-ValidCase "M13_if_text_comparison" ".\Tests\CommandTests\if_compile_time\valid_text_comparison.arq" "name ok" "name bad"
    Run-M13-ValidCase "M13_if_is_not" ".\Tests\CommandTests\if_compile_time\valid_is_not.arq" "not bob" "bob"
    Run-M13-InvalidCase "M13_if_missing_condition" ".\Tests\CommandTests\if_compile_time\invalid_if_no_condition.arq" "P053" "parser"
    Run-M13-InvalidCase "M13_if_non_bool_condition" ".\Tests\CommandTests\if_compile_time\invalid_if_non_bool_condition.arq" "P052" "parser"
    Run-M13-InvalidCase "M13_if_missing_end_if" ".\Tests\CommandTests\if_compile_time\invalid_if_missing_end_if.arq" "P057" "parser"
    Run-M13-InvalidCase "M13_if_else_without_if" ".\Tests\CommandTests\if_compile_time\invalid_if_else_without_if.arq" "P055" "parser"
    Run-M13-InvalidCase "M13_if_type_mismatch" ".\Tests\CommandTests\if_compile_time\invalid_if_type_mismatch.arq" "S021" "semantic"
    Run-M13-InvalidCase "M13_if_unknown_variable" ".\Tests\CommandTests\if_compile_time\invalid_if_unknown_variable.arq" "S020" "semantic"
    Run-M13-InvalidCase "M13_if_nested_if_if_not_supported" ".\Tests\CommandTests\if_compile_time\invalid_if_nested_if_if_not_supported.arq" "P054" "parser"

    $oldHello = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Samples\hello_m10.arq", "--rebuild")
    $oldComfort = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Samples\comfort_m12.arq", "--rebuild")
    $oldBlend = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Samples\blend_m11.arq", "--rebuild")
    Add-Check "M13_old_commands_still_work" ($oldHello -eq 0 -and $oldComfort -eq 0 -and $oldBlend -eq 0)

    $cacheExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\if_compile_time\valid_if_true_branch.arq")
    $cacheManifest = Join-Path $RepoRoot "Build\Manifests\valid_if_true_branch.build.txt"
    Add-Check "M13_cache_still_works_if_present" ($cacheExit -eq 0 -and (Manifest-Has $cacheManifest "CACHE_STATUS|"))

    $diagPath = Join-Path $RepoRoot "Build\Diagnostics\invalid_if_type_mismatch.all_errors.txt"
    Add-Check "M13_diagnostics_still_work" ((Diagnostic-ErrorCount $diagPath) -gt 0 -and (Manifest-Has $diagPath "S021"))
}

function Run-M13B-Tests {
    Write-Host ""
    Write-Host "M13B parser statement automation and expected IR tests"

    $mapExit = Invoke-Stage $RepoRoot ".\Tools\generate_parser_statement_map.ps1"
    $mapPath = Join-Path $RepoRoot "Build\Generated\parser_statement_map.txt"
    $mapText = if (Test-Path $mapPath) { Get-Content $mapPath -Raw } else { "" }
    Add-Check "M13B_parser_statement_map_generation" ($mapExit -eq 0 -and (Test-Path $mapPath))
    Add-Check "M13B_parser_statement_map_core_rules" ($mapText.Contains("RULE_ID|if_statement|") -and $mapText.Contains("RULE_ID|else_statement|") -and $mapText.Contains("RULE_ID|end_if_statement|") -and $mapText.Contains("RULE_ID|blend_mix_to_code_statement|"))
    Add-Check "M13B_parser_statement_map_expected_ir_flag" ($mapText.Contains("RULE_ID|if_statement|") -and $mapText.Contains("EXPECTED_IR_AVAILABLE|true"))

    $expectedIrExit = Invoke-Stage $RepoRoot "powershell" @("-ExecutionPolicy", "Bypass", "-File", ".\Tools\verify_expected_ir.ps1")
    $expectedIrPath = Join-Path $RepoRoot "Build\Generated\expected_ir_validation.txt"
    $expectedIrText = if (Test-Path $expectedIrPath) { Get-Content $expectedIrPath -Raw } else { "" }
    Add-Check "M13B_expected_ir_checker" ($expectedIrExit -eq 0 -and (Test-Path $expectedIrPath) -and -not $expectedIrText.Contains("FAIL|"))
    Add-Check "M13B_expected_ir_true_branch" ($expectedIrText.Contains("PASS|m13b_if_true_branch|"))
    Add-Check "M13B_expected_ir_false_branch" ($expectedIrText.Contains("PASS|m13b_if_false_branch|"))
    Add-Check "M13B_expected_ir_no_else_true" ($expectedIrText.Contains("PASS|m13b_if_no_else_true|"))
    Add-Check "M13B_expected_ir_no_else_false" ($expectedIrText.Contains("PASS|m13b_if_no_else_false|"))
    Add-Check "M13B_expected_ir_is_not" ($expectedIrText.Contains("PASS|m13b_is_not_true|"))
    Add-Check "M13B_expected_ir_bool_comparison" ($expectedIrText.Contains("PASS|m13b_bool_comparison|"))

    Run-M13-InvalidCase "M13B_invalid_end_if_without_if" ".\Tests\CommandTests\if_compile_time\invalid_if_end_if_without_if.arq" "P056" "parser"
    Run-M13-InvalidCase "M13B_invalid_is_not_missing_operand" ".\Tests\CommandTests\comparison_is\invalid_missing_right_operand_after_is_not.arq" "P051" "parser"
    Run-M13-InvalidCase "M13B_invalid_duplicate_else" ".\Tests\CommandTests\if_compile_time\invalid_if_duplicate_else.arq" "P055" "parser"

    $ruleExit = Invoke-Stage $RepoRoot ".\Tools\generate_parser_rule_registry.ps1"
    $indexExit = Invoke-Stage $RepoRoot ".\Tools\generate_command_test_index.ps1"
    $statusExit = Invoke-Stage $RepoRoot ".\Tools\generate_command_status.ps1"
    Add-Check "M13B_generated_parser_rule_registry" ($ruleExit -eq 0 -and (Test-Path (Join-Path $RepoRoot "Build\Generated\parser_rule_registry.txt")))
    Add-Check "M13B_generated_command_test_index" ($indexExit -eq 0 -and (Test-Path (Join-Path $RepoRoot "Build\Generated\command_test_index.txt")))
    Add-Check "M13B_generated_command_status" ($statusExit -eq 0 -and (Test-Path (Join-Path $RepoRoot "Build\Generated\command_status.txt")))
}

function Run-M14A-Tests {
    Write-Host ""
    Write-Host "M14A canonical define/show/title and rename tests"

    $defineExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\canonical_define\valid_typed_values.arq", "--rebuild")
    $defineAst = Get-Content (Join-Path $RepoRoot "Build\AST\valid_typed_values.ast") -Raw
    Add-Check "M14A_define_typed_values" ($defineExit -eq 0 -and $defineAst.Contains("LET|name|text|Sqweek") -and $defineAst.Contains("LET|score|int|10") -and $defineAst.Contains("LET|alive|bool|true"))

    $showStringExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\canonical_show\valid_show_string.arq", "--rebuild")
    $showStringIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_show_string.arqir") -Raw
    Add-Check "M14A_show_string_literal" ($showStringExit -eq 0 -and $showStringIr.Contains("value=Hello"))

    $showValueExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\canonical_show\valid_show_int_symbol.arq", "--rebuild")
    $showValueIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_show_int_symbol.arqir") -Raw
    Add-Check "M14A_show_quoted_value" ($showValueExit -eq 0 -and $showValueIr.Contains("value=10"))

    $titleLiteralExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\canonical_title\valid_title_literal.arq", "--rebuild")
    $titleLiteralIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_title_literal.arqir") -Raw
    Add-Check "M14A_set_title_string_literal" ($titleLiteralExit -eq 0 -and $titleLiteralIr.Contains("CONST|id=str_0|type=text|value=Arqen"))

    $titleSymbolExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\canonical_title\valid_title_symbol.arq", "--rebuild")
    $titleSymbolIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_title_symbol.arqir") -Raw
    Add-Check "M14A_set_title_symbol" ($titleSymbolExit -eq 0 -and $titleSymbolIr.Contains("CONST|id=str_0|type=text|value=Arqen"))

    $renameExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\rename\valid_rename_int.arq", "--rebuild")
    $renameIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_rename_int.arqir") -Raw
    Add-Check "M14A_rename_keeps_value" ($renameExit -eq 0 -and $renameIr.Contains("CONST|id=str_1|type=text|value=10"))

    Run-M13-InvalidCase "M14A_define_missing_called" ".\Tests\CommandTests\canonical_define\invalid_missing_called.arq" "P071" "parser"
    Run-M13-InvalidCase "M14A_define_missing_quoted_name" ".\Tests\CommandTests\canonical_define\invalid_missing_quoted_name.arq" "P072" "parser"
    Run-M13-InvalidCase "M14A_define_missing_be" ".\Tests\CommandTests\canonical_define\invalid_missing_be.arq" "P073" "parser"
    Run-M13-InvalidCase "M14A_define_invalid_int" ".\Tests\CommandTests\canonical_define\invalid_int_value.arq" "S031" "semantic"
    Run-M13-InvalidCase "M14A_define_invalid_bool" ".\Tests\CommandTests\canonical_define\invalid_bool_value.arq" "S032" "semantic"
    Run-M13-InvalidCase "M14A_define_duplicate_symbol" ".\Tests\CommandTests\canonical_define\invalid_duplicate_symbol.arq" "S001" "semantic"
    Run-M13-InvalidCase "M14A_show_missing_symbol" ".\Tests\CommandTests\canonical_show\invalid_show_missing_symbol.arq" "S036" "semantic"
    Run-M13-InvalidCase "M14A_title_missing_symbol" ".\Tests\CommandTests\canonical_title\invalid_title_missing_symbol.arq" "S036" "semantic"
    Run-M13-InvalidCase "M14A_rename_missing_symbol" ".\Tests\CommandTests\rename\invalid_missing_symbol.arq" "S034" "semantic"
    Run-M13-InvalidCase "M14A_rename_existing_symbol" ".\Tests\CommandTests\rename\invalid_existing_target.arq" "S035" "semantic"
    Run-M13-InvalidCase "M14A_rename_old_name_missing" ".\Tests\CommandTests\rename\invalid_show_old_name_after_rename.arq" "S036" "semantic"

    $expectedIrExit = Invoke-Stage $RepoRoot "powershell" @("-ExecutionPolicy", "Bypass", "-File", ".\Tools\verify_expected_ir.ps1")
    $expectedIrText = Get-Content (Join-Path $RepoRoot "Build\Generated\expected_ir_validation.txt") -Raw
    Add-Check "M14A_expected_ir_show_title_if_rename" ($expectedIrExit -eq 0 -and $expectedIrText.Contains("PASS|m14a_show_string_literal|") -and $expectedIrText.Contains("PASS|m14a_title_symbol|") -and $expectedIrText.Contains("PASS|m14a_if_canonical_int|") -and $expectedIrText.Contains("PASS|m14a_rename_string|"))

    $mapExit = Invoke-Stage $RepoRoot ".\Tools\generate_parser_statement_map.ps1"
    $mapText = Get-Content (Join-Path $RepoRoot "Build\Generated\parser_statement_map.txt") -Raw
    Add-Check "M14A_parser_statement_map" ($mapExit -eq 0 -and $mapText.Contains("RULE_ID|define_statement|") -and $mapText.Contains("RULE_ID|rename_statement|") -and $mapText.Contains("RULE_ID|show_string_statement|") -and $mapText.Contains("RULE_ID|show_value_statement|"))

    $legacyHello = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Samples\hello_m10.arq", "--rebuild")
    $legacyComfort = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Samples\comfort_m12.arq", "--rebuild")
    Add-Check "M14A_legacy_syntax_still_works" ($legacyHello -eq 0 -and $legacyComfort -eq 0)

    Invoke-Stage $RepoRoot ".\Tools\generate_parser_rule_registry.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_test_index.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_status.ps1" | Out-Null
}

function Run-M14C-Tests {
    Write-Host ""
    Write-Host "M14C usable canonical language slice tests"

    $printExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\print\valid_print_values.arq", "--rebuild")
    $printIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_print_values.arqir") -Raw
    Add-Check "M14C_print_values" ($printExit -eq 0 -and $printIr.Contains("value=Hi\nSqweek\n10\ntrue"))

    $setExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\set_value\valid_set_values.arq", "--rebuild")
    $setIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_set_values.arqir") -Raw
    Add-Check "M14C_set_values" ($setExit -eq 0 -and $setIr.Contains("value=Arqen\n14\nfalse"))

    $numericExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\numeric_expression\valid_precedence.arq", "--rebuild")
    $numericIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_precedence.arqir") -Raw
    Add-Check "M14C_numeric_precedence" ($numericExit -eq 0 -and $numericIr.Contains("value=14\n20\n5\n8\n1"))

    $whileExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\while_compile_time\valid_countdown.arq", "--rebuild")
    $whileIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_countdown.arqir") -Raw
    Add-Check "M14C_while_countdown" ($whileExit -eq 0 -and $whileIr.Contains("value=3\n2\n1"))

    $functionExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\function\valid_simple_function.arq", "--rebuild")
    $functionIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_simple_function.arqir") -Raw
    Add-Check "M14C_function_call" ($functionExit -eq 0 -and $functionIr.Contains("value=Hello, Sqweek"))

    Run-M13-InvalidCase "M14C_set_const_error" ".\Tests\CommandTests\set_value\invalid_set_const.arq" "S053" "semantic"
    Run-M13-InvalidCase "M14C_while_guard_error" ".\Tests\CommandTests\while_compile_time\invalid_guard_exceeded.arq" "S047" "semantic"
    Run-M13-InvalidCase "M14C_recursive_function_error" ".\Tests\CommandTests\function\invalid_recursive_call.arq" "S051" "semantic"
    Run-M13-InvalidCase "M14C_division_by_zero_error" ".\Tests\CommandTests\numeric_expression\invalid_division_by_zero.arq" "S046" "semantic"
    Run-M13-InvalidCase "M14C_rename_const_error" ".\Tests\CommandTests\rename\invalid_rename_const.arq" "S039" "semantic"

    $expectedIrExit = Invoke-Stage $RepoRoot "powershell" @("-ExecutionPolicy", "Bypass", "-File", ".\Tools\verify_expected_ir.ps1")
    $expectedIrText = Get-Content (Join-Path $RepoRoot "Build\Generated\expected_ir_validation.txt") -Raw
    Add-Check "M14C_expected_ir" ($expectedIrExit -eq 0 -and $expectedIrText.Contains("PASS|m14c_print_string_literal|") -and $expectedIrText.Contains("PASS|m14c_while_countdown|") -and $expectedIrText.Contains("PASS|m14c_function_call|") -and $expectedIrText.Contains("PASS|m14c_parenthesized_expression|"))

    $mapExit = Invoke-Stage $RepoRoot ".\Tools\generate_parser_statement_map.ps1"
    $mapText = Get-Content (Join-Path $RepoRoot "Build\Generated\parser_statement_map.txt") -Raw
    Add-Check "M14C_parser_statement_map" ($mapExit -eq 0 -and $mapText.Contains("RULE_ID|print_statement|") -and $mapText.Contains("RULE_ID|set_value_statement|") -and $mapText.Contains("RULE_ID|while_statement|") -and $mapText.Contains("RULE_ID|function_statement|"))

    Invoke-Stage $RepoRoot ".\Tools\generate_parser_rule_registry.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_test_index.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_status.ps1" | Out-Null
}

function Run-M15-Tests {
    Write-Host ""
    Write-Host "M15 real app layer stdout tests"

    $stdoutExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\ExpectedIR\m15_stdout_print.arq", "--rebuild")
    $stdoutIr = Get-Content (Join-Path $RepoRoot "Build\IR\m15_stdout_print.arqir") -Raw
    $stdoutManifest = Get-Content (Join-Path $RepoRoot "Build\Manifests\m15_stdout_print.manifest.txt") -Raw
    Add-Check "M15_stdout_ir" ($stdoutExit -eq 0 -and $stdoutIr.Contains("op=print_stdout") -and -not $stdoutIr.Contains("op=show_message"))
    Add-Check "M15_stdout_manifest" ($stdoutManifest.Contains("BACKEND|WindowsX64PE_StdoutBackend") -and $stdoutManifest.Contains("ACTIONS|print_stdout,exit"))

    $exePath = Join-Path $RepoRoot "Build\EXE\m15_stdout_print.exe"
    $stdoutText = ""
    $runExit = 1
    if (Test-Path $exePath) {
        Push-Location (Split-Path -Parent $exePath)
        $stdoutText = (& ".\m15_stdout_print.exe") -join "`n"
        $runExit = $LASTEXITCODE
        Pop-Location
    }
    Add-Check "M15_stdout_runtime" ($runExit -eq 0 -and $stdoutText -eq "Hello`nSqweek`n14`n4.5`ntrue")

    $expectedIrExit = Invoke-Stage $RepoRoot "powershell" @("-ExecutionPolicy", "Bypass", "-File", ".\Tools\verify_expected_ir.ps1")
    $expectedIrText = Get-Content (Join-Path $RepoRoot "Build\Generated\expected_ir_validation.txt") -Raw
    Add-Check "M15_expected_ir" ($expectedIrExit -eq 0 -and $expectedIrText.Contains("PASS|m15_stdout_print|"))

    $mapExit = Invoke-Stage $RepoRoot ".\Tools\generate_parser_statement_map.ps1"
    $mapText = Get-Content (Join-Path $RepoRoot "Build\Generated\parser_statement_map.txt") -Raw
    Add-Check "M15_parser_statement_map" ($mapExit -eq 0 -and $mapText.Contains("RULE_ID|print_statement|"))

    Invoke-Stage $RepoRoot ".\Tools\generate_parser_rule_registry.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_test_index.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_status.ps1" | Out-Null
}

function Run-M15B-Tests {
    Write-Host ""
    Write-Host "M15B visual buffer tests"

    $visualExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\ExpectedIR\m15b_visual_buffer.arq", "--rebuild")
    $visualIr = Get-Content (Join-Path $RepoRoot "Build\IR\m15b_visual_buffer.arqir") -Raw
    $visualManifest = Get-Content (Join-Path $RepoRoot "Build\Manifests\m15b_visual_buffer.manifest.txt") -Raw
    $visualExe = Join-Path $RepoRoot "Build\EXE\m15b_visual_buffer.exe"
    Add-Check "M15B_visual_ir" ($visualExit -eq 0 -and $visualIr.Contains("op=show_message") -and -not $visualIr.Contains("op=print_stdout"))
    Add-Check "M15B_visual_manifest" ($visualManifest.Contains("BACKEND|WindowsX64PE_MessageBoxBackend") -and $visualManifest.Contains("ACTIONS|show_message,exit"))
    Add-Check "M15B_visual_pe" ((Test-Path $visualExe) -and (Test-Pe-Signature $visualExe))

    $expectedIrExit = Invoke-Stage $RepoRoot "powershell" @("-ExecutionPolicy", "Bypass", "-File", ".\Tools\verify_expected_ir.ps1")
    $expectedIrText = Get-Content (Join-Path $RepoRoot "Build\Generated\expected_ir_validation.txt") -Raw
    Add-Check "M15B_expected_ir" ($expectedIrExit -eq 0 -and $expectedIrText.Contains("PASS|m15b_visual_buffer|"))

    Invoke-Stage $RepoRoot ".\Tools\generate_parser_rule_registry.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_test_index.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_status.ps1" | Out-Null
}

function Run-M15C-Tests {
    Write-Host ""
    Write-Host "M15C runtime text file I/O tests"

    $demoExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\file_io\valid_file_io_demo.arq", "--rebuild")
    $symbolsExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\file_io\valid_file_io_symbols.arq", "--rebuild")
    $numericExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\file_io\valid_file_io_numeric.arq", "--rebuild")
    $missingRuntimeExit = Invoke-Stage $RepoRoot ".\Tools\arqc_m10jk.ps1" @(".\Tests\CommandTests\file_io\valid_load_missing_runtime.arq", "--rebuild")

    $demoIr = Get-Content (Join-Path $RepoRoot "Build\IR\valid_file_io_demo.arqir") -Raw
    Add-Check "M15C_file_io_ir" ($demoExit -eq 0 -and $demoIr.Contains("op=file_write") -and $demoIr.Contains("op=file_append") -and $demoIr.Contains("op=file_load") -and $demoIr.Contains("op=print_runtime_slot"))

    Add-Check "M15C_file_io_manifest" ((Get-Content (Join-Path $RepoRoot "Build\Manifests\valid_file_io_demo.manifest.txt") -Raw).Contains("BACKEND|WindowsX64PE_FileIoBackend"))

    Test-M15C-Runtime "M15C_file_io_demo_runtime" "valid_file_io_demo.exe" "log.txt" "Hello again" "Hello again"
    Test-M15C-Runtime "M15C_file_io_symbols_runtime" "valid_file_io_symbols.exe" "log.txt" "First`nSecond" "First`nSecond"
    Test-M15C-Runtime "M15C_file_io_numeric_runtime" "valid_file_io_numeric.exe" "stats.txt" "Score: 14`nSpeed: 4.5`nAlive: true" "Score: 14`nSpeed: 4.5`nAlive: true"
    Test-M15C-RuntimeFailure "M15C_file_io_missing_runtime_failure" "valid_load_missing_runtime.exe"

    $expectedIrExit = Invoke-Stage $RepoRoot "powershell" @("-ExecutionPolicy", "Bypass", "-File", ".\Tools\verify_expected_ir.ps1")
    $expectedIrText = Get-Content (Join-Path $RepoRoot "Build\Generated\expected_ir_validation.txt") -Raw
    Add-Check "M15C_expected_ir" ($expectedIrExit -eq 0 -and $expectedIrText.Contains("PASS|m15c_file_io_demo|") -and $expectedIrText.Contains("PASS|m15c_file_io_symbols|"))

    $mapExit = Invoke-Stage $RepoRoot ".\Tools\generate_parser_statement_map.ps1"
    $mapText = Get-Content (Join-Path $RepoRoot "Build\Generated\parser_statement_map.txt") -Raw
    Add-Check "M15C_parser_statement_map" ($mapExit -eq 0 -and $mapText.Contains("RULE_ID|file_io_statement|COMMAND_ID|file_io"))

    Invoke-Stage $RepoRoot ".\Tools\generate_parser_rule_registry.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_test_index.ps1" | Out-Null
    Invoke-Stage $RepoRoot ".\Tools\generate_command_status.ps1" | Out-Null
}

function Test-M15C-RuntimeFailure {
    param(
        [string]$Name,
        [string]$ExeName
    )

    $tmp = Join-Path $env:TEMP ("arqen_m15c_fail_" + [IO.Path]::GetFileNameWithoutExtension($ExeName) + "_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    Copy-Item (Join-Path $RepoRoot "Build\EXE\$ExeName") $tmp -Force
    Push-Location $tmp
    & ".\$ExeName" | Out-Null
    $exit = $LASTEXITCODE
    Pop-Location
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

    Add-Check $Name ($exit -ne 0)
}

function Test-M15C-Runtime {
    param(
        [string]$Name,
        [string]$ExeName,
        [string]$OutputFile,
        [string]$ExpectedStdout,
        [string]$ExpectedFile
    )

    $tmp = Join-Path $env:TEMP ("arqen_m15c_" + [IO.Path]::GetFileNameWithoutExtension($ExeName) + "_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    Copy-Item (Join-Path $RepoRoot "Build\EXE\$ExeName") $tmp -Force
    Push-Location $tmp
    $stdout = (& ".\$ExeName") -join "`n"
    $exit = $LASTEXITCODE
    $fileText = if (Test-Path $OutputFile) { (Get-Content $OutputFile -Raw).TrimEnd("`r", "`n") } else { "" }
    Pop-Location
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

    Add-Check $Name ($exit -eq 0 -and $stdout -eq $ExpectedStdout -and $fileText -eq $ExpectedFile)
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

Run-M12B-Tests

Run-M13-Tests

Run-M13B-Tests

Run-M14A-Tests

Run-M14C-Tests

Run-M15-Tests

Run-M15B-Tests

Run-M15C-Tests

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
