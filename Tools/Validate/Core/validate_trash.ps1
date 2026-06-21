param(
    [switch]$StrictLocal
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "Common\ArqenTooling.psm1") -Force

$RepoRoot = Get-ArqenRepoRoot -StartPath $PSScriptRoot
$Generated = Join-Path $RepoRoot "Build\Generated"
New-Item -ItemType Directory -Force -Path $Generated | Out-Null
$OutPath = Join-Path $Generated "trash_validation.txt"
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Add-Result {
    param([string]$Status,[string]$Name,[string]$Detail = "")
    if ($Status -eq "FAIL") { $script:failed = $true }
    $line = if ([string]::IsNullOrWhiteSpace($Detail)) { "$Status|$Name" } else { "$Status|$Name|$Detail" }
    $lines.Add($line) | Out-Null
    Write-Host $line
}

function Rel {
    param([string]$Path)
    ConvertTo-ArqenRelativePath $Path $RepoRoot
}

function Get-GitTrackedFiles {
    try {
        return @(git -C $RepoRoot ls-files | ForEach-Object { $_ -replace '/', '\' })
    } catch {
        Add-Result "WARN" "git_tracked_unavailable" $_.Exception.Message
        return @()
    }
}

function Get-GitUntrackedVisibleFiles {
    try {
        return @(git -C $RepoRoot ls-files --others --exclude-standard | ForEach-Object { $_ -replace '/', '\' })
    } catch {
        Add-Result "WARN" "git_untracked_unavailable" $_.Exception.Message
        return @()
    }
}

$tracked = Get-GitTrackedFiles
$visibleUntracked = Get-GitUntrackedVisibleFiles

$trackedTrashPatterns = @(
    'Build\*',
    'Tools\publish\*',
    'Tools\M10GDriver\bin\*',
    'Tools\M10GDriver\obj\*',
    'Tools\M10GDriver\publish\*',
    '*.obj',
    '*.pdb',
    '*.ilk',
    '*.exp',
    '*.lib',
    '*.rej',
    '*.orig',
    '*.patch',
    '*.zip',
    '*.7z',
    '*.rar'
)

$trackedTrash = New-Object System.Collections.Generic.List[string]
foreach ($file in $tracked) {
    if ($file -eq 'Build\.gitkeep') { continue }
    foreach ($pattern in $trackedTrashPatterns) {
        if ($file -like $pattern) { $trackedTrash.Add($file) | Out-Null; break }
    }
}
if ($trackedTrash.Count -eq 0) { Add-Result "PASS" "no_tracked_trash" "no generated/archive/patch artifacts are tracked" }
else { foreach ($item in $trackedTrash) { Add-Result "FAIL" "tracked_trash" $item } }

$legacyPs1 = @(Get-ChildItem (Join-Path $RepoRoot "Tools\Legacy") -File -Filter "*.ps1" -ErrorAction SilentlyContinue)
if ($legacyPs1.Count -eq 0) { Add-Result "PASS" "legacy_folder_clean" "Tools\Legacy has no active .ps1 files" }
else { foreach ($item in $legacyPs1) { Add-Result "FAIL" "legacy_active_script" (Rel $item.FullName) } }

$publicTestPs1 = @(Get-ChildItem (Join-Path $RepoRoot "Tools\Test") -File -Filter "*.ps1" -ErrorAction SilentlyContinue)
if ($publicTestPs1.Count -eq 0) { Add-Result "PASS" "public_test_folder_clean" "Tools\Test has no public engine .ps1 files; use Tools\test.ps1" }
else { foreach ($item in $publicTestPs1) { Add-Result "FAIL" "public_test_engine_trash" (Rel $item.FullName) } }

$duplicateBuildDoc = Join-Path $RepoRoot "Build\BUILD_OUTPUT.md"
if (Test-Path $duplicateBuildDoc) {
    Add-Result "FAIL" "build_output_doc_in_build" "Build\BUILD_OUTPUT.md is trash; keep the source doc at Docs\Info\BUILD_OUTPUT.md"
} else {
    Add-Result "PASS" "build_output_doc_not_in_build" "Build\BUILD_OUTPUT.md absent"
}

$visibleTrash = New-Object System.Collections.Generic.List[string]
foreach ($file in $visibleUntracked) {
    $norm = $file -replace '/', '\'
    if ($norm -eq 'Build\.gitkeep') { continue }
    if ($norm -like 'Build\*') { $visibleTrash.Add($norm) | Out-Null; continue }
    if ($norm -like '*.rej' -or $norm -like '*.orig') { $visibleTrash.Add($norm) | Out-Null; continue }
}
if ($visibleTrash.Count -eq 0) { Add-Result "PASS" "no_visible_untracked_trash" "no visible untracked Build/rej/orig trash" }
else { foreach ($item in $visibleTrash) { Add-Result "FAIL" "visible_untracked_trash" $item } }

$toolsRoot = Join-Path $RepoRoot "Tools"
$ps1Files = @(Get-ChildItem $toolsRoot -Recurse -File -Filter "*.ps1")
$staleNeedles = @(
    'Docs\Reference\Docs\Reference\',
    'Docs/Reference/Docs/Reference/',
    'Experiments\M10_SimpleExpressions\template_messagebox_m8.exe',
    'Experiments/M10_SimpleExpressions/template_messagebox_m8.exe',
    'Tools\Test\run_test_slice.ps1',
    'Tools/Test/run_test_slice.ps1',
    'Tools\Test\run_everything.ps1',
    'Tools/Test/run_everything.ps1',
    'Tools\Test\run_all_tests.ps1',
    'Tools/Test/run_all_tests.ps1'
)
$staleLiteralPolicyScripts = @(
    (Join-Path $RepoRoot "Tools\verify_repo.ps1"),
    (Join-Path $RepoRoot "Tools\Validate\Core\validate_tool_surface.ps1"),
    (Join-Path $RepoRoot "Tools\Validate\Core\validate_trash.ps1")
) | ForEach-Object { [System.IO.Path]::GetFullPath($_) }
$staleHits = 0
foreach ($file in $ps1Files) {
    $full = [System.IO.Path]::GetFullPath($file.FullName)
    if ($staleLiteralPolicyScripts -contains $full) { continue }
    $text = Get-Content $file.FullName -Raw
    foreach ($needle in $staleNeedles) {
        if ($text.Contains($needle)) {
            $staleHits += 1
            Add-Result "FAIL" "stale_tool_literal" "$(Rel $file.FullName) -> $needle"
        }
    }
}
if ($staleHits -eq 0) { Add-Result "PASS" "no_stale_tool_literals" "no known dead tool/path literals outside repo/checker scripts" }

if ($StrictLocal) {
    $ignoredLocalTrash = New-Object System.Collections.Generic.List[string]
    $strictPatterns = @('*.patch','*.zip','*.7z','*.rar','*.rej','*.orig','*.obj','*.pdb','*.ilk','*.exp','*.lib','*.dll','*.cache')
    foreach ($file in Get-ChildItem $RepoRoot -Recurse -File -Force) {
        $rel = Rel $file.FullName
        if ($rel -like '.git\*') { continue }
        if ($rel -like 'Build\*') { continue }
        if ($rel -like 'What_I_Can_Do\Build\*' -or $rel -like 'What_I_Can_Do\Exe\*') { continue }
        if ($rel -like 'VisualStudio\Trash\*' -or $rel -like 'VisualStudio\.vs\*') { continue }
        if ($rel -like 'Tools\M10GDriver\bin\*' -or $rel -like 'Tools\M10GDriver\obj\*' -or $rel -like 'Tools\M10GDriver\publish\*' -or $rel -like 'Tools\publish\*') { continue }
        foreach ($pattern in $strictPatterns) {
            if ($rel -like $pattern) { $ignoredLocalTrash.Add($rel) | Out-Null; break }
        }
    }
    if ($ignoredLocalTrash.Count -eq 0) { Add-Result "PASS" "strict_local_trash_clean" "no local archives/patch leftovers in repo tree" }
    else { foreach ($item in $ignoredLocalTrash) { Add-Result "FAIL" "strict_local_trash" $item } }
}

[System.IO.File]::WriteAllLines($OutPath, $lines.ToArray(), [System.Text.UTF8Encoding]::new($false))
if ($failed) { exit 1 }
exit 0
