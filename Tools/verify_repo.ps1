param(
    [switch]$BuildDriver,
    [switch]$RunSmoke,
    [switch]$RunValidators,
    [switch]$RunAllCommandTests,
    [switch]$StrictClean
)

$ErrorActionPreference = "Continue"
$script:Pass = 0
$script:Warn = 0
$script:Fail = 0
$script:Lines = New-Object System.Collections.Generic.List[string]

function Add-Line {
    param([string]$Status,[string]$Name,[string]$Note = "")
    $line = if ([string]::IsNullOrWhiteSpace($Note)) { "$Status|$Name" } else { "$Status|$Name|$Note" }
    $script:Lines.Add($line) | Out-Null
    Write-Host $line
    if ($Status -eq 'PASS') { $script:Pass++ }
    elseif ($Status -eq 'WARN') { $script:Warn++ }
    elseif ($Status -eq 'FAIL') { $script:Fail++ }
}

function Pass { param([string]$Name,[string]$Note = "") Add-Line "PASS" $Name $Note }
function Warn { param([string]$Name,[string]$Note = "") Add-Line "WARN" $Name $Note }
function Fail { param([string]$Name,[string]$Note = "") Add-Line "FAIL" $Name $Note }

function Get-ArqenRepoRoot {
    $dir = (Resolve-Path (Join-Path $PSScriptRoot ".." )).Path
    while ($true) {
        if ((Test-Path (Join-Path $dir "Docs\MILESTONES.md")) -and (Test-Path (Join-Path $dir "Tools\M10GDriver")) -and (Test-Path (Join-Path $dir "Tests\CommandTests"))) { return $dir }
        $parent = Split-Path -Parent $dir
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $dir) { break }
        $dir = $parent
    }
    throw "Could not locate Arqen repo root from $PSScriptRoot"
}

function RelPath {
    param([string]$Path)

    try {
        $rootFull = [System.IO.Path]::GetFullPath($RepoRoot)
        $pathFull = [System.IO.Path]::GetFullPath($Path)
        $rootFull = $rootFull.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)) + [System.IO.Path]::DirectorySeparatorChar
        if ($pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $pathFull.Substring($rootFull.Length)
        }
    } catch {
    }

    try { return [System.IO.Path]::GetRelativePath($RepoRoot, $Path) } catch { return $Path }
}

function Test-ExcludedPath {
    param([string]$Rel)
    $r = $Rel -replace '/', '\'
    if ($r -like '.git\*') { return $true }
    if ($r -like '.vs\*') { return $true }
    if ($r -like 'Build\*') { return $true }
    if ($r -like 'What_I_Can_Do\Build\*') { return $true }
    if ($r -like 'What_I_Can_Do\Exe\*') { return $true }
    if ($r -like 'VisualStudio\Trash\*') { return $true }
    if ($r -like 'VisualStudio\.vs\*') { return $true }
    if ($r -like 'Tools\M10GDriver\bin\*') { return $true }
    if ($r -like 'Tools\M10GDriver\obj\*') { return $true }
    if ($r -like 'Tools\M10GDriver\publish\*') { return $true }
    if ($r -like 'Tools\publish\*') { return $true }
    if ($r -like 'arqen_ps1_repair_*.ps1') { return $true }
    return $false
}

function Invoke-Step {
    param([string]$Name,[scriptblock]$Block)
    try {
        & $Block
        $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
        if ($code -eq 0) { Pass $Name "exit=0" } else { Fail $Name "exit=$code" }
    } catch {
        Fail $Name $_.Exception.Message
    }
}

$RepoRoot = Get-ArqenRepoRoot
$Generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $Generated | Out-Null
$ReportPath = Join-Path $Generated "arqen_repo_verification_report.txt"
Add-Line "INFO" "repo_root" $RepoRoot
Add-Line "INFO" "report_path" $ReportPath

if ($StrictClean) {
    $cleanDirs = @(
        "Build\Diagnostics", "Build\Errors", "Build\EXE", "Build\Generated", "Build\Logs", "Build\Manifests", "Build\Temp",
        "Tools\M10GDriver\bin", "Tools\M10GDriver\obj", "Tools\M10GDriver\publish", "Tools\publish"
    )
    foreach ($rel in $cleanDirs) {
        $path = Join-Path $RepoRoot $rel
        if (Test-Path $path) {
            try { Remove-Item $path -Recurse -Force; Add-Line "INFO" "clean_removed" $rel } catch { Warn "clean_failed" "$rel :: $($_.Exception.Message)" }
        }
    }
    New-Item -ItemType Directory -Force -Path $Generated | Out-Null
}

$requiredDirs = @("Docs", "Docs\Info", "Docs\Language", "Docs\Milestones", "Docs\Reference", "Tools", "Tools\Build", "Tools\Common", "Tools\Generate", "Tools\Lowering", "Tools\Scaffold", "Tools\Internal", "Tools\Internal\Test", "Tools\Validate", "Tools\M10GDriver", "Tests", "Tests\CommandTests")
foreach ($d in $requiredDirs) {
    if (Test-Path (Join-Path $RepoRoot $d)) { Pass "dir_exists" $d } else { Fail "dir_exists" $d }
}

$requiredFiles = @(
    "run_me.ps1",
    "README.md", "What_I_Can_Do\README.md", "VisualStudio\README.md",
    "What_I_Can_Do\Build\build_all.ps1", "VisualStudio\Scripts\vs_build_what_i_can_do.ps1", "VisualStudio\Scripts\vs_clean_what_i_can_do.ps1",
    "Docs\MILESTONES.md", "Docs\Info\TOOLS.md", "Docs\Info\TERMINAL_COMMANDS.md", "Docs\Language\LANGUAGE.md", "Docs\Language\ERRORS.md",
    "Docs\Reference\Runtime\RUNTIME_CONTRACT.md", "Docs\Reference\Runtime\RUNTIME_ACTION_CATALOG.txt",
    "Tools\arqc.ps1", "Tools\build.ps1", "Tools\generate.ps1", "Tools\validate.ps1", "Tools\test.ps1", "Tools\run_test_slice.ps1", "Tools\verify_repo.ps1", "Tools\Internal\Test\run_test_slice.ps1", "Tools\Internal\Test\run_everything.ps1", "Tools\Validate\Core\validate_tool_surface.ps1", "Tools\Validate\Core\validate_trash.ps1"
)
foreach ($f in $requiredFiles) {
    if (Test-Path (Join-Path $RepoRoot $f)) { Pass "file_exists" $f } else { Fail "file_exists" $f }
}

$badDocs = New-Object System.Collections.Generic.List[string]
Get-ChildItem $RepoRoot -Recurse -File -Force | ForEach-Object {
    $rel = RelPath $_.FullName
    if (Test-ExcludedPath $rel) { return }
    $ext = $_.Extension.ToLowerInvariant()
    if ($ext -ne '.md' -and $ext -ne '.txt') { return }
    $norm = $rel -replace '/', '\'
    if ($norm -eq 'README.md') { return }
    if ($norm -eq 'What_I_Can_Do\README.md') { return }
    if ($norm -eq 'VisualStudio\README.md') { return }
    if (-not ($norm -like 'Docs\*' -or $norm -like 'Tests\*')) { $badDocs.Add($rel) | Out-Null }
}
if ($badDocs.Count -eq 0) { Pass "docs_placement" "source .md/.txt files are under Docs/ or Tests/, with approved README/generated-output exceptions allowed" }
else {
    Fail "docs_placement" "$($badDocs.Count) source .md/.txt files outside Docs or Tests"
    $badDocs | Select-Object -First 40 | ForEach-Object { Fail "bad_doc" $_ }
    if ($badDocs.Count -gt 40) { Warn "bad_doc_truncated" "showing 40 of $($badDocs.Count)" }
}

$badPs1 = New-Object System.Collections.Generic.List[string]
Get-ChildItem $RepoRoot -Recurse -File -Force -Filter "*.ps1" | ForEach-Object {
    $rel = RelPath $_.FullName
    if (Test-ExcludedPath $rel) { return }
    $norm = $rel -replace '/', '\'
    if ($norm -eq 'run_me.ps1') { return }
    if ($norm -eq 'What_I_Can_Do\Build\build_all.ps1') { return }
    if ($norm -eq 'VisualStudio\Scripts\vs_build_what_i_can_do.ps1') { return }
    if ($norm -eq 'VisualStudio\Scripts\vs_clean_what_i_can_do.ps1') { return }
    if (-not ($norm -like 'Tools\*')) { $badPs1.Add($rel) | Out-Null }
}
if ($badPs1.Count -eq 0) { Pass "ps1_placement" "source .ps1 files are under Tools/, with approved root/showcase/VisualStudio wrappers allowed" }
else { Fail "ps1_placement" "$($badPs1.Count) source .ps1 files outside Tools/ or root run_me.ps1"; $badPs1 | Select-Object -First 40 | ForEach-Object { Fail "bad_ps1" $_ } }

$parseFail = 0
$parseTargets = @(Get-ChildItem (Join-Path $RepoRoot "Tools") -Recurse -File -Filter "*.ps1")
$extraParseTargets = @(
    "run_me.ps1",
    "What_I_Can_Do\Build\build_all.ps1",
    "VisualStudio\Scripts\vs_build_what_i_can_do.ps1",
    "VisualStudio\Scripts\vs_clean_what_i_can_do.ps1"
)
foreach ($relParseTarget in $extraParseTargets) {
    $parsePath = Join-Path $RepoRoot $relParseTarget
    if (Test-Path $parsePath) { $parseTargets = @($parseTargets + (Get-Item $parsePath)) }
}
$parseTargets | ForEach-Object {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) { $parseFail++; Fail "ps1_parse" "$(RelPath $_.FullName): $($errors[0].Message)" }
}
if ($parseFail -eq 0) { Pass "ps1_parse" "all Tools/*.ps1 plus approved root/showcase/VisualStudio scripts parsed" }

$stalePatterns = @(
    "Docs\Reference\Docs\Reference\",
    "Docs/Reference/Docs/Reference/",
    "Tools\Test\run_test_slice.ps1",
    "Tools/Test/run_test_slice.ps1",
    "Tools\Test\run_everything.ps1",
    "Tools/Test/run_everything.ps1",
    "Tools\Test\run_all_tests.ps1",
    "Tools/Test/run_all_tests.ps1"
)
$staleCount = 0
$staleLiteralPolicyScripts = @(
    (Join-Path $RepoRoot "Tools\verify_repo.ps1"),
    (Join-Path $RepoRoot "Tools\Validate\Core\validate_tool_surface.ps1"),
    (Join-Path $RepoRoot "Tools\Validate\Core\validate_trash.ps1")
) | ForEach-Object { [System.IO.Path]::GetFullPath($_) }
Get-ChildItem (Join-Path $RepoRoot "Tools") -Recurse -File -Filter "*.ps1" | ForEach-Object {
    $full = [System.IO.Path]::GetFullPath($_.FullName)
    if ($staleLiteralPolicyScripts -contains $full) { return }
    $text = Get-Content $_.FullName -Raw
    foreach ($pat in $stalePatterns) {
        if ($text.Contains($pat)) { $staleCount++; Fail "stale_path" "$(RelPath $_.FullName) -> $pat" }
    }
}
if ($staleCount -eq 0) { Pass "stale_path_literals" "no stale path literals outside repo/checker scripts" } else { Fail "stale_path_literals" "$staleCount stale references found" }

$repoPaths = Join-Path $RepoRoot "Tools\M10GDriver\Core\RepoPaths.cs"
if (Test-Path $repoPaths) {
    $rp = Get-Content $repoPaths -Raw
    if ($rp.Contains("Docs") -and $rp.Contains("MILESTONES.md") -and $rp.Contains("Tests") -and -not $rp.Contains("Experiments")) { Pass "driver_root_marker" "RepoPaths.cs uses cleaned repo markers" }
    else { Fail "driver_root_marker" "RepoPaths.cs still appears stale" }
} else { Fail "driver_root_marker" "RepoPaths.cs missing" }

Invoke-Step "wrapper_build_list" { & (Join-Path $RepoRoot "Tools\build.ps1") -List | Out-Null }
Invoke-Step "wrapper_generate_list" { & (Join-Path $RepoRoot "Tools\generate.ps1") -List | Out-Null }
Invoke-Step "wrapper_validate_list" { & (Join-Path $RepoRoot "Tools\validate.ps1") -List | Out-Null }
Invoke-Step "wrapper_test_list" { & (Join-Path $RepoRoot "Tools\test.ps1") -List | Out-Null }

if ($BuildDriver) { Invoke-Step "build_driver" { & (Join-Path $RepoRoot "Tools\arqc.ps1") -BuildDriver } }

if ($RunSmoke) {
    $smokeDir = Join-Path $RepoRoot "Build\Generated"
    New-Item -ItemType Directory -Force -Path $smokeDir | Out-Null
    $src = Join-Path $smokeDir "verify_smoke.arq"
    $out = Join-Path $RepoRoot "Build\EXE\verify_smoke.exe"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) | Out-Null
    $smoke = @(
        'program "VerifySmoke"',
        '',
        'title "Verify Smoke"',
        'message text "ok"',
        'blend mix to code 0',
        '',
        'end program "VerifySmoke"'
    )
    [System.IO.File]::WriteAllLines($src, $smoke, [System.Text.UTF8Encoding]::new($false))
    Invoke-Step "smoke_compile" { & (Join-Path $RepoRoot "Tools\arqc.ps1") $src -o $out }
    if (Test-Path $out) { Pass "smoke_output_exists" (RelPath $out) } else { Fail "smoke_output_exists" (RelPath $out) }
}

if ($RunValidators) {
    $validators = @(
        "Core\validate_repo_hygiene.ps1",
        "Core\validate_backend_contract_docs.ps1",
        "Runtime\validate_m61_m62_enum_scope_params.ps1",
        "Core\validate_tool_surface.ps1",
        "Core\validate_trash.ps1"
    )
    foreach ($v in $validators) {
        $vp = Join-Path (Join-Path $RepoRoot "Tools\Validate") $v
        if (-not (Test-Path $vp)) { Fail "validator_$v" "missing"; continue }
        Invoke-Step "validator_$(Split-Path -Leaf $v)" { & $vp }
    }
}

if ($RunAllCommandTests) {
    Invoke-Step "all_command_tests" { & (Join-Path $RepoRoot "Tools\test.ps1") -AllCommand }
}

Add-Line "INFO" "summary" "pass=$script:Pass warn=$script:Warn fail=$script:Fail"
[System.IO.File]::WriteAllLines($ReportPath, $script:Lines, [System.Text.UTF8Encoding]::new($false))
if ($script:Fail -gt 0) { exit 1 }
exit 0
