$ErrorActionPreference = "Stop"

$VsRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = Split-Path -Parent $VsRoot
$TrashRoot = Join-Path $VsRoot "Trash\Arqen.WhatICanDo"
$ShowcaseBuild = Join-Path $RepoRoot "What_I_Can_Do\Build"
$ShowcaseExe = Join-Path $RepoRoot "What_I_Can_Do\Exe"

Remove-Item -LiteralPath $TrashRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $TrashRoot | Out-Null

if (Test-Path -LiteralPath $ShowcaseBuild) {
    Get-ChildItem -LiteralPath $ShowcaseBuild -Force |
        Where-Object { $_.Name -ne "build_all.ps1" -and $_.Name -ne ".gitkeep" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $ShowcaseExe) {
    Get-ChildItem -LiteralPath $ShowcaseExe -Force |
        Where-Object { $_.Name -ne ".gitkeep" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

"cleaned=$(Get-Date -Format o)" | Set-Content -LiteralPath (Join-Path $TrashRoot "last_clean.stamp") -Encoding ASCII
exit 0
