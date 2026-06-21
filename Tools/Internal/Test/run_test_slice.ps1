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
Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "Common\ArqenTooling.psm1") -Force

$RepoRoot = Get-ArqenRepoRoot -StartPath $PSScriptRoot
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
            if ([System.IO.Path]::GetExtension($Exe).Equals(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) {
                $psExe = (Get-Process -Id $PID).Path
                $scriptPath = if ([System.IO.Path]::IsPathRooted($Exe)) { $Exe } else { Join-Path $RepoRoot $Exe }
                $escapedScriptPath = $scriptPath.Replace("'", "''")
                $argText = ""
                foreach ($arg in $StageArgs) {
                    $argText += " '" + $arg.Replace("'", "''") + "'"
                }

                $command = "& '$escapedScriptPath'$argText; if (`$?) { exit 0 } else { exit 1 }"
                & $psExe -NoProfile -ExecutionPolicy Bypass -Command $command *> $null
                $exit = $LASTEXITCODE
                if ($null -eq $exit) {
                    $exit = if ($?) { 0 } else { 1 }
                }
                return [int]$exit
            }

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
        } elseif ($kind -eq "AST_CONTAINS") {
            $astPath = Join-Path $RepoRoot "Build\AST\$stem.ast"
            $ast = if (Test-Path $astPath) { Get-Content $astPath -Raw } else { "" }
            $ok = ($exit -eq $wantExit -and $ast.Contains($want))
            $note = if ($ok) { "contains=$want" } else { "exit=$exit expected=$wantExit ast=$([System.IO.Path]::GetFileName($astPath)) missing=$want" }
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
    "repo_hygiene" = "Tools\Validate\Core\validate_repo_hygiene.ps1"
    "hygiene" = "Tools\Validate\Core\validate_repo_hygiene.ps1"
    "backend_capabilities" = "Tools\Validate\Core\validate_backend_capabilities.ps1"
    "capabilities" = "Tools\Validate\Core\validate_backend_capabilities.ps1"
    "m33ab_runtime_stress" = "Tools\Validate\Runtime\validate_m33a_m33b_windows_x64_runtime_stress.ps1"
    "runtime_stress" = "Tools\Validate\Runtime\validate_m33a_m33b_windows_x64_runtime_stress.ps1"
    "m34a_runtime_if" = "Tools\Validate\Runtime\validate_m34a_runtime_if.ps1"
    "runtime_if" = "Tools\Validate\Runtime\validate_m34a_runtime_if.ps1"
    "m34bc_runtime_math_while" = "Tools\Validate\Runtime\validate_m34b_m34c_runtime_math_while.ps1"
    "runtime_math_while" = "Tools\Validate\Runtime\validate_m34b_m34c_runtime_math_while.ps1"
    "m34de_runtime_int_control" = "Tools\Validate\Runtime\validate_m34d_m34e_runtime_int_control.ps1"
    "runtime_int_control" = "Tools\Validate\Runtime\validate_m34d_m34e_runtime_int_control.ps1"
    "m35abc_runtime_state" = "Tools\Validate\Runtime\validate_m35a_m35b_m35c_runtime_state.ps1"
    "runtime_state" = "Tools\Validate\Runtime\validate_m35a_m35b_m35c_runtime_state.ps1"
    "m36abc_runtime_conditions" = "Tools\Validate\Runtime\validate_m36a_m36b_m36c_runtime_conditions.ps1"
    "runtime_conditions" = "Tools\Validate\Runtime\validate_m36a_m36b_m36c_runtime_conditions.ps1"
    "m37abc_runtime_string_data" = "Tools\Validate\Runtime\validate_m37a_m37b_m37c_runtime_string_data.ps1"
    "runtime_string_data" = "Tools\Validate\Runtime\validate_m37a_m37b_m37c_runtime_string_data.ps1"
    "m38abc_function_runtime_audit" = "Tools\Validate\Runtime\validate_m38a_m38b_m38c_function_runtime_audit.ps1"
    "function_runtime_audit" = "Tools\Validate\Runtime\validate_m38a_m38b_m38c_function_runtime_audit.ps1"
    "m39abc_function_ir_runtime" = "Tools\Validate\Runtime\validate_m39a_m39b_m39c_function_ir_runtime.ps1"
    "function_ir_runtime" = "Tools\Validate\Runtime\validate_m39a_m39b_m39c_function_ir_runtime.ps1"
    "m40abc_function_return_void" = "Tools\Validate\Runtime\validate_m40a_m40b_m40c_function_return_void.ps1"
    "function_return_void" = "Tools\Validate\Runtime\validate_m40a_m40b_m40c_function_return_void.ps1"
    "m41abc_function_return_values" = "Tools\Validate\Runtime\validate_m41a_m41b_m41c_function_return_values.ps1"
    "function_return_values" = "Tools\Validate\Runtime\validate_m41a_m41b_m41c_function_return_values.ps1"
    "m42abc_function_parameters" = "Tools\Validate\Runtime\validate_m42a_m42b_m42c_function_parameters.ps1"
    "function_parameters" = "Tools\Validate\Runtime\validate_m42a_m42b_m42c_function_parameters.ps1"
    "m43abc_function_local_scope" = "Tools\Validate\Runtime\validate_m43a_m43b_m43c_function_local_scope.ps1"
    "function_local_scope" = "Tools\Validate\Runtime\validate_m43a_m43b_m43c_function_local_scope.ps1"
    "m44abc_function_call_graph" = "Tools\Validate\Runtime\validate_m44a_m44b_m44c_function_call_graph.ps1"
    "function_call_graph" = "Tools\Validate\Runtime\validate_m44a_m44b_m44c_function_call_graph.ps1"
    "m45m46_runtime_int_arrays" = "Tools\Validate\Runtime\validate_m45_m46_runtime_int_arrays.ps1"
    "runtime_int_arrays" = "Tools\Validate\Runtime\validate_m45_m46_runtime_int_arrays.ps1"
    "m47m48_runtime_bool_string_arrays" = "Tools\Validate\Runtime\validate_m47_m48_runtime_bool_string_arrays.ps1"
    "runtime_bool_string_arrays" = "Tools\Validate\Runtime\validate_m47_m48_runtime_bool_string_arrays.ps1"
    "m49m50_runtime_array_scope_params" = "Tools\Validate\Runtime\validate_m49_m50_runtime_array_scope_params.ps1"
    "runtime_array_scope_params" = "Tools\Validate\Runtime\validate_m49_m50_runtime_array_scope_params.ps1"
    "m51m52_array_utils_records" = "Tools\Validate\Runtime\validate_m51_m52_array_utils_records.ps1"
    "array_utils_records" = "Tools\Validate\Runtime\validate_m51_m52_array_utils_records.ps1"
    "m53m54_record_scope_arrays" = "Tools\Validate\Runtime\validate_m53_m54_record_scope_arrays.ps1"
    "record_scope_arrays" = "Tools\Validate\Runtime\validate_m53_m54_record_scope_arrays.ps1"
    "m55m56_record_utils_enums" = "Tools\Validate\Runtime\validate_m55_m56_record_utils_enums.ps1"
    "record_utils_enums" = "Tools\Validate\Runtime\validate_m55_m56_record_utils_enums.ps1"
    "m57m58_runtime_switch" = "Tools\Validate\Runtime\validate_m57_m58_runtime_switch.ps1"
    "runtime_switch" = "Tools\Validate\Runtime\validate_m57_m58_runtime_switch.ps1"
    "m59m60_enum_integration" = "Tools\Validate\Runtime\validate_m59_m60_enum_integration.ps1"
    "enum_integration" = "Tools\Validate\Runtime\validate_m59_m60_enum_integration.ps1"
    "m61m62_enum_scope_params" = "Tools\Validate\Runtime\validate_m61_m62_enum_scope_params.ps1"
    "enum_scope_params" = "Tools\Validate\Runtime\validate_m61_m62_enum_scope_params.ps1"
    "runtime_action_catalog" = "Tools\Validate\Core\validate_runtime_action_catalog.ps1"
    "command_coverage" = "Tools\Validate\Core\validate_command_test_coverage.ps1"
    "coverage" = "Tools\Validate\Core\validate_command_test_coverage.ps1"
    "error_registry" = "Tools\Generate\generate_error_code_registry.ps1"
    "errors" = "Tools\Generate\generate_error_code_registry.ps1"
    "runtime_registry" = "Tools\Generate\generate_runtime_action_registry.ps1"
    "runtime" = "Tools\Generate\generate_runtime_action_registry.ps1"
    "ir_contract" = "Tools\Validate\Core\validate_ir_contract.ps1"
    "ir" = "Tools\Validate\Core\validate_ir_contract.ps1"
    "wrapper_cache" = "Tools\Validate\Core\validate_wrapper_cache_contract.ps1"
    "cache" = "Tools\Validate\Core\validate_wrapper_cache_contract.ps1"
    "tool_surface" = "Tools\Validate\Core\validate_tool_surface.ps1"
    "tools" = "Tools\Validate\Core\validate_tool_surface.ps1"
    "dx12_readiness" = "Tools\Validate\DX12\validate_dx12_readiness.ps1"
    "dx12" = "Tools\Validate\DX12\validate_dx12_readiness.ps1"
    "m20a_dx12" = "Tools\Validate\DX12\validate_m20a_dx12_contract.ps1"
    "dx12_bridge" = "Tools\Validate\DX12\validate_m20a_dx12_contract.ps1"
    "m20b_dx12" = "Tools\Validate\DX12\validate_m20b_dx12_syntax_contract.ps1"
    "dx12_syntax" = "Tools\Validate\DX12\validate_m20b_dx12_syntax_contract.ps1"
    "m20c_dx12" = "Tools\Validate\DX12\validate_m20c_dx12_style_bridge_contract.ps1"
    "dx12_style_bridge" = "Tools\Validate\DX12\validate_m20c_dx12_style_bridge_contract.ps1"
    "m20d_dx12" = "Tools\Validate\DX12\validate_m20d_dx12_semantic_contract.ps1"
    "dx12_semantics" = "Tools\Validate\DX12\validate_m20d_dx12_semantic_contract.ps1"
    "m20e0_dx12" = "Tools\Validate\DX12\validate_m20e0_dx12_clear_readiness.ps1"
    "dx12_clear_readiness" = "Tools\Validate\DX12\validate_m20e0_dx12_clear_readiness.ps1"
    "m20e1_dx12" = "Tools\Validate\DX12\validate_m20e1_dx12_lowering_contract.ps1"
    "dx12_clear_lowering" = "Tools\Validate\DX12\validate_m20e1_dx12_lowering_contract.ps1"
    "m20f_dx12" = "Tools\Validate\DX12\validate_m20f_dx12_clear_smoke_contract.ps1"
    "dx12_clear_smoke" = "Tools\Validate\DX12\validate_m20f_dx12_clear_smoke_contract.ps1"
    "m20g_dx12" = "Tools\Validate\DX12\validate_m20g_dx12_frame_syntax_contract.ps1"
    "dx12_frame_syntax" = "Tools\Validate\DX12\validate_m20g_dx12_frame_syntax_contract.ps1"
    "m20h_dx12" = "Tools\Validate\DX12\validate_m20h_dx12_frame_lowering_contract.ps1"
    "dx12_frame_lowering" = "Tools\Validate\DX12\validate_m20h_dx12_frame_lowering_contract.ps1"
    "m20i_dx12" = "Tools\Validate\DX12\validate_m20i_dx12_native_smoke_polish_contract.ps1"
    "dx12_native_smoke" = "Tools\Validate\DX12\validate_m20i_dx12_native_smoke_polish_contract.ps1"
    "m21a_dx12" = "Tools\Validate\DX12\validate_m21a_shader_pipeline_bible.ps1"
    "dx12_shader_pipeline_bible" = "Tools\Validate\DX12\validate_m21a_shader_pipeline_bible.ps1"
    "m21b_dx12" = "Tools\Validate\DX12\validate_m21b_shader_pipeline_metadata.ps1"
    "dx12_shader_pipeline" = "Tools\Validate\DX12\validate_m21b_shader_pipeline_metadata.ps1"
    "m21c_dx12" = "Tools\Validate\DX12\validate_m21c_vertex_draw_metadata.ps1"
    "dx12_vertex_draw" = "Tools\Validate\DX12\validate_m21c_vertex_draw_metadata.ps1"
    "m21d_dx12" = "Tools\Validate\DX12\validate_m21d_dx12_triangle_smoke.ps1"
    "dx12_triangle_smoke" = "Tools\Validate\DX12\validate_m21d_dx12_triangle_smoke.ps1"
    "m21e_dx12" = "Tools\Validate\DX12\validate_m21e_dx12_standalone_runtime.ps1"
    "dx12_standalone_runtime" = "Tools\Validate\DX12\validate_m21e_dx12_standalone_runtime.ps1"
    "m21f_dx12" = "Tools\Validate\DX12\validate_m21f_dx12_frame_loop.ps1"
    "dx12_frame_loop" = "Tools\Validate\DX12\validate_m21f_dx12_frame_loop.ps1"
    "m21g_dx12" = "Tools\Validate\DX12\validate_m21g_constant_buffer_metadata.ps1"
    "dx12_constant_buffer" = "Tools\Validate\DX12\validate_m21g_constant_buffer_metadata.ps1"
    "m21h_dx12" = "Tools\Validate\DX12\validate_m21h_dx12_color_animation.ps1"
    "dx12_color_animation" = "Tools\Validate\DX12\validate_m21h_dx12_color_animation.ps1"
    "m21i_dx12" = "Tools\Validate\DX12\validate_m21i_dx12_color_animation_smoke_polish.ps1"
    "m21j_dx12" = "Tools\Validate\DX12\validate_m21j_dx12_color_animation_metadata_hardening.ps1"
    "m22_dx12" = "Tools\Validate\DX12\validate_m22_dx12_mini_scene_contract.ps1"
    "m19a_runtime_loop" = "Tools\Validate\DX12\validate_m19a_runtime_loop_contract.ps1"
    "runtime_loop" = "Tools\Validate\DX12\validate_m19a_runtime_loop_contract.ps1"
    "m19b_style" = "Tools\Validate\DX12\validate_m19b_style_contract.ps1"
    "style_contract" = "Tools\Validate\DX12\validate_m19b_style_contract.ps1"
    "m19c_ui" = "Tools\Validate\DX12\validate_m19c_ui_contract.ps1"
    "ui_contract" = "Tools\Validate\DX12\validate_m19c_ui_contract.ps1"
    "m19d_layout" = "Tools\Validate\DX12\validate_m19d_ui_layout_contract.ps1"
    "ui_layout_contract" = "Tools\Validate\DX12\validate_m19d_ui_layout_contract.ps1"
    "m19efgh_ui" = "Tools\Validate\DX12\validate_m19efgh_ui_final_contract.ps1"
    "ui_final_contract" = "Tools\Validate\DX12\validate_m19efgh_ui_final_contract.ps1"
    "backend_docs" = "Tools\Validate\Core\validate_backend_contract_docs.ps1"
    "docs" = "Tools\Validate\Core\validate_backend_contract_docs.ps1"
    "parser_split" = "Tools\Validate\Core\validate_parser_split.ps1"
    "parser" = "Tools\Validate\Core\validate_parser_split.ps1"
    "strict_ir" = "Tools\Validate\Core\validate_strict_ir.ps1"
    "keyword_registry" = "Tools\Validate\Core\validate_keyword_registry.ps1"
    "keywords" = "Tools\Validate\Core\validate_keyword_registry.ps1"
    "parser_statement_map" = "Tools\Validate\Core\validate_parser_statement_map.ps1"
    "statement_map" = "Tools\Validate\Core\validate_parser_statement_map.ps1"
    "test_slice_self" = "Tools\Validate\Core\validate_test_slice.ps1"
    "m23_dx12" = "Tools\Validate\DX12\validate_m23_dx12_scene_objects.ps1"
    "dx12_scene_objects" = "Tools\Validate\DX12\validate_m23_dx12_scene_objects.ps1"
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
    return @(
        Get-ChildItem $CommandRoot -Directory |
            Where-Object { $_.Name -ne "misc" -and (Test-Path (Join-Path $_.FullName "expected.txt")) } |
            Sort-Object Name |
            ForEach-Object { $_.Name }
    )
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
            foreach ($t in @("backend_capabilities","backend_docs","ir_contract","runtime_stress")) { Add-Unique $tools $t }
        }
        "m33ab" {
            foreach ($t in @("runtime_stress","backend_capabilities","ir_contract")) { Add-Unique $tools $t }
        }
        "m34a" {
            foreach ($t in @("runtime_if")) { Add-Unique $tools $t }
        }
        "m34bc" {
            foreach ($t in @("runtime_if","runtime_math_while")) { Add-Unique $tools $t }
        }
        "m34b" {
            foreach ($t in @("runtime_math_while")) { Add-Unique $tools $t }
        }
        "m34c" {
            foreach ($t in @("runtime_math_while")) { Add-Unique $tools $t }
        }
        "m34de" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control")) { Add-Unique $tools $t }
        }
        "m34d" {
            foreach ($t in @("runtime_int_control")) { Add-Unique $tools $t }
        }
        "m34e" {
            foreach ($t in @("runtime_int_control")) { Add-Unique $tools $t }
        }
        "m35abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state")) { Add-Unique $tools $t }
        }
        "m35a" {
            foreach ($t in @("runtime_state")) { Add-Unique $tools $t }
        }
        "m35b" {
            foreach ($t in @("runtime_state")) { Add-Unique $tools $t }
        }
        "m35c" {
            foreach ($t in @("runtime_state")) { Add-Unique $tools $t }
        }
        "m36abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions")) { Add-Unique $tools $t }
        }
        "m36a" {
            foreach ($t in @("runtime_conditions")) { Add-Unique $tools $t }
        }
        "m36b" {
            foreach ($t in @("runtime_conditions")) { Add-Unique $tools $t }
        }
        "m36c" {
            foreach ($t in @("runtime_conditions")) { Add-Unique $tools $t }
        }
        "m37abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data")) { Add-Unique $tools $t }
        }
        "m37a" {
            foreach ($t in @("runtime_string_data")) { Add-Unique $tools $t }
        }
        "m37b" {
            foreach ($t in @("runtime_string_data")) { Add-Unique $tools $t }
        }
        "m37c" {
            foreach ($t in @("runtime_string_data")) { Add-Unique $tools $t }
        }
        "m38abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m38a" {
            foreach ($t in @("function_runtime_audit")) { Add-Unique $tools $t }
        }
        "m38b" {
            foreach ($t in @("function_runtime_audit")) { Add-Unique $tools $t }
        }
        "m38c" {
            foreach ($t in @("function_runtime_audit","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m39abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m39a" {
            foreach ($t in @("function_ir_runtime")) { Add-Unique $tools $t }
        }
        "m39b" {
            foreach ($t in @("function_ir_runtime")) { Add-Unique $tools $t }
        }
        "m39c" {
            foreach ($t in @("function_ir_runtime","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m40abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m40a" {
            foreach ($t in @("function_return_void")) { Add-Unique $tools $t }
        }
        "m40b" {
            foreach ($t in @("function_return_void")) { Add-Unique $tools $t }
        }
        "m40c" {
            foreach ($t in @("function_return_void","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m41abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","function_return_values","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m41a" {
            foreach ($t in @("function_return_values")) { Add-Unique $tools $t }
        }
        "m41b" {
            foreach ($t in @("function_return_values")) { Add-Unique $tools $t }
        }
        "m41c" {
            foreach ($t in @("function_return_values","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m42abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","function_return_values","function_parameters","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m42a" {
            foreach ($t in @("function_parameters")) { Add-Unique $tools $t }
        }
        "m42b" {
            foreach ($t in @("function_parameters")) { Add-Unique $tools $t }
        }
        "m42c" {
            foreach ($t in @("function_parameters","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m43abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","function_return_values","function_parameters","function_local_scope","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m43a" {
            foreach ($t in @("function_local_scope")) { Add-Unique $tools $t }
        }
        "m43b" {
            foreach ($t in @("function_local_scope")) { Add-Unique $tools $t }
        }
        "m43c" {
            foreach ($t in @("function_local_scope","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m44abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","function_return_values","function_parameters","function_local_scope","function_call_graph","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m44a" {
            foreach ($t in @("function_call_graph")) { Add-Unique $tools $t }
        }
        "m44b" {
            foreach ($t in @("function_call_graph")) { Add-Unique $tools $t }
        }
        "m44c" {
            foreach ($t in @("function_call_graph","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m45m46" {
            foreach ($t in @("runtime_int_arrays","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m45" {
            foreach ($t in @("runtime_int_arrays")) { Add-Unique $tools $t }
        }
        "m46" {
            foreach ($t in @("runtime_int_arrays","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m45m46abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","function_return_values","function_parameters","function_local_scope","function_call_graph","runtime_int_arrays","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m47m48" {
            foreach ($t in @("runtime_bool_string_arrays","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m47" {
            foreach ($t in @("runtime_bool_string_arrays")) { Add-Unique $tools $t }
        }
        "m48" {
            foreach ($t in @("runtime_bool_string_arrays","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m47m48abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","function_return_values","function_parameters","function_local_scope","function_call_graph","runtime_int_arrays","runtime_bool_string_arrays","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m49m50" {
            foreach ($t in @("runtime_array_scope_params","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m49" {
            foreach ($t in @("runtime_array_scope_params")) { Add-Unique $tools $t }
        }
        "m50" {
            foreach ($t in @("runtime_array_scope_params","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m49m50abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","function_return_values","function_parameters","function_local_scope","function_call_graph","runtime_int_arrays","runtime_bool_string_arrays","runtime_array_scope_params","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m51m52" {
            foreach ($t in @("array_utils_records","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m51" {
            foreach ($t in @("array_utils_records")) { Add-Unique $tools $t }
        }
        "m52" {
            foreach ($t in @("array_utils_records","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m51m52abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","function_return_values","function_parameters","function_local_scope","function_call_graph","runtime_int_arrays","runtime_bool_string_arrays","runtime_array_scope_params","array_utils_records","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m53m54" {
            foreach ($t in @("record_scope_arrays","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m53" {
            foreach ($t in @("record_scope_arrays")) { Add-Unique $tools $t }
        }
        "m54" {
            foreach ($t in @("record_scope_arrays","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m53m54abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","function_return_values","function_parameters","function_local_scope","function_call_graph","runtime_int_arrays","runtime_bool_string_arrays","runtime_array_scope_params","array_utils_records","record_scope_arrays","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m55m56" {
            foreach ($t in @("record_utils_enums","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m55" {
            foreach ($t in @("record_utils_enums")) { Add-Unique $tools $t }
        }
        "m56" {
            foreach ($t in @("record_utils_enums","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m55m56abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","function_return_values","function_parameters","function_local_scope","function_call_graph","runtime_int_arrays","runtime_bool_string_arrays","runtime_array_scope_params","array_utils_records","record_scope_arrays","record_utils_enums","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m57m58" {
            foreach ($t in @("runtime_switch","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m57" {
            foreach ($t in @("runtime_switch")) { Add-Unique $tools $t }
        }
        "m58" {
            foreach ($t in @("runtime_switch","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m57m58abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","function_return_values","function_parameters","function_local_scope","function_call_graph","runtime_int_arrays","runtime_bool_string_arrays","runtime_array_scope_params","array_utils_records","record_scope_arrays","record_utils_enums","runtime_switch","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m59m60" {
            foreach ($t in @("enum_integration","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m59" {
            foreach ($t in @("enum_integration")) { Add-Unique $tools $t }
        }
        "m60" {
            foreach ($t in @("enum_integration","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m59m60abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","function_return_values","function_parameters","function_local_scope","function_call_graph","runtime_int_arrays","runtime_bool_string_arrays","runtime_array_scope_params","array_utils_records","record_scope_arrays","record_utils_enums","runtime_switch","enum_integration","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m61m62" {
            foreach ($t in @("enum_scope_params","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m61" {
            foreach ($t in @("enum_scope_params")) { Add-Unique $tools $t }
        }
        "m62" {
            foreach ($t in @("enum_scope_params","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "m61m62abc" {
            foreach ($t in @("runtime_if","runtime_math_while","runtime_int_control","runtime_state","runtime_conditions","runtime_string_data","function_runtime_audit","function_ir_runtime","function_return_void","function_return_values","function_parameters","function_local_scope","function_call_graph","runtime_int_arrays","runtime_bool_string_arrays","runtime_array_scope_params","array_utils_records","record_scope_arrays","record_utils_enums","runtime_switch","enum_integration","enum_scope_params","runtime_action_catalog")) { Add-Unique $tools $t }
        }
        "lowlevel" {
            foreach ($f in @("file_io","command_args","print","show_message","exit")) { Add-Unique $folders $f }
            foreach ($t in @("runtime_stress","backend_capabilities","ir_contract")) { Add-Unique $tools $t }
        }
        "m18a" {
            foreach ($t in @("repo_hygiene","backend_capabilities","command_coverage","error_registry")) { Add-Unique $tools $t }
        }
        "m18b" {
            foreach ($t in @("runtime_registry","ir_contract","wrapper_cache","tool_surface","dx12_readiness","backend_docs")) { Add-Unique $tools $t }
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
        "m20a" {
            foreach ($t in @("m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry")) { Add-Unique $tools $t }
        }
        "m20b" {
            foreach ($f in @("dx12")) { Add-Unique $folders $f }
            foreach ($t in @("m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m20c" {
            foreach ($f in @("dx12","style")) { Add-Unique $folders $f }
            foreach ($t in @("m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m20d" {
            foreach ($f in @("dx12","style","ui_objects","window","canonical_define")) { Add-Unique $folders $f }
            foreach ($t in @("m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m20e0" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m20e1" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m20f" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m20g" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m20g_dx12","m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m20h" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m20h_dx12","m20g_dx12","m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m20i" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m20i_dx12","m20h_dx12","m20g_dx12","m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m21a" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m21a_dx12","m20i_dx12","m20h_dx12","m20g_dx12","m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m21b" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m21b_dx12","m21a_dx12","m20i_dx12","m20h_dx12","m20g_dx12","m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m21c" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m21c_dx12","m21b_dx12","m21a_dx12","m20i_dx12","m20h_dx12","m20g_dx12","m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m21d" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m21d_dx12","m21c_dx12","m21b_dx12","m21a_dx12","m20i_dx12","m20h_dx12","m20g_dx12","m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m21e" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m21e_dx12","m21d_dx12","m21c_dx12","m21b_dx12","m21a_dx12","m20i_dx12","m20h_dx12","m20g_dx12","m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m21f" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m21f_dx12","m21e_dx12","m21d_dx12","m21c_dx12","m21b_dx12","m21a_dx12","m20i_dx12","m20h_dx12","m20g_dx12","m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m21g" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m21g_dx12","m21f_dx12","m21e_dx12","m21d_dx12","m21c_dx12","m21b_dx12","m21a_dx12","m20i_dx12","m20h_dx12","m20g_dx12","m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m21h" {
            foreach ($f in @("dx12","style","window")) { Add-Unique $folders $f }
            foreach ($t in @("m21h_dx12","m21g_dx12","m21f_dx12","m21e_dx12","m21d_dx12","m21c_dx12","m21b_dx12","m21a_dx12","m20i_dx12","m20h_dx12","m20g_dx12","m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "dx12_m20" {
            foreach ($f in @("dx12")) { Add-Unique $folders $f }
            foreach ($t in @("m20i_dx12","m20h_dx12","m20g_dx12","m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "dx12_m21" {
            foreach ($f in @("dx12")) { Add-Unique $folders $f }
            foreach ($t in @("m21h_dx12","m21g_dx12","m21f_dx12","m21e_dx12","m21d_dx12","m21c_dx12","m21b_dx12","m21a_dx12","m20i_dx12","m20h_dx12","m20g_dx12","m20f_dx12","m20e1_dx12","m20e0_dx12","m20d_dx12","m20c_dx12","m20b_dx12","m20a_dx12","dx12_readiness","backend_docs","ir_contract","runtime_registry","keyword_registry","parser_statement_map","command_coverage")) { Add-Unique $tools $t }
        }
        "m23" {
            foreach ($f in @("dx12")) { Add-Unique $folders $f }
            foreach ($t in @("m23_dx12","m21h_dx12","m21i_dx12","m21j_dx12","m22_dx12")) { Add-Unique $tools $t }
        }
        "m18fg" {
            foreach ($t in @("parser_split","ir_contract","runtime_registry")) { Add-Unique $tools $t }
        }
        "refactor" {
            foreach ($t in @("parser_split","ir_contract","runtime_registry","backend_docs")) { Add-Unique $tools $t }
        }
        "tooling" {
            foreach ($t in @("repo_hygiene","backend_capabilities","command_coverage","error_registry","runtime_registry","ir_contract","wrapper_cache","tool_surface","dx12_readiness","m20a_dx12","m20b_dx12","m20c_dx12","m20d_dx12","m20e0_dx12","m20e1_dx12","m20f_dx12","m20g_dx12","m20h_dx12","m20i_dx12","m21a_dx12","m21b_dx12","m21c_dx12","m21d_dx12","m21e_dx12","m21f_dx12","m21g_dx12","m21h_dx12","m19a_runtime_loop","m19b_style","m19c_ui","m19d_layout","m19efgh_ui","backend_docs","parser_split","strict_ir","keyword_registry","parser_statement_map","test_slice_self")) { Add-Unique $tools $t }
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
        if ($file -match '^Tests/DX12Lowering/') {
            Add-Unique $Tools "m20e1_dx12"
            continue
        }
        if ($file -match '^Tests/CommandTests/misc/([^/]+)\.command\.txt$') {
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
            elseif ($file -like "*validate_m20a_dx12_contract.ps1") { Add-Unique $Tools "m20a_dx12" }
            elseif ($file -like "*validate_m20b_dx12_syntax_contract.ps1") { Add-Unique $Tools "m20b_dx12" }
            elseif ($file -like "*validate_m20c_dx12_style_bridge_contract.ps1") { Add-Unique $Tools "m20c_dx12" }
            elseif ($file -like "*validate_m20d_dx12_semantic_contract.ps1") { Add-Unique $Tools "m20d_dx12" }
            elseif ($file -like "*validate_m20e0_dx12_clear_readiness.ps1") { Add-Unique $Tools "m20e0_dx12" }
            elseif ($file -like "*validate_m20e1_dx12_lowering_contract.ps1") { Add-Unique $Tools "m20e1_dx12" }
            elseif ($file -like "*lower_m20e1_dx12_clear_from_ir.ps1") { Add-Unique $Tools "m20e1_dx12"; Add-Unique $Tools "m20h_dx12"; Add-Unique $Tools "m20i_dx12"; Add-Unique $Tools "m21d_dx12"; Add-Unique $Tools "m21e_dx12"; Add-Unique $Tools "m21f_dx12"; Add-Unique $Tools "m21g_dx12"; Add-Unique $Tools "m21h_dx12" }
            elseif ($file -like "*validate_m20f_dx12_clear_smoke_contract.ps1") { Add-Unique $Tools "m20f_dx12" }
            elseif ($file -like "*build_m20f_dx12_clear_smoke.ps1") { Add-Unique $Tools "m20f_dx12" }
            elseif ($file -like "*validate_m20g_dx12_frame_syntax_contract.ps1") { Add-Unique $Tools "m20g_dx12" }
            elseif ($file -like "*validate_m20h_dx12_frame_lowering_contract.ps1") { Add-Unique $Tools "m20h_dx12" }
            elseif ($file -like "*validate_m20i_dx12_native_smoke_polish_contract.ps1") { Add-Unique $Tools "m20i_dx12" }
            elseif ($file -like "*validate_m21a_shader_pipeline_bible.ps1") { Add-Unique $Tools "m21a_dx12" }
            elseif ($file -like "*validate_m21b_shader_pipeline_metadata.ps1") { Add-Unique $Tools "m21b_dx12" }
            elseif ($file -like "*validate_m21c_vertex_draw_metadata.ps1") { Add-Unique $Tools "m21c_dx12" }
            elseif ($file -like "*validate_m21d_dx12_triangle_smoke.ps1") { Add-Unique $Tools "m21d_dx12" }
            elseif ($file -like "*validate_m21e_dx12_standalone_runtime.ps1") { Add-Unique $Tools "m21e_dx12" }
            elseif ($file -like "*validate_m21f_dx12_frame_loop.ps1") { Add-Unique $Tools "m21f_dx12" }
            elseif ($file -like "*validate_m21g_constant_buffer_metadata.ps1") { Add-Unique $Tools "m21g_dx12" }
            elseif ($file -like "*validate_m21h_dx12_color_animation.ps1") { Add-Unique $Tools "m21h_dx12" }
            elseif ($file -like "*build_m21d_dx12_triangle_smoke.ps1") { Add-Unique $Tools "m21d_dx12"; Add-Unique $Tools "m21e_dx12"; Add-Unique $Tools "m21f_dx12" }
            elseif ($file -like "*build_m21f_dx12_triangle_loop_smoke.ps1") { Add-Unique $Tools "m21f_dx12" }
            elseif ($file -like "*build_m21h_dx12_animated_triangle_smoke.ps1") { Add-Unique $Tools "m21h_dx12" }
            elseif ($file -like "*build_m20i_dx12_frame_clear_smoke.ps1") { Add-Unique $Tools "m20i_dx12" }
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
        if ($file -match '^Docs/Reference/Backends/WindowsX64PE_Config/') {
            Add-Unique $Tools "backend_capabilities"
            Add-Unique $Tools "dx12_readiness"
            continue
        }
        if ($file -match '^(IR|Runtime|Backends/DX12|Docs)/') {
            Add-Unique $Tools "ir_contract"
            Add-Unique $Tools "dx12_readiness"
            Add-Unique $Tools "m20a_dx12"
            Add-Unique $Tools "m20b_dx12"
            Add-Unique $Tools "m20c_dx12"
            Add-Unique $Tools "m20d_dx12"
            Add-Unique $Tools "m20e0_dx12"
            Add-Unique $Tools "m20e1_dx12"
            Add-Unique $Tools "m20f_dx12"
            Add-Unique $Tools "m20g_dx12"
            Add-Unique $Tools "m20h_dx12"
            Add-Unique $Tools "m20i_dx12"
            Add-Unique $Tools "m21a_dx12"
            Add-Unique $Tools "m21b_dx12"
            Add-Unique $Tools "m21c_dx12"
            Add-Unique $Tools "m21d_dx12"
            Add-Unique $Tools "m21e_dx12"
            Add-Unique $Tools "m21f_dx12"
            Add-Unique $Tools "backend_docs"
            Add-Unique $Tools "m19a_runtime_loop"
            continue
        }
        if ($file -match '^Tools/M10GDriver/Frontend/Lexer\.cs$' -or $file -match '^Tests/CommandTests/misc/') {
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
    Write-Host "Groups: math, geometry, backend, lowlevel, m33ab, m34a, m34bc, m34b, m34c, m34de, m34d, m34e, m35abc, m36abc, m37abc, m37a, m37b, m37c, m38abc, m38a, m38b, m38c, m39abc, m39a, m39b, m39c, m40abc, m40a, m40b, m40c, m41abc, m42abc, m43abc, m44abc, m45m46, m45, m46, m47m48, m47, m48, m18a, m18b, m18fg, m18h, m18i, m18j, m19a, m19b, m19c, m19d, m19efgh, ui_final, m20a, m20b, m20c, m20d, m20e0, m20e1, m20f, m20g, m20h, m20i, dx12_m20, refactor, tooling, core, flow, commands"
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
    Write-Host "  .\Tools\test.ps1 -Folder geometry_math"
    Write-Host "  .\Tools\test.ps1 -Folder procedural_coordinate_math -Case valid_coordinate"
    Write-Host "  .\Tools\test.ps1 -Group math"
    Write-Host "  .\Tools\test.ps1 -Tool repo_hygiene"
    Write-Host "  .\Tools\test.ps1 -Changed"
    Write-Host "  .\Tools\test.ps1 -List"
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
