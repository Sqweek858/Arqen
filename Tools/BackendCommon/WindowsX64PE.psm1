function New-ArqCheck {
    param(
        [bool]$Ok,
        [string]$Code = "",
        [string]$Message = ""
    )

    [pscustomobject]@{
        Ok = $Ok
        Code = $Code
        Message = $Message
    }
}

function Read-ArqKeyValueFile {
    param([string]$Path)

    $result = @{}
    if (-not (Test-Path $Path)) {
        return $result
    }

    foreach ($line in Get-Content $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $parts = $line.Split([char]"|", 2)
        if ($parts.Length -eq 2) {
            $result[$parts[0]] = $parts[1]
        }
    }
    return $result
}

function Convert-ArqNumber {
    param([string]$Value)

    if ($Value.StartsWith("0x")) {
        return [Convert]::ToInt64($Value.Substring(2), 16)
    }
    return [Convert]::ToInt64($Value, 10)
}

function Get-ArqFileSha256 {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return ""
    }
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Get-ArqPeInfo {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "file not found"
    }

    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 512) {
        throw "file too small"
    }

    function U16([int]$Offset) { [BitConverter]::ToUInt16($bytes, $Offset) }
    function U32([int]$Offset) { [BitConverter]::ToUInt32($bytes, $Offset) }
    function U64([int]$Offset) { [BitConverter]::ToUInt64($bytes, $Offset) }

    if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw "missing MZ signature"
    }

    $peOffset = U32 0x3C
    if ($peOffset -le 0 -or ($peOffset + 0x108) -ge $bytes.Length) {
        throw "invalid PE offset"
    }

    if ((U32 $peOffset) -ne 0x00004550) {
        throw "missing PE signature"
    }

    $coff = $peOffset + 4
    $machine = U16 ($coff + 0)
    $sectionsCount = U16 ($coff + 2)
    $optionalSize = U16 ($coff + 16)
    $optional = $coff + 20
    $magic = U16 $optional
    $entryRva = U32 ($optional + 16)
    $imageBase = if ($magic -eq 0x20B) { U64 ($optional + 24) } else { U32 ($optional + 28) }
    $sectionAlignment = U32 ($optional + 32)
    $fileAlignment = U32 ($optional + 36)
    $importRva = if ($magic -eq 0x20B) { U32 ($optional + 112 + 8) } else { U32 ($optional + 96 + 8) }
    $sectionOffset = $optional + $optionalSize
    $sections = @()

    for ($i = 0; $i -lt $sectionsCount; $i++) {
        $offset = $sectionOffset + (40 * $i)
        if (($offset + 40) -gt $bytes.Length) {
            throw "section table outside file"
        }
        $name = ([Text.Encoding]::ASCII.GetString($bytes, $offset, 8)).Trim([char]0)
        $sections += [pscustomobject]@{
            Name = $name
            VirtualSize = U32 ($offset + 8)
            VirtualAddress = U32 ($offset + 12)
            RawSize = U32 ($offset + 16)
            RawPointer = U32 ($offset + 20)
            Characteristics = U32 ($offset + 36)
        }
    }

    [pscustomobject]@{
        Bytes = $bytes
        Size = $bytes.Length
        Machine = $machine
        Magic = $magic
        ImageBase = $imageBase
        EntryRva = $entryRva
        SectionAlignment = $sectionAlignment
        FileAlignment = $fileAlignment
        ImportRva = $importRva
        Sections = $sections
    }
}

function Test-ArqPeTemplate {
    param(
        [string]$Path,
        [string]$LayoutPath,
        [string]$ImportRegistryPath
    )

    try {
        $info = Get-ArqPeInfo $Path
    } catch {
        return New-ArqCheck $false "B002" "template validation failed: $($_.Exception.Message)"
    }

    $layout = Read-ArqKeyValueFile $LayoutPath
    if ($info.Machine -ne 0x8664) {
        return New-ArqCheck $false "B002" "template machine is not AMD64"
    }
    if ($info.Magic -ne 0x20B) {
        return New-ArqCheck $false "B002" "template is not PE32+"
    }
    if ($layout.ContainsKey("IMAGE_BASE") -and $info.ImageBase -ne (Convert-ArqNumber $layout["IMAGE_BASE"])) {
        return New-ArqCheck $false "B002" "template image base mismatch"
    }

    $text = $info.Sections | Where-Object { $_.Name -eq ".text" } | Select-Object -First 1
    $rdata = $info.Sections | Where-Object { $_.Name -eq ".rdata" } | Select-Object -First 1
    $idata = $info.Sections | Where-Object { $_.Name -eq ".idata" } | Select-Object -First 1
    if ($null -eq $text -or (($text.Characteristics -band 0x60000000) -ne 0x60000000)) {
        return New-ArqCheck $false "B002" "template .text is not executable/readable"
    }
    if ($null -eq $rdata -or (($rdata.Characteristics -band 0x40000000) -ne 0x40000000)) {
        return New-ArqCheck $false "B002" "template .rdata is not readable"
    }
    if ($null -eq $idata -or (($idata.Characteristics -band 0x40000000) -ne 0x40000000)) {
        return New-ArqCheck $false "B002" "template .idata is not readable"
    }
    if ($info.ImportRva -eq 0) {
        return New-ArqCheck $false "B002" "template import table is missing"
    }

    $ascii = [Text.Encoding]::ASCII.GetString($info.Bytes)
    foreach ($line in Get-Content $ImportRegistryPath) {
        $parts = $line.Split([char]"|")
        if ($parts.Length -lt 3 -or $parts[2] -ne "required") {
            continue
        }
        if (-not $ascii.Contains($parts[0]) -or -not $ascii.Contains($parts[1])) {
            return New-ArqCheck $false "B005" "missing import $($parts[0])!$($parts[1])"
        }
    }

    return New-ArqCheck $true
}

function Test-ArqPeArtifact {
    param(
        [string]$Path,
        [string]$ImportRegistryPath
    )

    if (-not (Test-Path $Path)) {
        return New-ArqCheck $false "B007" "artifact file missing"
    }
    if ((Get-Item $Path).Length -le 0) {
        return New-ArqCheck $false "B007" "artifact file empty"
    }

    try {
        $info = Get-ArqPeInfo $Path
    } catch {
        return New-ArqCheck $false "B007" "artifact PE verification failed: $($_.Exception.Message)"
    }

    if ($info.EntryRva -eq 0) {
        return New-ArqCheck $false "B007" "artifact entry point missing"
    }

    $ascii = [Text.Encoding]::ASCII.GetString($info.Bytes)
    if ($ascii.Contains("GetStdHandle") -or $ascii.Contains("WriteFile")) {
        foreach ($required in @("kernel32.dll", "ExitProcess", "GetStdHandle", "WriteFile")) {
            if (-not $ascii.Contains($required)) {
                return New-ArqCheck $false "B005" "artifact missing stdout import $required"
            }
        }
        return New-ArqCheck $true
    }

    foreach ($line in Get-Content $ImportRegistryPath) {
        $parts = $line.Split("|")
        if ($parts.Length -lt 3 -or $parts[2] -ne "required") {
            continue
        }
        if (-not $ascii.Contains($parts[0]) -or -not $ascii.Contains($parts[1])) {
            return New-ArqCheck $false "B005" "artifact missing import $($parts[0])!$($parts[1])"
        }
    }

    return New-ArqCheck $true
}

function Split-ArqIrLine {
    param([string]$Line)

    return $Line.Split([char]"|")
}

function Get-ArqIrModel {
    param([string]$Path)

    $consts = @{}
    $actions = @()
    $source = ""

    if (-not (Test-Path $Path)) {
        return [pscustomobject]@{ Source = ""; Consts = $consts; Actions = $actions }
    }

    foreach ($line in Get-Content $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $parts = Split-ArqIrLine $line
        $kind = $parts[0]
        $fields = @{}
        for ($i = 1; $i -lt $parts.Length; $i++) {
            $part = [string]$parts[$i]
            $at = $part.IndexOf("=")
            if ($at -gt 0) {
                $fields[$part.Substring(0, $at)] = $part.Substring($at + 1)
            }
        }
        if ($kind -eq "META" -and $fields.ContainsKey("source")) {
            $source = $fields["source"]
        } elseif ($kind -eq "CONST") {
            $consts[$fields["id"]] = [pscustomobject]@{ Type = $fields["type"]; Value = $fields["value"] }
        } elseif ($kind -eq "ACTION") {
            $actions += [pscustomobject]$fields
        }
    }

    [pscustomobject]@{
        Source = $source
        Consts = $consts
        Actions = $actions
    }
}

function Test-ArqBackendCapabilities {
    param(
        [string]$IrPath,
        [string]$CapabilitiesPath
    )

    $capabilities = @{}
    foreach ($line in Get-Content $CapabilitiesPath) {
        $parts = $line.Split([char]"|")
        if ($parts.Length -eq 2) {
            $capabilities[$parts[0]] = $parts[1]
        }
    }

    $ir = Get-ArqIrModel $IrPath
    foreach ($action in $ir.Actions) {
        $op = $action.op
        if (-not $capabilities.ContainsKey($op) -or $capabilities[$op] -ne "supported") {
            return New-ArqCheck $false "B001" "unsupported backend action: $op"
        }
    }

    return New-ArqCheck $true
}

function Test-ArqRDataPlan {
    param(
        [string]$IrPath,
        [string]$LayoutPath
    )

    $layout = Read-ArqKeyValueFile $LayoutPath
    $slotBytes = if ($layout.ContainsKey("STRING_SLOT_BYTES")) { Convert-ArqNumber $layout["STRING_SLOT_BYTES"] } else { 64 }
    $ir = Get-ArqIrModel $IrPath

    foreach ($action in $ir.Actions) {
        if ($action.op -ne "show_message") {
            continue
        }
        foreach ($field in @("title", "text")) {
            $id = $action.$field
            if (-not $ir.Consts.ContainsKey($id)) {
                return New-ArqCheck $false "B003" "rdata constant missing: $id"
            }
            $value = $ir.Consts[$id].Value
            $bytes = [Text.Encoding]::Unicode.GetByteCount($value + [char]0)
            if ($bytes -gt $slotBytes) {
                return New-ArqCheck $false "B003" "rdata overflow for $field"
            }
        }
    }

    return New-ArqCheck $true
}

Export-ModuleMember -Function Read-ArqKeyValueFile,Convert-ArqNumber,Get-ArqFileSha256,Get-ArqPeInfo,Test-ArqPeTemplate,Test-ArqPeArtifact,Get-ArqIrModel,Test-ArqBackendCapabilities,Test-ArqRDataPlan
