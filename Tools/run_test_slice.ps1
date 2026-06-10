param(
    [string[]]$Folder = @(),
    [string[]]$Group = @(),
    [string[]]$Case = @(),
    [string[]]$Tool = @(),
    [switch]$Changed,
    [switch]$AllCommand,
    [switch]$List,
    [switch]$BuildDriver,
    [switch]$StopOnFail
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$CommandRoot = Join-Path $RepoRoot "Tests\CommandTests"
$BuildLogs = Join-Path $RepoRoot "Build\Logs"
New-Item -ItemType Directory -Force -Path $BuildLogs | Out-Null

$script:Total = 0
$script:Passed = 0
$script:Failures = @()
$script:StructuredResults = New-Object System.Collections.Generic.List[string]

function Normalize-NameList {
    param([string[]]$Values)

    $out = New-Object System.Collections.Generic.List[string]
    foreach ($value in $Values) {
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        foreach ($part in ($value -split ",")) {
            $trimmed = $part.Trim()
            if ($trimmed -ne "") { $out.Add($trimmed) | Out-Null }
        }
    }
    return @($out.ToArray())
}

function Add-Check {
    param(
        [string]$Name,
        [bool]$Pass,
        [string]$Note = ""
    )

    $script:Total += 1
    if ($Pass) {
        $script:Passed += 1
        $script:StructuredResults.Add("PASS|$Name|$Note") | Out-Null
        Write-Host ("{0} PASS {1}" -f $Name, $Note)
    } else {
        $script:Failures += "$Name $Note"
        $script:StructuredResults.Add("FAIL|$Name|$Note") | Out-Null
        Write-Host ("{0} FAIL {1}" -f $Name, $Note)
        if ($StopOnFail) {
            Write-SummaryAndExit 1
        }
    }
}

function Write-SummaryAndExit {
    param([int]$Code)

    Write-Host ""
    Write-Host "=== Test slice summary ==="
    Write-Host ("Total: {0}/{1} passed" -f $script:Passed, $script:Total)
    if ($script:Failures.Count -gt 0) {
        Write-Host "Failures:"
        foreach ($failure in $script:Failures) {
            Write-Host " - $failure"
        }
    }

    $logPath = Join-Path $BuildLogs "test_slice.last.txt"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(("TOTAL|{0}|{1}" -f $script:Passed, $script:Total)) | Out-Null
    foreach ($line in $script:StructuredResults) { $lines.Add($line) | Out-Null }
    [System.IO.File]::WriteAllLines($logPath, $lines, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("LOG|{0}" -f (Resolve-Path $logPath).Path)
    exit $Code
}

function Invoke-RepoCommand {
    param(
        [string]$Exe,
        [string[]]$StageArgs = @()
    )

    Push-Location $RepoRoot
    try {
        $oldErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & $Exe @StageArgs *> $null
            $exit = $LASTEXITCODE
            if ($null -eq $exit) {
                $exit = if ($?) { 0 } else { 1 }
            }
            return [int]$exit
        } finally {
            $ErrorActionPreference = $oldErrorActionPreference
        }
    } finally {
        Pop-Location
    }
}

function Matches-AnyPattern {
    param(
        [string]$Text,
        [string[]]$Patterns
    )

    if ($Patterns.Count -eq 0) { return $true }
    foreach ($pattern in $Patterns) {
        if ($Text -like "*$pattern*") { return $true }
    }
    return $false
}

function Run-CommandFolder {
    param(
        [string]$FolderName,
        [string[]]$CasePatterns = @()
    )

    $folderPath = Join-Path $CommandRoot $FolderName
    if (-not (Test-Path $folderPath)) {
        Add-Check ("CMD_{0}_FOLDER_EXISTS" -f $FolderName.ToUpperInvariant()) $false "missing folder"
        return
    }

    $expectedPath = Join-Path $folderPath "expected.txt"
    if (-not (Test-Path $expectedPath)) {
        Add-Check ("CMD_{0}_EXPECTED" -f $FolderName.ToUpperInvariant()) $false "missing expected.txt"
        return
    }

    $lines = @(Get-Content $expectedPath | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") })
    $matchedCases = 0
    foreach ($line in $lines) {
        $parts = $line.Split("|")
        if ($parts.Length -lt 4) {
            Add-Check ("CMD_{0}_BAD_EXPECTED" -f $FolderName.ToUpperInvariant()) $false $line
            continue
        }

        $file = $parts[0]
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $name = "CMD_{0}_{1}" -f $FolderName.ToUpperInvariant(), $stem.ToUpperInvariant()
        if (-not (Matches-AnyPattern $file $CasePatterns) -and -not (Matches-AnyPattern $stem $CasePatterns) -and -not (Matches-AnyPattern $name $CasePatterns)) {
            continue
        }
        $matchedCases += 1

        $wantExit = [int]$parts[1]
        $kind = $parts[2]
        $want = $parts[3]
        $stage = if ($parts.Length -ge 5) { $parts[4] } else { "" }
        $sourcePath = Join-Path $folderPath $file

        if (-not (Test-Path $sourcePath)) {
            Add-Check $name $false "missing input $file"
            continue
        }

        $exit = Invoke-RepoCommand ".\Tools\arqc_m10g.exe" @($sourcePath)

        if ($kind -eq "MESSAGE") {
            $astPath = Join-Path $RepoRoot "Build\AST\$stem.ast"
            $ast = if (Test-Path $astPath) { Get-Content $astPath -Raw } else { "" }
            $ok = ($exit -eq $wantExit -and $ast.Contains("MESSAGE|$want"))
            $note = if ($ok) { "" } else { "exit=$exit expected=$wantExit ast=$([System.IO.Path]::GetFileName($astPath))" }
            Add-Check $name $ok $note
        } elseif ($kind -eq "ERROR") {
            $errPath = Join-Path $RepoRoot "Build\Errors\$stem.$stage.error.txt"
            $err = if (Test-Path $errPath) { Get-Content $errPath -Raw } else { "" }
            $ok = ($exit -eq $wantExit -and $err.Contains("Error $want"))
            $note = "stage=$stage code=$want"
            if (-not $ok) { $note = "$note exit=$exit expected=$wantExit err=$([System.IO.Path]::GetFileName($errPath))" }
            Add-Check $name $ok $note
        } else {
            Add-Check $name $false "unknown expected kind $kind"
        }
    }

    if ($CasePatterns.Count -gt 0 -and $matchedCases -eq 0) {
        Add-Check ("CMD_{0}_CASE_MATCH" -f $FolderName.ToUpperInvariant()) $false "no cases matched: $($CasePatterns -join ', ')"
    }
}

$ToolMap = [ordered]@{
    "repo_hygiene" = "Tools\validate_repo_hygiene.ps1"
    "hygiene" = "Tools\validate_repo_hygiene.ps1"
    "backend_capabilities" = "Tools\validate_backend_capabilities.ps1"
    "capabilities" = "Tools\validate_backend_capabilities.ps1"
    "command_coverage" = "Tools\validate_command_test_coverage.ps1"
    "coverage" = "Tools\validate_command_test_coverage.ps1"
    "error_registry" = "Tools\generate_error_code_registry.ps1"
    "errors" = "Tools\generate_error_code_registry.ps1"
    "runtime_registry" = "Tools\generate_runtime_action_registry.ps1"
    "runtime" = "Tools\generate_runtime_action_registry.ps1"
    "ir_contract" = "Tools\validate_ir_contract.ps1"
    "ir" = "Tools\validate_ir_contract.ps1"
    "wrapper_cache" = "Tools\validate_wrapper_cache_contract.ps1"
    "cache" = "Tools\validate_wrapper_cache_contract.ps1"
    "dx12_readiness" = "Tools\validate_dx12_readiness.ps1"
    "dx12" = "Tools\validate_dx12_readiness.ps1"
    "m19a_runtime_loop" = "Tools\validate_m19a_runtime_loop_contract.ps1"
    "runtime_loop" = "Tools\validate_m19a_runtime_loop_contract.ps1"
    "m19b_style" = "Tools\validate_m19b_style_contract.ps1"
    "style_contract" = "Tools\validate_m19b_style_contract.ps1"
    "m19c_ui" = "Tools\validate_m19c_ui_contract.ps1"
    "ui_contract" = "Tools\validate_m19c_ui_contract.ps1"
    "m19d_layout" = "Tools\validate_m19d_ui_layout_contract.ps1"
    "ui_layout_contract" = "Tools\validate_m19d_ui_layout_contract.ps1"
    "m19efgh_ui" = "Tools\validate_m19efgh_ui_final_contract.ps1"
    "ui_final_contract" = "Tools\validate_m19efgh_ui_final_contract.ps1"
    "backend_docs" = "Tools\validate_backend_contract_docs.ps1"
    "docs" = "Tools\validate_backend_contract_docs.ps1"
    "parser_split" = "Tools\validate_parser_split.ps1"
    "parser" = "Tools\validate_parser_split.ps1"
    "strict_ir" = "Tools\validate_strict_ir.ps1"
    "keyword_registry" = "Tools\validate_keyword_registry.ps1"
    "keywords" = "Tools\validate_keyword_registry.ps1"
    "parser_statement_map" = "Tools\validate_parser_statement_map.ps1"
    "statement_map" = "Tools\validate_parser_statement_map.ps1"
    "test_slice_self" = "Tools\validate_test_slice.ps1"
}

function Run-ToolCheck {
    param([string]$Alias)

    if (-not $ToolMap.Contains($Alias)) {
        Add-Check ("TOOL_{0}" -f $Alias.ToUpperInvariant()) $false "unknown tool alias"
        return
    }

    $relative = $ToolMap[$Alias]
    $path = Join-Path $RepoRoot $relative
    $name = "TOOL_{0}" -f $Alias.ToUpperInvariant()
    if (-not (Test-Path $path)) {
        Add-Check $name $false "missing $relative"
        return
    }

    $exit = Invoke-RepoCommand (".\" + $relative) @()
    Add-Check $name ($exit -eq 0) ("exit=$exit")
}

function Existing-CommandFolders {
    if (-not (Test-Path $CommandRoot)) { return @() }
    return @(Get-ChildItem $CommandRoot -Directory | Sort-Object Name | ForEach-Object { $_.Name })
}

function Add-Unique {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    if (-not $List.Contains($Value)) { $List.Add($Value) | Out-Null }
}

function Expand-Group {
    param([string]$GroupName)

    $folders = New-Object System.Collections.Generic.List[string]
    $tools = New-Object System.Collections.Generic.List[string]

    switch ($GroupName.ToLowerInvariant()) {
        "math" {
            foreach ($f in @("scalar_math","advanced_math","numeric_expression","math_update","vector_math","color_angle","complex_math","quaternion_math","geometry_math","interpolation_easing","math_core_hardening","math_regression_expansion","procedural_coordinate_math","complete_math_scalar_bit_curve","geometry_space_math")) { Add-Unique $folders $f }
        }
        "geometry" {
            foreach ($f in @("geometry_math","geometry_space_math","quaternion_math","vector_math","procedural_coordinate_math")) { Add-Unique $folders $f }
        }
        "backend" {
            foreach ($f in @("file_io","command_args","window","print","show_message","exit")) { Add-Unique $folders $f }
            foreach ($t in @("backend_capabilities","backend_docs","ir_contract")) { Add-Unique $tools $t }
        }
        "m18a" {
            foreach ($t in @("repo_hygiene","backend_capabilities","command_coverage","error_registry")) { Add-Unique $tools $t }
        }
        "m18b" {
            foreach ($t in @("runtime_registry","ir_contract","wrapper_cache","dx12_readiness","backend_docs")) { Add-Unique $tools $t }
        }
        "m19a" {
            foreach ($t in @("runtime_registry","ir_contract","dx12_readiness","backend_docs","m19a_runtime_loop")) { Add-Unique $tools $t }
        }
        "m19b" {
            foreach ($f in @("style")) { Add-Unique $folders $f }
            foreach ($t in @("m19b_style","keyword_registry","parser_statement_map","command_coverage","ir_contract","backend_docs","test_slice_self")) { Add-Unique $tools $t }
        }
        "m19c" {
            foreach ($f in @("ui_objects","style")) { Add-Unique $folders $f }
            foreach ($t in @("m19c_ui","m19b_style","keyword_registry","parser_statement_map","command_coverage","ir_contract","backend_docs","test_slice_self")) { Add-Unique $tools $t }
        }
        "m19d" {
            foreach ($f in @("ui_layout","ui_objects","style")) { Add-Unique $folders $f }
            foreach ($t in @("m19d_layout","m19c_ui","m19b_style","keyword_registry","parser_statement_map","command_coverage","ir_contract","backend_docs","test_slice_self")) { Add-Unique $tools $t }
        }
        "m19efgh" {
            foreach ($f in @("ui_final","ui_layout","ui_objects","style")) { Add-Unique $folders $f }
            foreach ($t in @("m19efgh_ui","m19d_layout","m19c_ui","m19b_style","keyword_registry","parser_statement_map","command_coverage","ir_contract","backend_docs","test_slice_self")) { Add-Unique $tools $t }
        }
        "ui_final" {
            foreach ($f in @("ui_final","ui_layout","ui_objects","style")) { Add-Unique $folders $f }
            foreach ($t in @("m19efgh_ui","m19d_layout","m19c_ui","m19b_style","keyword_registry","parser_statement_map","command_coverage","ir_contract","backend_docs","test_slice_self")) { Add-Unique $tools $t }
        }
        "m18fg" {
            foreach ($t in @("parser_split","ir_contract","runtime_registry")) { Add-Unique $tools $t }
        }
        "refactor" {
            foreach ($t in @("parser_split","ir_contract","runtime_registry","backend_docs")) { Add-Unique $tools $t }
        }
        "tooling" {
            foreach ($t in @("repo_hygiene","backend_capabilities","command_coverage","error_registry","runtime_registry","ir_contract","wrapper_cache","dx12_readiness","m19a_runtime_loop","m19b_style","m19c_ui","m19d_layout","m19efgh_ui","backend_docs","parser_split","strict_ir","keyword_registry","parser_statement_map","test_slice_self")) { Add-Unique $tools $t }
        }
        "core" {
            foreach ($f in @("program","let","set_value","message_text","show_message","title","set_title_to","exit","blend_mix_to_code","comments","comparison_is","logical_condition","if_compile_time","while_compile_time","function")) { Add-Unique $folders $f }
        }
        "flow" {
            foreach ($f in @("comparison_is","logical_condition","if_compile_time","while_compile_time","function")) { Add-Unique $folders $f }
        }
        "m18h" {
            foreach ($t in @("repo_hygiene","test_slice_self","keyword_registry","parser_statement_map")) { Add-Unique $tools $t }
        }
        "m18i" {
            foreach ($t in @("ir_contract","strict_ir")) { Add-Unique $tools $t }
        }
        "m18j" {
            foreach ($t in @("keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "commands" {
            foreach ($f in Existing-CommandFolders) { Add-Unique $folders $f }
        }
        default {
            if ((Existing-CommandFolders) -contains $GroupName) {
                Add-Unique $folders $GroupName
            } elseif ($ToolMap.Contains($GroupName)) {
                Add-Unique $tools $GroupName
            } else {
                Add-Check ("GROUP_{0}" -f $GroupName.ToUpperInvariant()) $false "unknown group"
            }
        }
    }

    return @{ Folders = @($folders.ToArray()); Tools = @($tools.ToArray()) }
}

function Add-ChangedTargets {
    param(
        [System.Collections.Generic.List[string]]$Folders,
        [System.Collections.Generic.List[string]]$Tools
    )

    $changedFiles = @()
    try {
        $trackedChanged = @(git -C $RepoRoot diff --name-only HEAD | ForEach-Object { $_ -replace "\\", "/" })
        $untrackedChanged = @(git -C $RepoRoot ls-files --others --exclude-standard | ForEach-Object { $_ -replace "\\", "/" })
        $changedFiles = @($trackedChanged + $untrackedChanged | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    } catch {
        Write-Host "WARN|changed|git diff/untracked scan failed: $($_.Exception.Message)"
        return
    }

    $allFolders = Existing-CommandFolders
    foreach ($file in $changedFiles) {
        if ($file -match '^Tests/CommandTests/([^/]+)/') {
            Add-Unique $Folders $Matches[1]
            continue
        }
        if ($file -match '^Specs/Commands/([^/]+)\.command\.txt$') {
            $candidate = $Matches[1]
            if ($allFolders -contains $candidate) { Add-Unique $Folders $candidate }
            Add-Unique $Tools "command_coverage"
            Add-Unique $Tools "keyword_registry"
            Add-Unique $Tools "parser_statement_map"
            continue
        }
        if ($file -match '^Tools/M10GDriver/Frontend/Lexer\.cs$') {
            Add-Unique $Tools "keyword_registry"
            Add-Unique $Tools "parser_statement_map"
            Add-Unique $Tools "parser_split"
            continue
        }
        if ($file -eq "Tools/M10GDriver/Program.cs") {
            Write-Host "WARN|changed|Program.cs changed; selecting parser/refactor tools and all command tests. Use -Folder/-Group manually for a smaller slice."
            Add-Unique $Tools "parser_split"
            Add-Unique $Tools "ir_contract"
            foreach ($f in $allFolders) { Add-Unique $Folders $f }
            continue
        }
        if ($file -match '^Tools/M10GDriver/.+\.cs$') {
            Write-Host "WARN|changed|Tools/M10GDriver changed; selecting parser/refactor tools. Add command folders manually for behavior checks."
            Add-Unique $Tools "parser_split"
            Add-Unique $Tools "ir_contract"
            Add-Unique $Tools "runtime_registry"
            continue
        }
        if ($file -match '^Tools/.*\.ps1$' -or $file -match '^Tools/.*\.psm1$') {
            if ($file -like "*validate_repo_hygiene.ps1") { Add-Unique $Tools "repo_hygiene" }
            elseif ($file -like "*validate_backend_capabilities.ps1") { Add-Unique $Tools "backend_capabilities" }
            elseif ($file -like "*validate_command_test_coverage.ps1") { Add-Unique $Tools "command_coverage" }
            elseif ($file -like "*generate_error_code_registry.ps1") { Add-Unique $Tools "error_registry" }
            elseif ($file -like "*generate_runtime_action_registry.ps1") { Add-Unique $Tools "runtime_registry" }
            elseif ($file -like "*validate_ir_contract.ps1") { Add-Unique $Tools "ir_contract" }
            elseif ($file -like "*validate_wrapper_cache_contract.ps1") { Add-Unique $Tools "wrapper_cache" }
            elseif ($file -like "*validate_dx12_readiness.ps1") { Add-Unique $Tools "dx12_readiness" }
            elseif ($file -like "*validate_m19a_runtime_loop_contract.ps1") { Add-Unique $Tools "m19a_runtime_loop" }
            elseif ($file -like "*validate_m19b_style_contract.ps1") { Add-Unique $Tools "m19b_style" }
            elseif ($file -like "*validate_m19c_ui_contract.ps1") { Add-Unique $Tools "m19c_ui" }
            elseif ($file -like "*validate_m19d_ui_layout_contract.ps1") { Add-Unique $Tools "m19d_layout" }
            elseif ($file -like "*validate_m19efgh_ui_final_contract.ps1") { Add-Unique $Tools "m19efgh_ui" }
            elseif ($file -like "*validate_backend_contract_docs.ps1") { Add-Unique $Tools "backend_docs" }
            elseif ($file -like "*validate_parser_split.ps1") { Add-Unique $Tools "parser_split" }
            elseif ($file -like "*validate_strict_ir.ps1") { Add-Unique $Tools "strict_ir" }
            elseif ($file -like "*validate_keyword_registry.ps1") { Add-Unique $Tools "keyword_registry" }
            elseif ($file -like "*validate_parser_statement_map.ps1") { Add-Unique $Tools "parser_statement_map" }
            elseif ($file -like "*validate_test_slice.ps1") { Add-Unique $Tools "test_slice_self" }
            else { Add-Unique $Tools "repo_hygiene" }
            continue
        }
        if ($file -eq ".gitignore" -or $file -eq ".gitattributes") {
            Add-Unique $Tools "repo_hygiene"
            continue
        }
        if ($file -match '^Backends/WindowsX64PE/Config/') {
            Add-Unique $Tools "backend_capabilities"
            Add-Unique $Tools "dx12_readiness"
            continue
        }
        if ($file -match '^(IR|Runtime|Backends/DX12|Docs)/') {
            Add-Unique $Tools "ir_contract"
            Add-Unique $Tools "dx12_readiness"
            Add-Unique $Tools "backend_docs"
            Add-Unique $Tools "m19a_runtime_loop"
            continue
        }
        if ($file -match '^Tools/M10GDriver/Frontend/Lexer\.cs$' -or $file -match '^Specs/Commands/') {
            Add-Unique $Tools "keyword_registry"
            Add-Unique $Tools "parser_statement_map"
            continue
        }
    }
}

if ($BuildDriver) {
    Write-Host "BUILD|dotnet publish arqc_m10g"
    Push-Location $RepoRoot
    try {
        dotnet publish ".\Tools\M10GDriver\ArqcM10G.csproj" -c Release -o ".\Tools\M10GDriver\publish"
        if ($LASTEXITCODE -ne 0) { Add-Check "BUILD_DRIVER" $false "dotnet publish failed"; Write-SummaryAndExit 1 }
        Copy-Item ".\Tools\M10GDriver\publish\arqc_m10g.exe" ".\Tools\arqc_m10g.exe" -Force
        Add-Check "BUILD_DRIVER" $true "arqc_m10g.exe updated"
    } finally {
        Pop-Location
    }
}

$Folder = Normalize-NameList $Folder
$Group = Normalize-NameList $Group
$Case = Normalize-NameList $Case
$Tool = Normalize-NameList $Tool

if ($List) {
    Write-Host "Command folders:"
    foreach ($f in Existing-CommandFolders) { Write-Host " - $f" }
    Write-Host ""
    Write-Host "Tool aliases:"
    foreach ($key in $ToolMap.Keys) {
        $path = Join-Path $RepoRoot $ToolMap[$key]
        $state = if (Test-Path $path) { "present" } else { "missing" }
        Write-Host " - $key -> $($ToolMap[$key]) [$state]"
    }
    Write-Host ""
    Write-Host "Groups: math, geometry, backend, m18a, m18b, m18fg, m18h, m18i, m18j, m19a, m19b, m19c, m19d, m19efgh, ui_final, refactor, tooling, core, flow, commands"
    exit 0
}

$selectedFolders = New-Object System.Collections.Generic.List[string]
$selectedTools = New-Object System.Collections.Generic.List[string]

foreach ($f in $Folder) { Add-Unique $selectedFolders $f }
foreach ($t in $Tool) { Add-Unique $selectedTools $t }
foreach ($g in $Group) {
    $expanded = Expand-Group $g
    foreach ($f in $expanded.Folders) { Add-Unique $selectedFolders $f }
    foreach ($t in $expanded.Tools) { Add-Unique $selectedTools $t }
}
if ($AllCommand) {
    foreach ($f in Existing-CommandFolders) { Add-Unique $selectedFolders $f }
}
if ($Changed) {
    Add-ChangedTargets $selectedFolders $selectedTools
}

if ($selectedFolders.Count -eq 0 -and $selectedTools.Count -eq 0) {
    Write-Host "No test slice selected. Examples:"
    Write-Host "  .\Tools\run_test_slice.ps1 -Folder geometry_math"
    Write-Host "  .\Tools\run_test_slice.ps1 -Folder procedural_coordinate_math -Case valid_coordinate"
    Write-Host "  .\Tools\run_test_slice.ps1 -Group math"
    Write-Host "  .\Tools\run_test_slice.ps1 -Tool repo_hygiene"
    Write-Host "  .\Tools\run_test_slice.ps1 -Changed"
    Write-Host "  .\Tools\run_test_slice.ps1 -List"
    exit 2
}

Write-Host "Selected command folders: $($selectedFolders -join ', ')"
Write-Host "Selected tools: $($selectedTools -join ', ')"
if ($Case.Count -gt 0) { Write-Host "Case filter: $($Case -join ', ')" }
Write-Host ""

foreach ($folderName in $selectedFolders) {
    Run-CommandFolder $folderName $Case
}
foreach ($toolAlias in $selectedTools) {
    Run-ToolCheck $toolAlias
}

$exitCode = if ($script:Failures.Count -eq 0) { 0 } else { 1 }
Write-SummaryAndExit $exitCode
