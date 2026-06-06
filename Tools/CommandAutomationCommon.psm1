function Get-ArqenRepoRoot {
    return Split-Path -Parent $PSScriptRoot
}

function Get-ArqenGeneratedDir {
    $root = Get-ArqenRepoRoot
    $dir = Join-Path $root "Build\Generated"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

function ConvertTo-ArqenRelativePath {
    param([string]$Path)

    $root = (Get-ArqenRepoRoot).TrimEnd("\") + "\"
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length)
    }
    return $full
}

function Read-ArqenCommandSpec {
    param([string]$Path)

    $fields = [ordered]@{}
    foreach ($raw in Get-Content $Path) {
        $line = $raw.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
            continue
        }

        if ($line.Contains("|")) {
            $parts = $line.Split([char]"|", 2)
            $fields[$parts[0]] = $parts[1]
            continue
        }

        $splitAt = $line.IndexOf(" ")
        if ($splitAt -le 0) {
            continue
        }
        $key = $line.Substring(0, $splitAt)
        $value = $line.Substring($splitAt + 1)
        switch ($key) {
            "COMMAND" { $fields["COMMAND_ID"] = $value.Replace(" ", "_") }
            "SYNTAX" { $fields["CANONICAL"] = $value }
            "CATEGORY" { $fields["CATEGORY"] = $value }
            "TOKENS" { $fields["TOKENS"] = $value }
            "AST" { $fields["AST_NODE"] = ($value.Split("(", 2)[0]) }
            "SEMANTIC" { $fields["SEMANTIC"] = $value }
            "IR" { $fields["IR"] = $value }
            "BACKEND" { $fields["BACKEND"] = $value }
            "CODEGEN" { $fields["BACKEND"] = $value }
            "STATUS" { $fields["STATUS"] = $value }
            "LIMITATIONS" { $fields["LIMITATIONS"] = $value }
            "TEST_VALID" { $fields["VALID_TEST"] = $value }
            "TEST_INVALID" {
                if ($fields.Contains("INVALID_TEST")) {
                    $fields["INVALID_TEST"] = $fields["INVALID_TEST"] + ";" + $value
                } else {
                    $fields["INVALID_TEST"] = $value
                }
            }
        }
    }

    [pscustomobject]@{
        Path = $Path
        Fields = $fields
        Id = if ($fields.Contains("COMMAND_ID")) { $fields["COMMAND_ID"] } else { [IO.Path]::GetFileNameWithoutExtension($Path).Replace(".command", "") }
    }
}

function Get-ArqenCommandSpecs {
    param([switch]$IncludeDrafts)

    $root = Get-ArqenRepoRoot
    $files = @(Get-ChildItem (Join-Path $root "Specs\Commands") -Filter "*.command.txt" -File | Sort-Object Name)
    if ($IncludeDrafts) {
        $draft = Join-Path $root "Experiments\CommandDrafts\BlendMixToCode\COMMAND_SPEC.command.txt"
        if (Test-Path $draft) {
            $files += Get-Item $draft
        }
    }
    return $files | ForEach-Object { Read-ArqenCommandSpec $_.FullName }
}

function Get-ArqenSpecValue {
    param(
        $Spec,
        [string]$Key,
        [string]$Default = ""
    )

    if ($Spec.Fields.Contains($Key)) {
        return $Spec.Fields[$Key]
    }
    return $Default
}

function Test-ArqenReferencedPath {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -eq "none") {
        return $true
    }
    if (-not ($Value.Contains("\") -or $Value.Contains("/") -or $Value.EndsWith(".arq") -or $Value.EndsWith(".arqir") -or $Value.EndsWith(".txt"))) {
        return $true
    }

    $root = Get-ArqenRepoRoot
    foreach ($part in $Value.Split(";")) {
        $candidate = $part.Trim()
        if ([string]::IsNullOrWhiteSpace($candidate) -or $candidate -eq "none") {
            continue
        }
        $full = if ([IO.Path]::IsPathRooted($candidate)) { $candidate } else { Join-Path $root $candidate }
        if (-not (Test-Path $full)) {
            return $false
        }
    }
    return $true
}

function Get-ArqenKeywordTokens {
    param([string]$TokenText)

    $matches = [regex]::Matches($TokenText, "KEYWORD\(([^)]+)\)")
    return @($matches | ForEach-Object { $_.Groups[1].Value })
}

Export-ModuleMember -Function Get-ArqenRepoRoot,Get-ArqenGeneratedDir,ConvertTo-ArqenRelativePath,Read-ArqenCommandSpec,Get-ArqenCommandSpecs,Get-ArqenSpecValue,Test-ArqenReferencedPath,Get-ArqenKeywordTokens
