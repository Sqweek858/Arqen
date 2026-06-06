param(
    [Parameter(Mandatory=$true)]
    [string]$Name,
    [string]$Syntax = "",
    [string]$Tokens = "",
    [string]$Ast = "",
    [string]$Semantic = "",
    [string]$Ir = "none",
    [string]$Backend = "none",
    [string]$Category = "draft",
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Normalize-CommandId {
    param([string]$Value)
    $id = $Value.Trim().ToLowerInvariant() -replace '[\s-]+', '_'
    $id = $id -replace '[^a-z0-9_]', ''
    return $id.Trim("_")
}

$commandId = Normalize-CommandId $Name
if ([string]::IsNullOrWhiteSpace($commandId)) {
    Write-Host "ERROR|invalid_Name"
    exit 2
}

if ([string]::IsNullOrWhiteSpace($Syntax)) {
    $Syntax = $commandId.Replace("_", " ")
}
if ([string]::IsNullOrWhiteSpace($Tokens)) {
    $first = $commandId.Split("_")[0]
    $Tokens = "KEYWORD($first)"
}
if ([string]::IsNullOrWhiteSpace($Ast)) {
    $Ast = "$($commandId)_Skeleton"
}
if ([string]::IsNullOrWhiteSpace($Semantic)) {
    $Semantic = "generated skeleton"
}

$target = Join-Path $PSScriptRoot "CommandAutomation\new_command_skeleton.ps1"
if ($DryRun -and $Force) {
    & $target -CommandId $commandId -Syntax $Syntax -Tokens $Tokens -Ast $Ast -Semantic $Semantic -Ir $Ir -Backend $Backend -Category $Category -DryRun -Force
} elseif ($DryRun) {
    & $target -CommandId $commandId -Syntax $Syntax -Tokens $Tokens -Ast $Ast -Semantic $Semantic -Ir $Ir -Backend $Backend -Category $Category -DryRun
} elseif ($Force) {
    & $target -CommandId $commandId -Syntax $Syntax -Tokens $Tokens -Ast $Ast -Semantic $Semantic -Ir $Ir -Backend $Backend -Category $Category -Force
} else {
    & $target -CommandId $commandId -Syntax $Syntax -Tokens $Tokens -Ast $Ast -Semantic $Semantic -Ir $Ir -Backend $Backend -Category $Category
}
exit $LASTEXITCODE
