$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "CommandAutomationCommon.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "repo_hygiene_validation.txt"
$lines = New-Object System.Collections.Generic.List[string]
$failed = $false

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) {
        $lines.Add("PASS|$Name|$Detail") | Out-Null
    } else {
        $script:failed = $true
        $lines.Add("FAIL|$Name|$Detail") | Out-Null
    }
}

function Add-Warn {
    param([string]$Name, [string]$Detail = "")
    $lines.Add("WARN|$Name|$Detail") | Out-Null
}

$gitattributesPath = Join-Path $root ".gitattributes"
$gitignorePath = Join-Path $root ".gitignore"
$gitattributes = if (Test-Path $gitattributesPath) { Get-Content $gitattributesPath -Raw } else { "" }
$gitignore = if (Test-Path $gitignorePath) { Get-Content $gitignorePath -Raw } else { "" }

Add-Result "gitattributes_cs" ($gitattributes -match '(?m)^\*\.cs\s+text\s+eol=') "C# line endings pinned"
Add-Result "gitattributes_csproj" ($gitattributes -match '(?m)^\*\.csproj\s+text\s+eol=') "C# project line endings pinned"
Add-Result "gitignore_pdb" ($gitignore -match '(?m)^/Tools/\*\.pdb$' -or $gitignore -match '(?m)^\*\.pdb$' -or $gitignore -match '(?m)^/Tools/\*\*/\*\.pdb$') "debug symbols ignored"
Add-Result "gitignore_patch" ($gitignore -match '(?m)^\*\.patch$') "temporary patches ignored"
Add-Result "gitignore_tools_publish" ($gitignore -match '(?m)^/Tools/publish/$') "tool publish output ignored"

$requiredTools = @(
    "validate_repo_hygiene.ps1",
    "validate_backend_capabilities.ps1",
    "validate_command_test_coverage.ps1",
    "generate_error_code_registry.ps1"
)
foreach ($tool in $requiredTools) {
    Add-Result "tool_$tool" (Test-Path (Join-Path $root "Tools\$tool")) "required hardening tool present"
}

$trackedBadPatterns = @(
    "Tools/publish/",
    "Tools/M10GDriver/publish/",
    ".pdb",
    ".rej",
    ".orig"
)
foreach ($pattern in $trackedBadPatterns) {
    $matches = @()
    if (Test-Path (Join-Path $root ".git")) {
        Push-Location $root
        try {
            $tracked = git ls-files 2>$null
            foreach ($item in $tracked) {
                if ($item.Contains($pattern) -or ($pattern.StartsWith(".") -and $item.EndsWith($pattern))) {
                    $matches += $item
                }
            }
        } finally {
            Pop-Location
        }
    }

    if ($matches.Count -eq 0) {
        Add-Result "no_tracked_$($pattern.Replace('/', '_').Replace('.', 'dot'))" $true "tracked artifact guard"
    } else {
        Add-Warn "tracked_$($pattern.Replace('/', '_').Replace('.', 'dot'))" (($matches | Select-Object -First 5) -join ',')
    }
}

Set-Content -Path $outPath -Value $lines.ToArray() -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
if ($failed) { exit 1 }
exit 0
