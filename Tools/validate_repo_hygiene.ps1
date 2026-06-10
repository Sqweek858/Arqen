param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$failed = $false
$lines = New-Object System.Collections.Generic.List[string]

function Emit-Check {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Message
    )

    if ($Ok) {
        $lines.Add("PASS|$Name|$Message") | Out-Null
        Write-Host "PASS|$Name|$Message"
    } else {
        $lines.Add("FAIL|$Name|$Message") | Out-Null
        Write-Host "FAIL|$Name|$Message"
        $script:failed = $true
    }
}

function Read-Lines {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return @()
    }

    return @(Get-Content $Path | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
}

function Has-Any-Line {
    param(
        [string[]]$Lines,
        [string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        if ($Lines -contains $candidate) {
            return $true
        }
    }

    return $false
}

$gitAttributesPath = Join-Path $RepoRoot ".gitattributes"
$gitIgnorePath = Join-Path $RepoRoot ".gitignore"

$gitAttributes = Read-Lines $gitAttributesPath
$gitIgnore = Read-Lines $gitIgnorePath

$hasCsEol = $false
$hasCsprojEol = $false

foreach ($line in $gitAttributes) {
    if ($line -match '^\*\.cs\s+text\s+eol=') {
        $hasCsEol = $true
    }
    if ($line -match '^\*\.csproj\s+text\s+eol=') {
        $hasCsprojEol = $true
    }
}

Emit-Check "gitattributes_cs" $hasCsEol "C# line endings pinned"
Emit-Check "gitattributes_csproj" $hasCsprojEol "C# project line endings pinned"
Emit-Check "gitattributes_self" (Has-Any-Line $gitAttributes @(".gitattributes text eol=lf")) ".gitattributes line endings pinned"
Emit-Check "gitattributes_gitignore" (Has-Any-Line $gitAttributes @(".gitignore text eol=lf")) ".gitignore line endings pinned"

$hasPdbIgnore = Has-Any-Line $gitIgnore @(
    "*.pdb",
    "/Tools/*.pdb",
    "/Tools/**/*.pdb",
    "Tools/*.pdb",
    "Tools/**/*.pdb"
)

$hasPatchIgnore = Has-Any-Line $gitIgnore @(
    "*.patch",
    "/*.patch"
)

$hasToolsPublishIgnore = Has-Any-Line $gitIgnore @(
    "/Tools/publish/",
    "Tools/publish/",
    "/Tools/M10GDriver/publish/",
    "Tools/M10GDriver/publish/"
)

Emit-Check "gitignore_pdb" $hasPdbIgnore "debug symbols ignored"
Emit-Check "gitignore_patch" $hasPatchIgnore "temporary patches ignored"
Emit-Check "gitignore_tools_publish" $hasToolsPublishIgnore "tool publish output ignored"

$requiredTools = @(
    "Tools/validate_repo_hygiene.ps1",
    "Tools/validate_backend_capabilities.ps1",
    "Tools/validate_command_test_coverage.ps1",
    "Tools/generate_error_code_registry.ps1",
    "Tools/validate_strict_ir.ps1",
    "Tools/validate_keyword_registry.ps1",
    "Tools/validate_parser_statement_map.ps1",
    "Tools/validate_test_slice.ps1",
    "Tools/validate_m19a_runtime_loop_contract.ps1",
    "Tools/validate_m19b_style_contract.ps1",
    "Tools/validate_m19c_ui_contract.ps1",
    "Tools/validate_m19d_ui_layout_contract.ps1",
    "Tools/validate_m19efgh_ui_final_contract.ps1"
)

foreach ($tool in $requiredTools) {
    $path = Join-Path $RepoRoot $tool
    Emit-Check ("tool_" + (Split-Path $tool -Leaf)) (Test-Path $path) "required hardening tool present"
}

$tracked = @(git -C $RepoRoot ls-files | ForEach-Object { $_ -replace "\\", "/" })

$trackedToolsPublish = @($tracked | Where-Object { $_ -like "Tools/publish/*" })
$trackedM10Publish = @($tracked | Where-Object { $_ -like "Tools/M10GDriver/publish/*" })
$trackedPdb = @($tracked | Where-Object { $_ -like "*.pdb" })
$trackedRej = @($tracked | Where-Object { $_ -like "*.rej" })
$trackedOrig = @($tracked | Where-Object { $_ -like "*.orig" })

Emit-Check "no_tracked_Tools_publish_" ($trackedToolsPublish.Count -eq 0) "tracked artifact guard"
Emit-Check "no_tracked_Tools_M10GDriver_publish_" ($trackedM10Publish.Count -eq 0) "tracked artifact guard"
Emit-Check "no_tracked_dotpdb" ($trackedPdb.Count -eq 0) "tracked artifact guard"
Emit-Check "no_tracked_dotrej" ($trackedRej.Count -eq 0) "tracked artifact guard"
Emit-Check "no_tracked_dotorig" ($trackedOrig.Count -eq 0) "tracked artifact guard"

function Test-NoCrLf {
    param([string]$RelativePath)
    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path $path)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    for ($i = 0; $i -lt ($bytes.Length - 1); $i++) {
        if ($bytes[$i] -eq 13 -and $bytes[$i + 1] -eq 10) { return $false }
    }
    return $true
}

Emit-Check "lf_pinned_gitattributes_no_crlf" (Test-NoCrLf ".gitattributes") ".gitattributes has LF line endings"
Emit-Check "lf_pinned_gitignore_no_crlf" (Test-NoCrLf ".gitignore") ".gitignore has LF line endings"


$generatedDir = Join-Path $RepoRoot "Build/Generated"
New-Item -ItemType Directory -Force -Path $generatedDir | Out-Null
$outPath = Join-Path $generatedDir "repo_hygiene_validation.txt"
[System.IO.File]::WriteAllLines($outPath, $lines.ToArray(), [System.Text.UTF8Encoding]::new($false))
if ($failed) {
    exit 1
}

exit 0
