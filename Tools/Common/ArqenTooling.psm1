function Get-ArqenRepoRoot {
    param([string]$StartPath = $PSScriptRoot)

    $resolvedStart = if ([string]::IsNullOrWhiteSpace($StartPath)) { (Get-Location).Path } else { $StartPath }
    $current = if (Test-Path $resolvedStart -PathType Leaf) {
        [IO.DirectoryInfo]::new((Split-Path -Parent $resolvedStart))
    } else {
        [IO.DirectoryInfo]::new($resolvedStart)
    }

    while ($null -ne $current) {
        $docsMarker = Join-Path $current.FullName "Docs\MILESTONES.md"
        $toolsDir = Join-Path $current.FullName "Tools"
        if ((Test-Path $docsMarker) -and (Test-Path $toolsDir)) {
            return $current.FullName
        }
        $current = $current.Parent
    }

    try {
        $gitRoot = (git -C $resolvedStart rev-parse --show-toplevel 2>$null).Trim()
        if (-not [string]::IsNullOrWhiteSpace($gitRoot)) {
            return $gitRoot
        }
    } catch {
    }

    throw "Unable to locate Arqen repository root from $resolvedStart"
}

function ConvertTo-ArqenRelativePath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [string]$RepoRoot = (Get-ArqenRepoRoot)
    )

    $root = ([IO.Path]::GetFullPath($RepoRoot)).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length)
    }
    return $full
}

function Get-ArqenToolScripts {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Area,
        [string]$RepoRoot = (Get-ArqenRepoRoot)
    )

    $root = Join-Path $RepoRoot "Tools\$Area"
    if (-not (Test-Path $root)) {
        return @()
    }
    return @(Get-ChildItem $root -Recurse -Filter "*.ps1" -File | Sort-Object FullName)
}

function Resolve-ArqenToolScript {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Area,
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [string]$Prefix = "",
        [string]$RepoRoot = (Get-ArqenRepoRoot)
    )

    $searchRoot = Join-Path $RepoRoot "Tools\$Area"
    if (-not (Test-Path $searchRoot)) {
        throw "Tool area not found: Tools\$Area"
    }

    $needles = @()
    if ($Name.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase)) {
        $needles += $Name
    } else {
        $needles += "$Name.ps1"
        if (-not [string]::IsNullOrWhiteSpace($Prefix) -and -not $Name.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $needles += "$Prefix$Name.ps1"
        }
    }

    $matches = @()
    foreach ($needle in $needles | Select-Object -Unique) {
        $matches += @(Get-ChildItem $searchRoot -Recurse -Filter $needle -File)
    }
    $matches = @($matches | Sort-Object FullName -Unique)

    if ($matches.Count -eq 1) {
        return $matches[0].FullName
    }

    if ($matches.Count -eq 0) {
        $available = @(Get-ArqenToolScripts -Area $Area -RepoRoot $RepoRoot | ForEach-Object { ConvertTo-ArqenRelativePath $_.FullName $RepoRoot })
        throw "No script found for '$Name' in Tools\$Area. Available:`n$($available -join "`n")"
    }

    $list = ($matches | ForEach-Object { ConvertTo-ArqenRelativePath $_.FullName $RepoRoot }) -join "`n"
    throw "Ambiguous script name '$Name' in Tools\$Area. Matches:`n$list"
}

function Write-ArqenScriptList {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Area,
        [string]$RepoRoot = (Get-ArqenRepoRoot)
    )

    foreach ($script in Get-ArqenToolScripts -Area $Area -RepoRoot $RepoRoot) {
        Write-Host (ConvertTo-ArqenRelativePath $script.FullName $RepoRoot)
    }
}

Export-ModuleMember -Function Get-ArqenRepoRoot,ConvertTo-ArqenRelativePath,Get-ArqenToolScripts,Resolve-ArqenToolScript,Write-ArqenScriptList
