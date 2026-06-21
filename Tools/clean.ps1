param(
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "Common\ArqenTooling.psm1") -Force
$RepoRoot = Get-ArqenRepoRoot -StartPath $PSScriptRoot

$pathsToRemove = @(
    ".vs",
    "VisualStudio\.vs",
    "Tools\M10GDriver\bin",
    "Tools\M10GDriver\obj",
    "Tools\M10GDriver\publish",
    "Tools\publish"
)

if (-not $CheckOnly) {
    foreach ($rel in $pathsToRemove) {
        $path = Join-Path $RepoRoot $rel
        if (Test-Path $path) {
            Remove-Item -Recurse -Force $path
            Write-Host "REMOVED|$rel"
        }
    }

    $buildRoot = Join-Path $RepoRoot "Build"
    if (Test-Path $buildRoot) {
        Get-ChildItem $buildRoot -Force | Where-Object { $_.Name -ne ".gitkeep" } | Remove-Item -Recurse -Force
        Write-Host "CLEANED|Build"
    }

    $showcaseBuildRoot = Join-Path $RepoRoot "What_I_Can_Do\Build"
    if (Test-Path $showcaseBuildRoot) {
        Get-ChildItem $showcaseBuildRoot -Force | Where-Object { $_.Name -ne ".gitkeep" -and $_.Name -ne "build_all.ps1" } | Remove-Item -Recurse -Force
        Write-Host "CLEANED|What_I_Can_Do\Build"
    }

    $showcaseExeRoot = Join-Path $RepoRoot "What_I_Can_Do\Exe"
    if (Test-Path $showcaseExeRoot) {
        Get-ChildItem $showcaseExeRoot -Force | Where-Object { $_.Name -ne ".gitkeep" } | Remove-Item -Recurse -Force
        Write-Host "CLEANED|What_I_Can_Do\Exe"
    }

    $vsTrashRoot = Join-Path $RepoRoot "VisualStudio\Trash"
    if (Test-Path $vsTrashRoot) {
        Get-ChildItem $vsTrashRoot -Force | Where-Object { $_.Name -ne ".gitkeep" } | Remove-Item -Recurse -Force
        Write-Host "CLEANED|VisualStudio\Trash"
    }
}

$badDocs = @(Get-ChildItem $RepoRoot -Recurse -File -Include *.md,*.txt -Force |
    Where-Object {
        $rel = ConvertTo-ArqenRelativePath $_.FullName $RepoRoot
        -not $rel.Equals("README.md", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.Equals("What_I_Can_Do\README.md", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.Equals("VisualStudio\README.md", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.StartsWith("Docs\", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.StartsWith("Tests\", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.StartsWith("Build\", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.StartsWith("What_I_Can_Do\Build\", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.StartsWith("What_I_Can_Do\Exe\", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.StartsWith("VisualStudio\Trash\", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.StartsWith("VisualStudio\.vs\", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.StartsWith(".git\", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.StartsWith("Tools\M10GDriver\bin\", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.StartsWith("Tools\M10GDriver\obj\", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.StartsWith("Tools\M10GDriver\publish\", [StringComparison]::OrdinalIgnoreCase) -and
        -not $rel.StartsWith("Tools\publish\", [StringComparison]::OrdinalIgnoreCase)
    })

if ($badDocs.Count -gt 0) {
    Write-Host "FAIL|docs_location|md/txt outside Docs or Tests"
    $badDocs | ForEach-Object { Write-Host ("BAD_DOC|" + (ConvertTo-ArqenRelativePath $_.FullName $RepoRoot)) }
    exit 1
}

$backendScripts = @(Get-ChildItem (Join-Path $RepoRoot "Backends") -Recurse -Filter "*.ps1" -File -ErrorAction SilentlyContinue)
if ($backendScripts.Count -gt 0) {
    Write-Host "FAIL|backend_script_location|ps1 outside Tools"
    $backendScripts | ForEach-Object { Write-Host ("BAD_SCRIPT|" + (ConvertTo-ArqenRelativePath $_.FullName $RepoRoot)) }
    exit 1
}

Write-Host "PASS|docs_location|source docs are under Docs/ or Tests/, with approved README exceptions allowed"
Write-Host "PASS|script_location|ps1 tooling files are under approved Tools/root/showcase/VisualStudio locations"
exit 0
