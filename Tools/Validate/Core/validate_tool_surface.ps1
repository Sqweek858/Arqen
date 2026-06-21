$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "Common\ArqenTooling.psm1") -Force

$RepoRoot = Get-ArqenRepoRoot -StartPath $PSScriptRoot
$Generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $Generated | Out-Null
$OutPath = Join-Path $Generated "tool_surface_validation.txt"
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Add-Result {
    param([string]$Status,[string]$Name,[string]$Detail = "")
    if ($Status -eq "FAIL") { $script:failed = $true }
    $line = if ([string]::IsNullOrWhiteSpace($Detail)) { "$Status|$Name" } else { "$Status|$Name|$Detail" }
    $lines.Add($line) | Out-Null
    Write-Host $line
}

$required = @(
    "run_me.ps1",
    "Tools\arqc.ps1",
    "Tools\build.ps1",
    "Tools\clean.ps1",
    "Tools\generate.ps1",
    "Tools\validate.ps1",
    "Tools\test.ps1",
    "Tools\run_test_slice.ps1",
    "Tools\verify_repo.ps1",
    "Tools\verify_expected_ir.ps1",
    "Tools\Internal\Test\run_test_slice.ps1",
    "Tools\Internal\Test\run_everything.ps1",
    "Tools\Validate\Core\validate_tool_surface.ps1",
    "Tools\Validate\Core\validate_trash.ps1"
)

foreach ($rel in $required) {
    $path = Join-Path $RepoRoot $rel
    Add-Result ($(if (Test-Path $path) { "PASS" } else { "FAIL" })) "tool_required_$($rel -replace '[^A-Za-z0-9]+','_')" $rel
}

$toolsRoot = Join-Path $RepoRoot "Tools"
$ps1Files = @(Get-ChildItem $toolsRoot -Recurse -File -Filter "*.ps1" | Sort-Object FullName)
$runMePath = Join-Path $RepoRoot "run_me.ps1"
if (Test-Path $runMePath) { $ps1Files = @($ps1Files + (Get-Item $runMePath)) | Sort-Object FullName }
Add-Result "PASS" "tool_ps1_count" "count=$($ps1Files.Count)"

$parseFailures = 0
foreach ($file in $ps1Files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        $parseFailures += 1
        Add-Result "FAIL" "tool_parse_$($file.BaseName)" "$(ConvertTo-ArqenRelativePath $file.FullName $RepoRoot): $($errors[0].Message)"
    }
}
if ($parseFailures -eq 0) { Add-Result "PASS" "tool_parse_all" "all Tools/*.ps1 plus root run_me.ps1 parse" }

$legacyPs1 = @(Get-ChildItem (Join-Path $RepoRoot "Tools\Legacy") -File -Filter "*.ps1" -ErrorAction SilentlyContinue)
if ($legacyPs1.Count -eq 0) { Add-Result "PASS" "no_legacy_ps1" "Tools\Legacy contains no active scripts" }
else { foreach ($f in $legacyPs1) { Add-Result "FAIL" "legacy_ps1_active" (ConvertTo-ArqenRelativePath $f.FullName $RepoRoot) } }

$publicTestPs1 = @(Get-ChildItem (Join-Path $RepoRoot "Tools\Test") -File -Filter "*.ps1" -ErrorAction SilentlyContinue)
if ($publicTestPs1.Count -eq 0) { Add-Result "PASS" "no_public_test_engine_ps1" "Tools\Test contains no public engine scripts; use Tools\test.ps1" }
else { foreach ($f in $publicTestPs1) { Add-Result "FAIL" "public_test_engine_script" (ConvertTo-ArqenRelativePath $f.FullName $RepoRoot) } }

$forbidden = @(
    "Tools\Legacy\arqc_m10jk.ps1",
    "Experiments\M10_SimpleExpressions\template_messagebox_m8.exe",
    "Tools\Test\run_test_slice.ps1",
    "Tools/Test/run_test_slice.ps1",
    "Tools\Test\run_everything.ps1",
    "Tools/Test/run_everything.ps1",
    "Tools\Test\run_all_tests.ps1",
    "Tools/Test/run_all_tests.ps1"
)
$staleLiteralPolicyScripts = @(
    (Join-Path $RepoRoot "Tools\verify_repo.ps1"),
    (Join-Path $RepoRoot "Tools\Validate\Core\validate_tool_surface.ps1"),
    (Join-Path $RepoRoot "Tools\Validate\Core\validate_trash.ps1")
) | ForEach-Object { [System.IO.Path]::GetFullPath($_) }

foreach ($needle in $forbidden) {
    $hits = @($ps1Files | Where-Object {
        $full = [System.IO.Path]::GetFullPath($_.FullName)
        -not ($staleLiteralPolicyScripts -contains $full) -and (Get-Content $_.FullName -Raw).Contains($needle)
    })
    if ($hits.Count -eq 0) { Add-Result "PASS" "no_stale_literal_$($needle -replace '[^A-Za-z0-9]+','_')" $needle }
    else { foreach ($hit in $hits) { Add-Result "FAIL" "stale_literal" "$(ConvertTo-ArqenRelativePath $hit.FullName $RepoRoot) -> $needle" } }
}

function Test-ToolScriptHasSwitchParameter {
    param(
        [string]$Path,
        [string]$Name
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) { return $false }
    if (-not $ast.ParamBlock) { return $false }

    foreach ($parameter in $ast.ParamBlock.Parameters) {
        if ($parameter.Name.VariablePath.UserPath -eq $Name) { return $true }
    }

    return $false
}

$rootWrappers = @("build.ps1","generate.ps1","validate.ps1","test.ps1")
foreach ($name in $rootWrappers) {
    $path = Join-Path $RepoRoot "Tools\$name"
    if (-not (Test-Path $path)) { continue }
    $hasList = Test-ToolScriptHasSwitchParameter -Path $path -Name "List"
    Add-Result ($(if ($hasList) { "PASS" } else { "FAIL" })) "wrapper_${name}_list" "$name exposes -List switch parameter"
}

$testWrapper = Join-Path $RepoRoot "Tools\test.ps1"
if (Test-Path $testWrapper) {
    foreach ($switchName in @("Changed", "Everything", "IncludeBuildScripts", "IncludeScaffoldScripts", "IncludeHistoricalValidators", "IncludeSpecCoverageValidators", "IncludeExpectedIr")) {
        $hasSwitch = Test-ToolScriptHasSwitchParameter -Path $testWrapper -Name $switchName
        Add-Result ($(if ($hasSwitch) { "PASS" } else { "FAIL" })) "wrapper_test.ps1_$($switchName)_switch" "test.ps1 exposes -$switchName switch parameter"
    }
}

Set-Content -Path $OutPath -Value $lines.ToArray() -Encoding UTF8
if ($failed) { exit 1 }
exit 0
