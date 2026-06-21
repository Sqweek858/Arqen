param(
    [int[]]$RunCounts = @(1, 8, 16, 32, 64, 128, 256, 1024, 4096),
    [int[]]$CompileOnlyCounts = @(),
    [int[]]$CoreRunCounts = @(64, 1024, 4096),
    [int[]]$CoreCompileOnlyCounts = @(),
    [int[]]$HugeRunCounts = @(64, 1024, 4096),
    [int[]]$HugeCompileOnlyCounts = @(),
    [switch]$MillionScale,
    [int]$FullContentCheckMaxCount = 4096,
    [int]$LoadPrintMaxCount = 64,
    [int]$TimeoutSeconds = 30,
    [switch]$NoBuildDriver
)

$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$BuildRoot = Join-Path $RepoRoot "Build"
$StressRoot = Join-Path $BuildRoot "RuntimeStress"
$SourceRoot = Join-Path $StressRoot "Sources"
$BinRoot = Join-Path $StressRoot "Bin"
$RunRoot = Join-Path $StressRoot "Run"
$LogRoot = Join-Path $StressRoot "Logs"
$GeneratedRoot = Join-Path $BuildRoot "Generated"
$OutPath = Join-Path $GeneratedRoot "m33a_m33b_windows_x64_runtime_stress_validation.txt"

foreach ($dir in @($SourceRoot, $BinRoot, $RunRoot, $LogRoot, $GeneratedRoot)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$script:Failed = $false
$script:Lines = New-Object System.Collections.Generic.List[string]

if ($MillionScale) {
    if (-not $PSBoundParameters.ContainsKey("RunCounts")) { $RunCounts = @(1, 8, 16, 32, 64, 128, 256, 1024, 4096, 65536, 1048576) }
    if (-not $PSBoundParameters.ContainsKey("CompileOnlyCounts")) { $CompileOnlyCounts = @() }
    if (-not $PSBoundParameters.ContainsKey("CoreRunCounts")) { $CoreRunCounts = @(64, 1024, 4096, 65536, 1048576) }
    if (-not $PSBoundParameters.ContainsKey("CoreCompileOnlyCounts")) { $CoreCompileOnlyCounts = @() }
    if (-not $PSBoundParameters.ContainsKey("HugeRunCounts")) { $HugeRunCounts = @(64, 1024, 4096, 65536, 1048576) }
    if (-not $PSBoundParameters.ContainsKey("HugeCompileOnlyCounts")) { $HugeCompileOnlyCounts = @() }
    if (-not $PSBoundParameters.ContainsKey("TimeoutSeconds")) { $TimeoutSeconds = 180 }
}

function Emit-Check {
    param([string]$Name, [bool]$Ok, [string]$Message = "")
    $line = if ($Ok) { "PASS|$Name|$Message" } else { "FAIL|$Name|$Message" }
    Write-Host $line
    $script:Lines.Add($line) | Out-Null
    if (-not $Ok) { $script:Failed = $true }
}

function Rel-Path {
    param([string]$Path)
    $root = ([IO.Path]::GetFullPath($RepoRoot)).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length).Replace("\\", "/")
    }
    return $full.Replace("\\", "/")
}

function Join-ProcessArguments {
    param([string[]]$Arguments = @())
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($argValue in $Arguments) {
        $arg = if ($null -eq $argValue) { "" } else { [string]$argValue }
        if ($arg.Length -gt 0 -and $arg -notmatch '[\s"]') {
            $parts.Add($arg) | Out-Null
            continue
        }

        $builder = [Text.StringBuilder]::new()
        [void]$builder.Append('"')
        $backslashes = 0
        foreach ($ch in $arg.ToCharArray()) {
            if ($ch -eq '\\') {
                $backslashes++
                continue
            }
            if ($ch -eq '"') {
                if ($backslashes -gt 0) { [void]$builder.Append(('\\' * ($backslashes * 2))) }
                [void]$builder.Append('\\"')
                $backslashes = 0
                continue
            }
            if ($backslashes -gt 0) {
                [void]$builder.Append(('\\' * $backslashes))
                $backslashes = 0
            }
            [void]$builder.Append($ch)
        }
        if ($backslashes -gt 0) { [void]$builder.Append(('\\' * ($backslashes * 2))) }
        [void]$builder.Append('"')
        $parts.Add($builder.ToString()) | Out-Null
    }
    return [string]::Join(' ', $parts)
}

function Invoke-DriverBuild {
    if ($NoBuildDriver) {
        Emit-Check "m33a_driver_build" $true "skipped by -NoBuildDriver"
        return
    }
    Push-Location $RepoRoot
    try {
        dotnet publish ".\Tools\M10GDriver\ArqcM10G.csproj" -c Release -o ".\Tools\M10GDriver\publish" *> (Join-Path $LogRoot "driver_publish.log")
        if ($LASTEXITCODE -ne 0) {
            Emit-Check "m33a_driver_build" $false "dotnet publish failed; see $(Rel-Path (Join-Path $LogRoot 'driver_publish.log'))"
            return
        }
        Copy-Item ".\Tools\M10GDriver\publish\arqc_m10g.exe" ".\Tools\arqc_m10g.exe" -Force
        Emit-Check "m33a_driver_build" $true "arqc_m10g.exe rebuilt before runtime execution tests"
    } finally {
        Pop-Location
    }
}

function Write-StressSource {
    param(
        [int]$Count,
        [bool]$LoadAndPrint
    )

    $name = "StressFileAppend$Count"
    $fileName = "stress_file_append_$Count.txt"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("program `"$name`"") | Out-Null
    $lines.Add("") | Out-Null
    if ($LoadAndPrint) {
        $lines.Add("define string called `"content`" be string `"`"") | Out-Null
    }
    $lines.Add("write file `"$fileName`" with string `"start`"") | Out-Null
    for ($i = 1; $i -le $Count; $i++) {
        $lines.Add(("add string `"\nappend line {0:D6}`" to file `"$fileName`"" -f $i)) | Out-Null
    }
    if ($LoadAndPrint) {
        $lines.Add("load file `"$fileName`" to `"content`"") | Out-Null
        $lines.Add("print `"content`"") | Out-Null
    }
    $lines.Add("blend mix to code 0") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("end program `"$name`"") | Out-Null

    $path = Join-Path $SourceRoot "stress_file_append_$Count.arq"
    [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false))
    return $path
}

function Get-ExpectedContent {
    param([int]$Count)
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append("start")
    for ($i = 1; $i -le $Count; $i++) { [void]$sb.Append(("`nappend line {0:D6}" -f $i)) }
    return $sb.ToString()
}

function Get-PeInfo {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 512) { throw "PE too small" }
    function U16([int]$o) { [BitConverter]::ToUInt16($bytes, $o) }
    function U32([int]$o) { [BitConverter]::ToUInt32($bytes, $o) }
    if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw "missing MZ" }
    $pe = U32 0x3C
    if ((U32 $pe) -ne 0x4550) { throw "missing PE" }
    $coff = $pe + 4
    $optionalSize = U16 ($coff + 16)
    $optional = $coff + 20
    $entryRva = U32 ($optional + 16)
    $imageSize = U32 ($optional + 56)
    $sectionOffset = $optional + $optionalSize
    $sectionName = ([Text.Encoding]::ASCII.GetString($bytes, $sectionOffset, 8)).Trim([char]0)
    [pscustomobject]@{
        Size = $bytes.Length
        EntryRva = $entryRva
        ImageSize = $imageSize
        SectionName = $sectionName
        SectionVirtualSize = U32 ($sectionOffset + 8)
        SectionVirtualAddress = U32 ($sectionOffset + 12)
        SectionRawSize = U32 ($sectionOffset + 16)
        SectionRawPointer = U32 ($sectionOffset + 20)
    }
}

function Invoke-ExeWithTimeout {
    param(
        [string]$ExePath,
        [string]$WorkingDirectory,
        [int]$Timeout,
        [string[]]$Arguments = @()
    )

    $stdoutPath = Join-Path $LogRoot (([IO.Path]::GetFileNameWithoutExtension($ExePath)) + ".stdout.txt")
    $stderrPath = Join-Path $LogRoot (([IO.Path]::GetFileNameWithoutExtension($ExePath)) + ".stderr.txt")
    Remove-Item -Force -ErrorAction SilentlyContinue $stdoutPath, $stderrPath

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $ExePath
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $argList = $null
    try { $argList = $psi.ArgumentList } catch { $argList = $null }
    if ($null -ne $argList) {
        foreach ($arg in $Arguments) { [void]$argList.Add($arg) }
    } else {
        $psi.Arguments = Join-ProcessArguments $Arguments
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
    } catch {
        $message = $_.Exception.Message
        [IO.File]::WriteAllText($stdoutPath, "", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($stderrPath, $message, [Text.UTF8Encoding]::new($false))
        return [pscustomobject]@{ ExitCode = $null; TimedOut = $false; StartFailed = $true; Stdout = ""; Stderr = $message; StdoutPath = $stdoutPath; StderrPath = $stderrPath }
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $finished = $process.WaitForExit($Timeout * 1000)
    if (-not $finished) {
        try { $process.Kill() } catch { }
        try { [void]$process.WaitForExit(2000) } catch { }
        $stdout = try { $stdoutTask.Result } catch { "" }
        $stderr = try { $stderrTask.Result } catch { "" }
        [IO.File]::WriteAllText($stdoutPath, $stdout, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($stderrPath, $stderr, [Text.UTF8Encoding]::new($false))
        return [pscustomobject]@{ ExitCode = $null; TimedOut = $true; StartFailed = $false; Stdout = $stdout; Stderr = $stderr; StdoutPath = $stdoutPath; StderrPath = $stderrPath }
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    [IO.File]::WriteAllText($stdoutPath, $stdout, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($stderrPath, $stderr, [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ ExitCode = $process.ExitCode; TimedOut = $false; StartFailed = $false; Stdout = $stdout; Stderr = $stderr; StdoutPath = $stdoutPath; StderrPath = $stderrPath }
}

Invoke-DriverBuild

$driverPath = Join-Path $RepoRoot "Tools\arqc_m10g.exe"
Emit-Check "m33a_driver_exists" (Test-Path $driverPath) "$(Rel-Path $driverPath)"

function Test-StressCase {
    param(
        [int]$Count,
        [bool]$RunCase,
        [bool]$LoadAndPrint
    )

    $sourcePath = Write-StressSource $Count $LoadAndPrint
    $exePath = Join-Path $BinRoot "stress_file_append_$Count.exe"
    $caseRunRoot = Join-Path $RunRoot "stress_file_append_$Count"
    New-Item -ItemType Directory -Force -Path $caseRunRoot | Out-Null
    Get-ChildItem $caseRunRoot -Force | Remove-Item -Recurse -Force

    Push-Location $RepoRoot
    try {
        & $driverPath $sourcePath -o $exePath *> (Join-Path $LogRoot "stress_file_append_$Count.build.log")
        $buildExit = if ($null -eq $LASTEXITCODE) { if ($?) { 0 } else { 1 } } else { $LASTEXITCODE }
    } finally {
        Pop-Location
    }
    Emit-Check "m33a_build_stress_file_append_$Count" ($buildExit -eq 0 -and (Test-Path $exePath)) "exit=$buildExit artifact=$(Rel-Path $exePath)"
    if ($buildExit -ne 0 -or -not (Test-Path $exePath)) { return }

    try {
        $pe = Get-PeInfo $exePath
        $layoutOk = ($pe.SectionName -eq ".text" -and $pe.SectionVirtualSize -ge 0x100000 -and $pe.SectionRawSize -ge 0x100000 -and $pe.ImageSize -ge 0x101000)
        Emit-Check "m33b_pe_layout_stress_file_append_$Count" $layoutOk ("section={0} virtual=0x{1:X} raw=0x{2:X} image=0x{3:X} file_bytes={4}" -f $pe.SectionName, $pe.SectionVirtualSize, $pe.SectionRawSize, $pe.ImageSize, $pe.Size)
    } catch {
        Emit-Check "m33b_pe_layout_stress_file_append_$Count" $false $_.Exception.Message
        return
    }

    if (-not $RunCase) {
        Emit-Check "m33a_compile_only_stress_file_append_$Count" $true "compiled and PE layout checked; runtime skipped intentionally"
        return
    }

    $run = Invoke-ExeWithTimeout $exePath $caseRunRoot $TimeoutSeconds
    $exitOk = (-not $run.TimedOut -and $run.ExitCode -eq 0)
    $exitNote = if ($run.TimedOut) { "timeout=${TimeoutSeconds}s" } elseif ($run.StartFailed) { "start_failed=$($run.Stderr)" } else { "exit=$($run.ExitCode)" }
    if (-not $exitOk -and $run.ExitCode -eq -1073741819) { $exitNote += " access_violation=0xC0000005" }
    Emit-Check "m33a_run_stress_file_append_$Count" $exitOk $exitNote
    if (-not $exitOk) { return }

    $actualPath = Join-Path $caseRunRoot "stress_file_append_$Count.txt"
    $actualExists = Test-Path $actualPath
    Emit-Check "m33b_file_exists_stress_file_append_$Count" $actualExists "$(Rel-Path $actualPath)"
    if (-not $actualExists) { return }

    if ($Count -le $FullContentCheckMaxCount) {
        $expected = Get-ExpectedContent $Count
        $actual = [IO.File]::ReadAllText($actualPath, [Text.Encoding]::UTF8)
        Emit-Check "m33b_file_content_stress_file_append_$Count" ($actual -eq $expected) "bytes=$([Text.Encoding]::UTF8.GetByteCount($actual)) expected_bytes=$([Text.Encoding]::UTF8.GetByteCount($expected))"
        if ($LoadAndPrint) {
            $stdoutExpected = $expected + "`n"
            Emit-Check "m33a_stdout_stress_file_append_$Count" ($run.Stdout -eq $stdoutExpected) "stdout=$(Rel-Path $run.StdoutPath)"
        } else {
            Emit-Check "m33a_stdout_empty_stress_file_append_$Count" ($run.Stdout -eq "") "stdout=$(Rel-Path $run.StdoutPath)"
        }
    } else {
        $expectedBytes = [Text.Encoding]::UTF8.GetByteCount((Get-ExpectedContent $Count))
        $actualBytes = (Get-Item $actualPath).Length
        Emit-Check "m33b_file_size_stress_file_append_$Count" ($actualBytes -eq $expectedBytes) "bytes=$actualBytes expected_bytes=$expectedBytes"
    }
}


function Write-PrintOnlySource {
    param([int]$Count)
    $name = "StressPrintOnly$Count"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("program `"$name`"") | Out-Null
    $lines.Add("") | Out-Null
    for ($i = 1; $i -le $Count; $i++) {
        $lines.Add(("print string `"print line {0:D6}`"" -f $i)) | Out-Null
    }
    $lines.Add("write file `"stress_print_$Count.touch.txt`" with string `"ok`"") | Out-Null
    $lines.Add("blend mix to code 0") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("end program `"$name`"") | Out-Null
    $path = Join-Path $SourceRoot "stress_print_only_$Count.arq"
    [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false))
    return $path
}

function Get-PrintOnlyExpected {
    param([int]$Count)
    $sb = [Text.StringBuilder]::new()
    for ($i = 1; $i -le $Count; $i++) {
        [void]$sb.Append(("print line {0:D6}`n" -f $i))
    }
    return $sb.ToString()
}

function Write-ArgsSource {
    param([int]$Count)
    $name = "StressArgs$Count"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("program `"$name`"") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("define int called `"argc`" be command arg count") | Out-Null
    for ($i = 0; $i -lt $Count; $i++) {
        $lines.Add(("define string called `"arg{0}`" be command arg {0}" -f $i)) | Out-Null
    }
    $lines.Add("print `"argc`"") | Out-Null
    for ($i = 0; $i -lt $Count; $i++) {
        $lines.Add(("print `"arg{0}`"" -f $i)) | Out-Null
    }
    $lines.Add("blend mix to code 0") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("end program `"$name`"") | Out-Null
    $path = Join-Path $SourceRoot "stress_args_$Count.arq"
    [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false))
    return $path
}

function Get-ArgsList {
    param([int]$Count)
    $caseArgs = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Count; $i++) {
        if ($Count -le 256) {
            $caseArgs.Add(("ARG {0:D3}" -f ($i + 1))) | Out-Null
        } else {
            $caseArgs.Add(("A{0:D4}" -f ($i + 1))) | Out-Null
        }
    }
    return [string[]]$caseArgs.ToArray()
}

function Get-ArgsExpectedStdout {
    param([string[]]$CaseArgs)
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append($CaseArgs.Count.ToString())
    [void]$sb.Append("`n")
    foreach ($caseArg in $CaseArgs) {
        [void]$sb.Append($caseArg)
        [void]$sb.Append("`n")
    }
    return $sb.ToString()
}

function Write-MixedNoArgsSource {
    param([int]$Count)
    $name = "StressMixedNoArgs$Count"
    $fileName = "stress_mixed_no_args_$Count.txt"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("program `"$name`"") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("define string called `"content`" be string `"`"") | Out-Null
    $lines.Add("print string `"mixed no args start`"") | Out-Null
    $lines.Add("write file `"$fileName`" with string `"start`"") | Out-Null
    for ($i = 1; $i -le $Count; $i++) {
        $lines.Add(("add string `"\nappend line {0:D3}`" to file `"$fileName`"" -f $i)) | Out-Null
    }
    $lines.Add("load file `"$fileName`" to `"content`"") | Out-Null
    $lines.Add("print `"content`"") | Out-Null
    $lines.Add("print string `"mixed no args end`"") | Out-Null
    $lines.Add("blend mix to code 0") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("end program `"$name`"") | Out-Null
    $path = Join-Path $SourceRoot "stress_mixed_no_args_$Count.arq"
    [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false))
    return $path
}

function Get-MixedNoArgsContent {
    param([int]$Count)
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append("start")
    for ($i = 1; $i -le $Count; $i++) { [void]$sb.Append(("`nappend line {0:D3}" -f $i)) }
    return $sb.ToString()
}

function Write-ArgsFileSource {
    param([int]$Count)
    $name = "StressArgsFile$Count"
    $fileName = "stress_args_file_$Count.txt"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("program `"$name`"") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("define string called `"arg0`" be command arg 0") | Out-Null
    $lines.Add("define string called `"content`" be string `"`"") | Out-Null
    $lines.Add("print string `"args file start`"") | Out-Null
    $lines.Add("write file `"$fileName`" with string `"Arg: `"") | Out-Null
    $lines.Add("add `"arg0`" to file `"$fileName`"") | Out-Null
    for ($i = 1; $i -le $Count; $i++) {
        $lines.Add(("add string `"\nfile line {0:D3}`" to file `"$fileName`"" -f $i)) | Out-Null
    }
    $lines.Add("load file `"$fileName`" to `"content`"") | Out-Null
    $lines.Add("print `"content`"") | Out-Null
    $lines.Add("print string `"args file end`"") | Out-Null
    $lines.Add("blend mix to code 0") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("end program `"$name`"") | Out-Null
    $path = Join-Path $SourceRoot "stress_args_file_$Count.arq"
    [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false))
    return $path
}

function Get-ArgsFileContent {
    param([int]$Count, [string]$Arg0)
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append("Arg: ")
    [void]$sb.Append($Arg0)
    for ($i = 1; $i -le $Count; $i++) { [void]$sb.Append(("`nfile line {0:D3}" -f $i)) }
    return $sb.ToString()
}


function Invoke-CoreCompileOnlyCase {
    param(
        [string]$CaseName,
        [string]$SourcePath
    )

    $exePath = Join-Path $BinRoot "$CaseName.exe"
    Push-Location $RepoRoot
    try {
        & $driverPath $SourcePath -o $exePath *> (Join-Path $LogRoot "$CaseName.build.log")
        $buildExit = if ($null -eq $LASTEXITCODE) { if ($?) { 0 } else { 1 } } else { $LASTEXITCODE }
    } finally {
        Pop-Location
    }
    Emit-Check "m33d_build_$CaseName" ($buildExit -eq 0 -and (Test-Path $exePath)) "exit=$buildExit artifact=$(Rel-Path $exePath)"
    if ($buildExit -ne 0 -or -not (Test-Path $exePath)) { return }

    try {
        $pe = Get-PeInfo $exePath
        $layoutOk = ($pe.SectionName -eq ".text" -and $pe.SectionVirtualSize -ge 0x1000 -and $pe.SectionRawSize -ge 0x1000 -and $pe.ImageSize -ge 0x2000)
        Emit-Check "m33d_pe_layout_$CaseName" $layoutOk ("section={0} virtual=0x{1:X} raw=0x{2:X} image=0x{3:X} file_bytes={4}" -f $pe.SectionName, $pe.SectionVirtualSize, $pe.SectionRawSize, $pe.ImageSize, $pe.Size)
        if ($layoutOk) { Emit-Check "m33d_compile_only_$CaseName" $true "compiled and PE layout checked; runtime skipped intentionally" }
    } catch {
        Emit-Check "m33d_pe_layout_$CaseName" $false $_.Exception.Message
        return
    }
}

function Invoke-CoreRuntimeCase {
    param(
        [string]$CaseName,
        [string]$SourcePath,
        [string[]]$Arguments = @(),
        [string]$ExpectedStdout = "",
        [hashtable]$ExpectedFiles = @{}
    )

    $exePath = Join-Path $BinRoot "$CaseName.exe"
    $caseRunRoot = Join-Path $RunRoot $CaseName
    New-Item -ItemType Directory -Force -Path $caseRunRoot | Out-Null
    Get-ChildItem $caseRunRoot -Force | Remove-Item -Recurse -Force

    Push-Location $RepoRoot
    try {
        & $driverPath $SourcePath -o $exePath *> (Join-Path $LogRoot "$CaseName.build.log")
        $buildExit = if ($null -eq $LASTEXITCODE) { if ($?) { 0 } else { 1 } } else { $LASTEXITCODE }
    } finally {
        Pop-Location
    }
    Emit-Check "m33d_build_$CaseName" ($buildExit -eq 0 -and (Test-Path $exePath)) "exit=$buildExit artifact=$(Rel-Path $exePath)"
    if ($buildExit -ne 0 -or -not (Test-Path $exePath)) { return }

    try {
        $pe = Get-PeInfo $exePath
        $layoutOk = ($pe.SectionName -eq ".text" -and $pe.SectionVirtualSize -ge 0x1000 -and $pe.SectionRawSize -ge 0x1000 -and $pe.ImageSize -ge 0x2000)
        Emit-Check "m33d_pe_layout_$CaseName" $layoutOk ("section={0} virtual=0x{1:X} raw=0x{2:X} image=0x{3:X} file_bytes={4}" -f $pe.SectionName, $pe.SectionVirtualSize, $pe.SectionRawSize, $pe.ImageSize, $pe.Size)
    } catch {
        Emit-Check "m33d_pe_layout_$CaseName" $false $_.Exception.Message
        return
    }

    $run = Invoke-ExeWithTimeout $exePath $caseRunRoot $TimeoutSeconds $Arguments
    $exitOk = (-not $run.TimedOut -and $run.ExitCode -eq 0)
    $exitNote = if ($run.TimedOut) { "timeout=${TimeoutSeconds}s" } elseif ($run.StartFailed) { "start_failed=$($run.Stderr)" } else { "exit=$($run.ExitCode)" }
    if (-not $exitOk -and $run.ExitCode -eq -1073741819) { $exitNote += " access_violation=0xC0000005" }
    Emit-Check "m33d_run_$CaseName" $exitOk $exitNote
    if (-not $exitOk) { return }

    Emit-Check "m33d_stdout_$CaseName" ($run.Stdout -eq $ExpectedStdout) "stdout=$(Rel-Path $run.StdoutPath) bytes=$([Text.Encoding]::UTF8.GetByteCount($run.Stdout)) expected_bytes=$([Text.Encoding]::UTF8.GetByteCount($ExpectedStdout))"

    foreach ($relativeName in $ExpectedFiles.Keys) {
        $actualPath = Join-Path $caseRunRoot $relativeName
        $actualExists = Test-Path $actualPath
        Emit-Check "m33d_file_exists_${CaseName}_$relativeName" $actualExists "$(Rel-Path $actualPath)"
        if ($actualExists) {
            $actual = [IO.File]::ReadAllText($actualPath, [Text.Encoding]::UTF8)
            $expected = [string]$ExpectedFiles[$relativeName]
            Emit-Check "m33d_file_content_${CaseName}_$relativeName" ($actual -eq $expected) "bytes=$([Text.Encoding]::UTF8.GetByteCount($actual)) expected_bytes=$([Text.Encoding]::UTF8.GetByteCount($expected))"
        }
    }
}


function Write-LoadPrintSource {
    param([int]$Count)
    $name = "StressLoadPrint$Count"
    $fileName = "stress_load_print_$Count.txt"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("program `"$name`"") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("define string called `"content`" be string `"`"") | Out-Null
    $lines.Add("write file `"$fileName`" with string `"load start`"") | Out-Null
    for ($i = 1; $i -le $Count; $i++) {
        $lines.Add(("add string `"\nload line {0:D6}`" to file `"$fileName`"" -f $i)) | Out-Null
    }
    $lines.Add("load file `"$fileName`" to `"content`"") | Out-Null
    $lines.Add("print `"content`"") | Out-Null
    $lines.Add("blend mix to code 0") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("end program `"$name`"") | Out-Null
    $path = Join-Path $SourceRoot "stress_load_print_$Count.arq"
    [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false))
    return $path
}

function Get-LoadPrintContent {
    param([int]$Count)
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append("load start")
    for ($i = 1; $i -le $Count; $i++) { [void]$sb.Append(("`nload line {0:D6}" -f $i)) }
    return $sb.ToString()
}

function Write-SlotRoundtripSource {
    param([int]$Count)
    $name = "StressSlotRoundtrip$Count"
    $sourceFile = "stress_slot_roundtrip_$Count.input.txt"
    $copyFile = "stress_slot_roundtrip_$Count.copy.txt"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("program `"$name`"") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("define string called `"content`" be string `"`"") | Out-Null
    $lines.Add("define string called `"copy`" be string `"`"") | Out-Null
    $lines.Add("write file `"$sourceFile`" with string `"roundtrip start`"") | Out-Null
    for ($i = 1; $i -le $Count; $i++) {
        $lines.Add(("add string `"\nroundtrip line {0:D6}`" to file `"$sourceFile`"" -f $i)) | Out-Null
    }
    $lines.Add("load file `"$sourceFile`" to `"content`"") | Out-Null
    $lines.Add("write file `"$copyFile`" with string `"copy:`"") | Out-Null
    $lines.Add("add string `"\n`" to file `"$copyFile`"") | Out-Null
    $lines.Add("add `"content`" to file `"$copyFile`"") | Out-Null
    $lines.Add("load file `"$copyFile`" to `"copy`"") | Out-Null
    $lines.Add("print `"copy`"") | Out-Null
    $lines.Add("blend mix to code 0") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("end program `"$name`"") | Out-Null
    $path = Join-Path $SourceRoot "stress_slot_roundtrip_$Count.arq"
    [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false))
    return $path
}

function Get-SlotRoundtripInputContent {
    param([int]$Count)
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append("roundtrip start")
    for ($i = 1; $i -le $Count; $i++) { [void]$sb.Append(("`nroundtrip line {0:D6}" -f $i)) }
    return $sb.ToString()
}

function Write-TwoFilesSource {
    param([int]$Count)
    $name = "StressTwoFiles$Count"
    $fileA = "stress_two_files_$Count.a.txt"
    $fileB = "stress_two_files_$Count.b.txt"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("program `"$name`"") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("define string called `"a`" be string `"`"") | Out-Null
    $lines.Add("define string called `"b`" be string `"`"") | Out-Null
    $lines.Add("write file `"$fileA`" with string `"A start`"") | Out-Null
    $lines.Add("write file `"$fileB`" with string `"B start`"") | Out-Null
    for ($i = 1; $i -le $Count; $i++) {
        $lines.Add(("add string `"\nA line {0:D6}`" to file `"$fileA`"" -f $i)) | Out-Null
    }
    for ($i = 1; $i -le $Count; $i++) {
        $lines.Add(("add string `"\nB line {0:D6}`" to file `"$fileB`"" -f $i)) | Out-Null
    }
    $lines.Add("load file `"$fileA`" to `"a`"") | Out-Null
    $lines.Add("load file `"$fileB`" to `"b`"") | Out-Null
    $lines.Add("print `"a`"") | Out-Null
    $lines.Add("print `"b`"") | Out-Null
    $lines.Add("blend mix to code 0") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("end program `"$name`"") | Out-Null
    $path = Join-Path $SourceRoot "stress_two_files_$Count.arq"
    [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false))
    return $path
}

function Get-TwoFilesContent {
    param([int]$Count, [string]$Prefix)
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append("$Prefix start")
    for ($i = 1; $i -le $Count; $i++) { [void]$sb.Append(("`n$Prefix line {0:D6}" -f $i)) }
    return $sb.ToString()
}

function Write-OrderMarkersSource {
    param([int]$Count)
    $name = "StressOrderMarkers$Count"
    $fileName = "stress_order_markers_$Count.txt"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("program `"$name`"") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("define string called `"content`" be string `"`"") | Out-Null

    $markerText = [Text.StringBuilder]::new()
    [void]$markerText.Append("order start")
    for ($i = 1; $i -le $Count; $i++) { [void]$markerText.Append(("\nmark {0:D6}" -f $i)) }
    $lines.Add("print string `"$($markerText.ToString())`"") | Out-Null

    $lines.Add("write file `"$fileName`" with string `"file start`"") | Out-Null
    for ($i = 1; $i -le $Count; $i++) {
        $lines.Add(("add string `"\nfile mark {0:D6}`" to file `"$fileName`"" -f $i)) | Out-Null
    }
    $lines.Add("load file `"$fileName`" to `"content`"") | Out-Null
    $lines.Add("print `"content`"") | Out-Null
    $lines.Add("print string `"order end`"") | Out-Null
    $lines.Add("blend mix to code 0") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("end program `"$name`"") | Out-Null
    $path = Join-Path $SourceRoot "stress_order_markers_$Count.arq"
    [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false))
    return $path
}

function Get-OrderMarkersFileContent {
    param([int]$Count)
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append("file start")
    for ($i = 1; $i -le $Count; $i++) { [void]$sb.Append(("`nfile mark {0:D6}" -f $i)) }
    return $sb.ToString()
}

function Get-OrderMarkersStdout {
    param([int]$Count)
    $fileContent = Get-OrderMarkersFileContent $Count
    $sb = [Text.StringBuilder]::new()

    # Keep this expected output byte-identical to the current runtime.
    # The huge static print string keeps embedded \n sequences as literal
    # backslash+n text, then print_stdout appends its normal trailing LF.
    # The later load/print path uses real LF from the file runtime slot.
    [void]$sb.Append("order start")
    for ($i = 1; $i -le $Count; $i++) { [void]$sb.Append(("\nmark {0:D6}" -f $i)) }
    [void]$sb.Append("`n")
    [void]$sb.Append($fileContent)
    [void]$sb.Append("`norder end`n")
    return $sb.ToString()
}
function Write-ArgFanoutFileSource {
    param([int]$Count)
    $name = "StressArgFanoutFile$Count"
    $fileName = "stress_arg_fanout_file_$Count.txt"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("program `"$name`"") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("define string called `"arg0`" be command arg 0") | Out-Null
    $lines.Add("define string called `"content`" be string `"`"") | Out-Null
    $lines.Add("write file `"$fileName`" with string `"arg fanout start`"") | Out-Null
    for ($i = 1; $i -le $Count; $i++) {
        $lines.Add(("add string `"\nfanout line {0:D6}: `" to file `"$fileName`"" -f $i)) | Out-Null
        $lines.Add("add `"arg0`" to file `"$fileName`"") | Out-Null
    }
    $lines.Add("load file `"$fileName`" to `"content`"") | Out-Null
    $lines.Add("print `"content`"") | Out-Null
    $lines.Add("blend mix to code 0") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("end program `"$name`"") | Out-Null
    $path = Join-Path $SourceRoot "stress_arg_fanout_file_$Count.arq"
    [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false))
    return $path
}

function Get-ArgFanoutFileContent {
    param([int]$Count, [string]$Arg0)
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append("arg fanout start")
    for ($i = 1; $i -le $Count; $i++) {
        [void]$sb.Append(("`nfanout line {0:D6}: " -f $i))
        [void]$sb.Append($Arg0)
    }
    return $sb.ToString()
}

function Invoke-HugeStressMatrix {
    param(
        [int[]]$RuntimeCounts,
        [int[]]$CompileCounts
    )

    foreach ($count in $RuntimeCounts) {
        $loadPrintSource = Write-LoadPrintSource $count
        $loadPrintContent = Get-LoadPrintContent $count
        Invoke-CoreRuntimeCase -CaseName "stress_load_print_$count" -SourcePath $loadPrintSource -ExpectedStdout ($loadPrintContent + "`n") -ExpectedFiles @{ "stress_load_print_$count.txt" = $loadPrintContent }

        $roundtripSource = Write-SlotRoundtripSource $count
        $roundtripInput = Get-SlotRoundtripInputContent $count
        $roundtripCopy = "copy:`n" + $roundtripInput
        Invoke-CoreRuntimeCase -CaseName "stress_slot_roundtrip_$count" -SourcePath $roundtripSource -ExpectedStdout ($roundtripCopy + "`n") -ExpectedFiles @{ "stress_slot_roundtrip_$count.input.txt" = $roundtripInput; "stress_slot_roundtrip_$count.copy.txt" = $roundtripCopy }

        $twoFilesSource = Write-TwoFilesSource $count
        $twoA = Get-TwoFilesContent $count "A"
        $twoB = Get-TwoFilesContent $count "B"
        Invoke-CoreRuntimeCase -CaseName "stress_two_files_$count" -SourcePath $twoFilesSource -ExpectedStdout ($twoA + "`n" + $twoB + "`n") -ExpectedFiles @{ "stress_two_files_$count.a.txt" = $twoA; "stress_two_files_$count.b.txt" = $twoB }

        $orderSource = Write-OrderMarkersSource $count
        $orderContent = Get-OrderMarkersFileContent $count
        Invoke-CoreRuntimeCase -CaseName "stress_order_markers_$count" -SourcePath $orderSource -ExpectedStdout (Get-OrderMarkersStdout $count) -ExpectedFiles @{ "stress_order_markers_$count.txt" = $orderContent }

        $fanoutSource = Write-ArgFanoutFileSource $count
        $fanoutArg = "ARG FANOUT"
        $fanoutContent = Get-ArgFanoutFileContent $count $fanoutArg
        Invoke-CoreRuntimeCase -CaseName "stress_arg_fanout_file_$count" -SourcePath $fanoutSource -Arguments @($fanoutArg) -ExpectedStdout ($fanoutContent + "`n") -ExpectedFiles @{ "stress_arg_fanout_file_$count.txt" = $fanoutContent }
    }

    foreach ($count in $CompileCounts) {
        Invoke-CoreCompileOnlyCase -CaseName "stress_load_print_$count" -SourcePath (Write-LoadPrintSource $count)
        Invoke-CoreCompileOnlyCase -CaseName "stress_slot_roundtrip_$count" -SourcePath (Write-SlotRoundtripSource $count)
        Invoke-CoreCompileOnlyCase -CaseName "stress_two_files_$count" -SourcePath (Write-TwoFilesSource $count)
        Invoke-CoreCompileOnlyCase -CaseName "stress_order_markers_$count" -SourcePath (Write-OrderMarkersSource $count)
        Invoke-CoreCompileOnlyCase -CaseName "stress_arg_fanout_file_$count" -SourcePath (Write-ArgFanoutFileSource $count)
    }
}

function Invoke-CoreRuntimeMatrix {
    param(
        [int[]]$RuntimeCounts,
        [int[]]$CompileCounts
    )

    foreach ($count in $RuntimeCounts) {
        $printSource = Write-PrintOnlySource $count
        Invoke-CoreRuntimeCase -CaseName "stress_print_$count" -SourcePath $printSource -ExpectedStdout (Get-PrintOnlyExpected $count)

        $argsSource = Write-ArgsSource $count
        $caseArgs = Get-ArgsList $count
        Invoke-CoreRuntimeCase -CaseName "stress_args_$count" -SourcePath $argsSource -Arguments $caseArgs -ExpectedStdout (Get-ArgsExpectedStdout -CaseArgs $caseArgs)

        $mixedSource = Write-MixedNoArgsSource $count
        $mixedContent = Get-MixedNoArgsContent $count
        $mixedFiles = @{ "stress_mixed_no_args_$count.txt" = $mixedContent }
        $mixedStdout = "mixed no args start`n" + $mixedContent + "`n" + "mixed no args end`n"
        Invoke-CoreRuntimeCase -CaseName "stress_mixed_no_args_$count" -SourcePath $mixedSource -ExpectedStdout $mixedStdout -ExpectedFiles $mixedFiles

        $argsFileSource = Write-ArgsFileSource $count
        $argsFileArgs = @("ARG 001")
        $argsFileContent = Get-ArgsFileContent $count $argsFileArgs[0]
        $argsFileFiles = @{ "stress_args_file_$count.txt" = $argsFileContent }
        $argsFileStdout = "args file start`n" + $argsFileContent + "`n" + "args file end`n"
        Invoke-CoreRuntimeCase -CaseName "stress_args_file_$count" -SourcePath $argsFileSource -Arguments $argsFileArgs -ExpectedStdout $argsFileStdout -ExpectedFiles $argsFileFiles
    }

    foreach ($count in $CompileCounts) {
        Invoke-CoreCompileOnlyCase -CaseName "stress_print_$count" -SourcePath (Write-PrintOnlySource $count)
        Invoke-CoreCompileOnlyCase -CaseName "stress_args_$count" -SourcePath (Write-ArgsSource $count)
        Invoke-CoreCompileOnlyCase -CaseName "stress_mixed_no_args_$count" -SourcePath (Write-MixedNoArgsSource $count)
        Invoke-CoreCompileOnlyCase -CaseName "stress_args_file_$count" -SourcePath (Write-ArgsFileSource $count)
    }
}

foreach ($count in $RunCounts) {
    Test-StressCase -Count $count -RunCase $true -LoadAndPrint ($count -le $LoadPrintMaxCount)
}

foreach ($count in $CompileOnlyCounts) {
    Test-StressCase -Count $count -RunCase $false -LoadAndPrint $false
}

Invoke-CoreRuntimeMatrix -RuntimeCounts $CoreRunCounts -CompileCounts $CoreCompileOnlyCounts
Invoke-HugeStressMatrix -RuntimeCounts $HugeRunCounts -CompileCounts $HugeCompileOnlyCounts

[IO.File]::WriteAllLines($OutPath, $script:Lines, [Text.UTF8Encoding]::new($false))
Write-Host "OUT|$(Rel-Path $OutPath)"
if ($script:Failed) { exit 1 }
exit 0
