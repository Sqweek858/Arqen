param(
    [Parameter(Position=0)]
    [string]$Name,
    [switch]$List,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

function Get-ArqenRepoRoot {
    $dir = (Resolve-Path (Join-Path $PSScriptRoot ".." )).Path
    while ($true) {
        if ((Test-Path (Join-Path $dir "Docs\MILESTONES.md")) -and (Test-Path (Join-Path $dir "Tools\M10GDriver"))) { return $dir }
        $parent = Split-Path -Parent $dir
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $dir) { break }
        $dir = $parent
    }
    throw "Could not locate Arqen repo root from $PSScriptRoot"
}

function Get-RelativePathSafe {
    param([string]$Base,[string]$Path)
    try { return [System.IO.Path]::GetRelativePath($Base, $Path) } catch { return $Path }
}

function Resolve-ArqenScript {
    param([string]$Root,[string]$Folder,[string]$Prefix,[string]$Name)
    $base = Join-Path $Root $Folder
    if (-not (Test-Path $base)) { throw "Tool folder not found: $base" }
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }

    $needles = New-Object System.Collections.Generic.List[string]
    if ($Name.EndsWith('.ps1')) { $needles.Add($Name) | Out-Null } else { $needles.Add("$Name.ps1") | Out-Null }
    if (-not $Name.StartsWith($Prefix)) {
        if ($Name.EndsWith('.ps1')) { $needles.Add("$Prefix$($Name.Substring(0, $Name.Length - 4)).ps1") | Out-Null }
        else { $needles.Add("$Prefix$Name.ps1") | Out-Null }
    }

    foreach ($needle in $needles) {
        $matches = @(Get-ChildItem $base -Recurse -File -Filter $needle)
        if ($matches.Count -eq 1) { return $matches[0].FullName }
    }

    $loose = @(Get-ChildItem $base -Recurse -File -Filter "$Prefix*.ps1" | Where-Object { $_.BaseName -like "*$Name*" })
    if ($loose.Count -eq 1) { return $loose[0].FullName }
    if ($loose.Count -gt 1) {
        $list = ($loose | ForEach-Object { Get-RelativePathSafe $Root $_.FullName }) -join "`n"
        throw "Ambiguous script name '$Name' in $Folder. Matches:`n$list"
    }
    return $null
}

$RepoRoot = Get-ArqenRepoRoot
$ToolFolder = "Tools\Build"
$Prefix = "build_"
$Base = Join-Path $RepoRoot $ToolFolder

if ($List -or [string]::IsNullOrWhiteSpace($Name)) {
    Get-ChildItem $Base -Recurse -File -Filter "$Prefix*.ps1" | Sort-Object FullName | ForEach-Object { Write-Host (Get-RelativePathSafe $RepoRoot $_.FullName) }
    exit 0
}

$script = Resolve-ArqenScript -Root $RepoRoot -Folder $ToolFolder -Prefix $Prefix -Name $Name
if (-not $script) {
    Write-Host "No script found for '$Name' in $ToolFolder. Available:"
    Get-ChildItem $Base -Recurse -File -Filter "$Prefix*.ps1" | Sort-Object FullName | ForEach-Object { Write-Host (Get-RelativePathSafe $RepoRoot $_.FullName) }
    exit 2
}

& $script @RemainingArgs
exit $LASTEXITCODE
