param(
    [switch]$List,
    [switch]$Deep,
    [switch]$AbsolutelyEverything,
    [switch]$IncludeBuildScripts,
    [switch]$IncludeScaffoldScripts,
    [switch]$IncludeHistoricalValidators,
    [switch]$IncludeSpecCoverageValidators,
    [switch]$IncludeExpectedIr,
    [switch]$StrictLocal,
    [switch]$StrictGit,
    [switch]$KeepGoing,
    [switch]$NoColor,
    [switch]$NoAnimation,
    [switch]$NoEmoji,
    [switch]$ReportOnly,
    [switch]$Run,
    [int]$TailLines = 80
)

$ErrorActionPreference = "Stop"

$script:UseColor = -not $NoColor
$script:UseAnimation = (-not $NoAnimation) -and (-not $NoColor)
$script:UseEmoji = $false
$script:ExpectedSteps = 18
$script:StepRows = New-Object System.Collections.Generic.List[object]
$script:ReportLines = New-Object System.Collections.Generic.List[string]
$script:FailureLines = New-Object System.Collections.Generic.List[string]
$script:StartedAt = Get-Date

function Write-RunMe {
    param(
        [string]$Text,
        [string]$Color = "Gray",
        [switch]$NoNewline
    )

    if ($script:UseColor) {
        Write-Host $Text -ForegroundColor $Color -NoNewline:$NoNewline
    } else {
        Write-Host $Text -NoNewline:$NoNewline
    }
}

function Add-ReportLine {
    param([string]$Line)
    $script:ReportLines.Add($Line) | Out-Null
}

function Get-RunMeConsoleWidth {
    try {
        $width = [int]$Host.UI.RawUI.WindowSize.Width
        if ($width -ge 60) { return [Math]::Min($width, 120) }
    } catch {
    }
    return 100
}

function ConvertTo-RunMeDisplayText {
    param(
        [string]$Text,
        [int]$MaxLength = 96
    )

    if ($null -eq $Text) { return "" }
    $clean = ($Text -replace "`r", " " -replace "`n", " " -replace "`t", "    ").TrimEnd()
    if ($clean.Length -le $MaxLength) { return $clean }
    if ($MaxLength -le 3) { return $clean.Substring(0, $MaxLength) }
    return $clean.Substring(0, $MaxLength - 3) + "..."
}

function Center-RunMeText {
    param(
        [string]$Text,
        [int]$Width
    )

    if ($null -eq $Text) { $Text = "" }
    if ($Width -le 0) { return $Text }
    if ($Text.Length -ge $Width) { return $Text.Substring(0, $Width) }
    $left = [Math]::Floor(($Width - $Text.Length) / 2)
    $right = $Width - $Text.Length - $left
    return ((" " * $left) + $Text + (" " * $right))
}

function Test-RunMeEmojiHost {
    if ($NoEmoji) { return $false }
    if ($NoColor) { return $false }
    if ($env:ARQEN_RUNME_EMOJI -eq "1") { return $true }
    if ($env:ARQEN_RUNME_EMOJI -eq "0") { return $false }

    # Windows Terminal and VS Code terminal usually handle emoji decently.
    if (-not [string]::IsNullOrWhiteSpace($env:WT_SESSION)) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($env:TERM_PROGRAM) -and $env:TERM_PROGRAM -match 'vscode|Windows_Terminal') { return $true }

    # PowerShell 7+ in a VT-like terminal is usually acceptable. Windows PowerShell 5.1 conhost is not.
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7 -and -not [string]::IsNullOrWhiteSpace($env:TERM)) { return $true }
    } catch {
    }

    return $false
}

function New-RunMeGlyph {
    param(
        [int]$CodePoint,
        [string]$Fallback
    )

    if ($script:UseEmoji) {
        try { return [System.Char]::ConvertFromUtf32($CodePoint) } catch { }
    }
    return $Fallback
}

function Get-RunMeGlyph {
    param([string]$Name)

    switch ($Name) {
        "Pass" { return (New-RunMeGlyph 0x2705 "+") }
        "Skip" { return (New-RunMeGlyph 0x26A0 "~") }
        "Fail" { return (New-RunMeGlyph 0x274C "X") }
        "Run" { return (New-RunMeGlyph 0x25B6 ">") }
        "Rocket" { return (New-RunMeGlyph 0x1F680 ">>") }
        "Gear" { return (New-RunMeGlyph 0x2699 "*") }
        "Spark" { return (New-RunMeGlyph 0x2728 "*") }
        "Folder" { return (New-RunMeGlyph 0x1F4C1 "[]") }
        "Test" { return (New-RunMeGlyph 0x1F9EA "T") }
        "Log" { return (New-RunMeGlyph 0x1F4DD "LOG") }
        "Coffee" { return (New-RunMeGlyph 0x2615 "C") }
        default { return "*" }
    }
}

function Write-RunMeRule {
    param(
        [string]$Title = "",
        [string]$Color = "DarkCyan"
    )

    $width = [Math]::Max(56, (Get-RunMeConsoleWidth) - 4)
    if ([string]::IsNullOrWhiteSpace($Title)) {
        Write-RunMe ("  " + ("=" * $width)) $Color
        return
    }

    $label = " $Title "
    $left = [Math]::Max(2, [Math]::Floor(($width - $label.Length) / 2))
    $right = [Math]::Max(2, $width - $label.Length - $left)
    Write-RunMe ("  " + ("=" * $left) + $label + ("=" * $right)) $Color
}

function Write-RunMeBox {
    param(
        [string]$Title,
        [string[]]$Lines = @(),
        [string]$Color = "DarkCyan",
        [string]$TextColor = "Cyan",
        [switch]$Center,
        [int]$MinWidth = 56,
        [int]$MaxWidth = 110
    )

    $innerWidth = [Math]::Max($MinWidth, [Math]::Min($MaxWidth, (Get-RunMeConsoleWidth) - 6))
    $titleText = if ([string]::IsNullOrWhiteSpace($Title)) { "" } else { " $Title " }
    $topBody = "=" * $innerWidth
    if (-not [string]::IsNullOrWhiteSpace($titleText) -and $titleText.Length -lt $innerWidth) {
        $left = [Math]::Floor(($innerWidth - $titleText.Length) / 2)
        $right = $innerWidth - $titleText.Length - $left
        $topBody = ("=" * $left) + $titleText + ("=" * $right)
    }

    Write-RunMe ("  +" + $topBody + "+") $Color
    foreach ($line in @($Lines)) {
        $display = ConvertTo-RunMeDisplayText -Text $line -MaxLength $innerWidth
        if ($Center) { $display = Center-RunMeText -Text $display -Width $innerWidth }
        $pad = " " * [Math]::Max(0, $innerWidth - $display.Length)
        if ($script:UseColor) {
            Write-Host "  |" -ForegroundColor $Color -NoNewline
            Write-Host ($display + $pad) -ForegroundColor $TextColor -NoNewline
            Write-Host "|" -ForegroundColor $Color
        } else {
            Write-Host ("  |" + $display + $pad + "|")
        }
    }
    Write-RunMe ("  +" + ("=" * $innerWidth) + "+") $Color
}

function Get-RunMeProgressBar {
    param(
        [int]$Done,
        [int]$Total,
        [int]$Width = 28
    )

    if ($Total -le 0) { $Total = 1 }
    $ratio = [Math]::Min(1.0, [Math]::Max(0.0, [double]$Done / [double]$Total))
    $filled = [int][Math]::Floor($ratio * $Width)
    $empty = $Width - $filled
    return "[" + ("+" * $filled) + ("." * $empty) + "] " + ("{0,3:n0}%" -f ($ratio * 100))
}

function Write-RunMeProgress {
    $done = $script:StepRows.Count
    $total = [Math]::Max($script:ExpectedSteps, $done)
    $bar = Get-RunMeProgressBar -Done $done -Total $total
    Write-RunMe ("       $bar  step $done/$total") DarkCyan
}

function Get-RunMeStatusIcon {
    param([string]$Status)
    if ($Status -eq "PASS") { return (Get-RunMeGlyph "Pass") }
    if ($Status -eq "SKIP") { return (Get-RunMeGlyph "Skip") }
    if ($Status -eq "FAIL") { return (Get-RunMeGlyph "Fail") }
    return (Get-RunMeGlyph "Run")
}

function Write-RunMeStepStart {
    param(
        [string]$Name,
        [string]$Category,
        [string]$Command
    )

    Write-RunMeRule ("$Category :: $Name") Magenta
    Write-RunMe ("  $(Get-RunMeGlyph 'Gear') command: $(ConvertTo-RunMeDisplayText -Text $Command -MaxLength 92)") Yellow
}

function Write-RunMeStepResult {
    param(
        [object]$Step,
        [switch]$NoProgress
    )

    $icon = Get-RunMeStatusIcon $Step.Status
    $color = if ($Step.Status -eq "PASS") { "Green" } elseif ($Step.Status -eq "SKIP") { "Yellow" } else { "Red" }
    $line = "  {0} {1,-5} {2,-26} {3,7:n2}s  exit={4}" -f $icon,$Step.Status,$Step.Name,$Step.Seconds,$Step.ExitCode
    Write-RunMe $line $color
    if ($Step.Status -ne "PASS" -and -not [string]::IsNullOrWhiteSpace($Step.Cause)) {
        Write-RunMe ("    cause: {0}" -f (ConvertTo-RunMeDisplayText -Text $Step.Cause -MaxLength 94)) $color
    }
    if ($Step.Status -ne "PASS" -and -not [string]::IsNullOrWhiteSpace($Step.LogPath)) {
        Write-RunMe ("    log:   {0}" -f (ConvertTo-RunMeRelativePath $Step.LogPath)) DarkYellow
    }
    if (-not $NoProgress) { Write-RunMeProgress }
}

function Invoke-RunMePulse {
    param([string]$Text)

    if (-not $script:UseAnimation) { return }
    $frames = @(".", "..", "...", "....")
    $width = [Math]::Max(40, (Get-RunMeConsoleWidth) - 4)
    for ($i = 0; $i -lt 8; $i++) {
        $frame = $frames[$i % $frames.Count]
        $line = "  $frame $Text"
        if ($line.Length -lt $width) { $line = $line + (" " * ($width - $line.Length)) }
        Write-Host ("`r" + $line) -ForegroundColor Magenta -NoNewline
        Start-Sleep -Milliseconds 45
    }
    $clear = " " * $width
    Write-Host ("`r" + $clear + "`r") -NoNewline
}

function Get-RunMeLogoLines {
    return @(
        "  +++++++     ++++++      +++++     +++++++    ++    ++",
        "  ++   ++     ++   ++    ++   ++    ++         +++   ++",
        "  +++++++     ++++++     ++   ++    +++++      ++ +  ++",
        "  ++   ++     ++  ++     ++  +++    ++         ++  + ++",
        "  ++   ++     ++   ++     ++++ +    +++++++    ++   +++"
    )
}

function Get-RunMeCoffeeLines {
    return @(
        "             ",
        "       ( (",
        "        ) )",
        "              ",
        "       .--------.",
        "        |        |]",
        "       \        /",
        "       '------'",
        "       =========="
    )
}

function New-RunMeMenuRow {
    param(
        [string]$Key,
        [string]$Marker,
        [string]$Name,
        [string]$Description
    )

    return ("  {0,-2} {1,-2} {2,-22} {3}" -f $Key,$Marker,$Name,$Description)
}

function New-RunMeMenuSection {
    param([string]$Name)
    return ("  -- {0} --" -f $Name)
}

function Write-RunMeMenu {
    param([switch]$Compact)

    $lines = if ($Compact) {
        @(
            (New-RunMeMenuSection "FAST PATHS"),
            (New-RunMeMenuRow "1" ">>" "STANDARD RUN" "full repo health sweep"),
            (New-RunMeMenuRow "2" "" "DEEP AUDIT" "optional old surfaces"),
            (New-RunMeMenuRow "3" "C" "BRING COFFEE MODE" "full audit, stale surfaces included"),
            (New-RunMeMenuRow "R" "" "LAST REPORT" "print Build\Generated\run_me_report.txt")
        )
    } else {
        @(
            (New-RunMeMenuSection "DIRECT COMMANDS"),
            (New-RunMeMenuRow "." "" ".\run_me.ps1" "open keyboard menu, no run yet"),
            (New-RunMeMenuRow "1" ">>" ".\run_me.ps1 -Run" "standard green sweep"),
            (New-RunMeMenuRow "2" "" ".\run_me.ps1 -Deep" "optional/stale surfaces; may fail"),
            (New-RunMeMenuRow "3" "C" ".\run_me.ps1 -AbsolutelyEverything" "full audit, stale surfaces included"),
            (New-RunMeMenuRow "9" "" ".\run_me.ps1 -List" "wrappers, aliases and groups"),
            (New-RunMeMenuRow "R" "" ".\run_me.ps1 -ReportOnly" "print last report"),
            "",
            (New-RunMeMenuSection "DISPLAY FLAGS"),
            (New-RunMeMenuRow "7" "" "-NoAnimation" "calmer output"),
            (New-RunMeMenuRow "8" "" "-NoEmoji" "ASCII glyphs only"),
            (New-RunMeMenuRow "P" "" "-NoColor" "plain output, boring but immortal")
        )
    }

    Write-RunMeBox -Title "RUN MENU" -Lines $lines -Color Magenta -TextColor Yellow -MinWidth 86 -MaxWidth 116
}

function Get-ArqenRepoRootFromRunMe {
    $dir = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { (Get-Location).Path } else { $PSScriptRoot }
    $dir = (Resolve-Path $dir).Path

    while ($true) {
        if (
            (Test-Path (Join-Path $dir "Docs\MILESTONES.md")) -and
            (Test-Path (Join-Path $dir "Tools\M10GDriver")) -and
            (Test-Path (Join-Path $dir "Tests\CommandTests"))
        ) {
            return $dir
        }

        $parent = Split-Path -Parent $dir
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $dir) { break }
        $dir = $parent
    }

    throw "Could not locate Arqen repo root from $PSScriptRoot"
}

function ConvertTo-RunMeRelativePath {
    param([string]$Path)
    try {
        $rootFull = [System.IO.Path]::GetFullPath($script:RepoRoot)
        $pathFull = [System.IO.Path]::GetFullPath($Path)
        $rootFull = $rootFull.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)) + [System.IO.Path]::DirectorySeparatorChar
        if ($pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $pathFull.Substring($rootFull.Length)
        }
    } catch {
    }
    return $Path
}

function ConvertTo-SafeStepName {
    param([string]$Name)
    $safe = $Name -replace '[^A-Za-z0-9]+','_'
    return $safe.Trim('_')
}

function Write-Banner {
    Write-RunMe "" DarkCyan
    $logo = @(Get-RunMeLogoLines)
    $logo += ""
    $logo += "$(Get-RunMeGlyph 'Spark') RUN_ME HEALTH CONSOLE $(Get-RunMeGlyph 'Spark')"
    $logo += "build + validate + test + report"

    Write-RunMeBox -Title "ARQEN" -Lines $logo -Color Cyan -TextColor Cyan -Center -MinWidth 78 -MaxWidth 116
    if ($script:UseAnimation) {
        Invoke-RunMePulse "warming up terminal dashboard"
    }
}


function Test-RunMeHasExplicitAction {
    # Treat these as actual actions or run-mode selectors.
    # Display-only flags such as -NoAnimation/-NoEmoji/-NoColor should not bypass
    # the menu on their own, but -Run -NoAnimation must still run directly.
    return (
        $Run -or
        $List -or
        $ReportOnly -or
        $Deep -or
        $AbsolutelyEverything -or
        $IncludeBuildScripts -or
        $IncludeScaffoldScripts -or
        $IncludeHistoricalValidators -or
        $IncludeSpecCoverageValidators -or
        $IncludeExpectedIr -or
        $StrictLocal -or
        $StrictGit -or
        $KeepGoing
    )
}

function Read-RunMeMenuChoice {
    try {
        if (-not [Console]::IsInputRedirected) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Enter) { return "" }
            return $key.KeyChar.ToString()
        }
    } catch {
    }

    return (Read-Host "select").Trim()
}

function New-RunMeMenuSelection {
    param(
        [string]$Action = "Run",
        [bool]$DeepMode = $false,
        [bool]$AbsoluteMode = $false,
        [bool]$StrictLocalMode = $false,
        [bool]$StrictGitMode = $false,
        [bool]$KeepGoingMode = $false,
        [bool]$NoAnimationMode = $false,
        [bool]$NoEmojiMode = $false
    )

    return [pscustomobject]@{
        Action = $Action
        DeepMode = $DeepMode
        AbsoluteMode = $AbsoluteMode
        StrictLocalMode = $StrictLocalMode
        StrictGitMode = $StrictGitMode
        KeepGoingMode = $KeepGoingMode
        NoAnimationMode = $NoAnimationMode
        NoEmojiMode = $NoEmojiMode
    }
}

function Write-RunMeInteractiveMenu {
    $lines = @(
        (New-RunMeMenuSection "CORE"),
        (New-RunMeMenuRow "1" ">>" "STANDARD RUN" "normal green path: preflight + verify + official full test"),
        (New-RunMeMenuRow "2" "" "DEEP AUDIT" "optional historical/spec/ExpectedIR/scaffold checks; may fail"),
        (New-RunMeMenuRow "3" "C" "BRING COFFEE MODE" "full audit, stale surfaces included"),
        "",
        (New-RunMeMenuSection "STRICTNESS"),
        (New-RunMeMenuRow "4" "" "STRICT LOCAL" "standard + fail on loose patch/archive leftovers"),
        (New-RunMeMenuRow "5" "" "STRICT GIT" "standard + make git diff --check fatal"),
        (New-RunMeMenuRow "6" "" "KEEP GOING" "collect more damage after failures"),
        "",
        (New-RunMeMenuSection "DISPLAY / INFO"),
        (New-RunMeMenuRow "7" "" "QUIET RUN" "no animation, calmer output"),
        (New-RunMeMenuRow "8" "" "NO EMOJI RUN" "ASCII glyphs only"),
        (New-RunMeMenuRow "9" "" "LIST SURFACES" "wrappers, command folders, aliases, groups"),
        "",
        (New-RunMeMenuRow "R" "" "LAST REPORT" "print Build\Generated\run_me_report.txt"),
        (New-RunMeMenuRow "0" "" "EXIT" "leave without touching the repo")
    )

    Write-RunMeBox -Title "MAIN MENU" -Lines $lines -Color Magenta -TextColor Yellow -MinWidth 100 -MaxWidth 116
    Write-RunMe "" DarkCyan
    Write-RunMe "  choose [1-9, R, 0]: " Cyan -NoNewline
}


function Confirm-RunMeAuditMode {
    param(
        [string]$Title,
        [string[]]$Lines
    )

    Write-RunMeBox -Title $Title -Lines $Lines -Color Yellow -TextColor Yellow -Center -MinWidth 82 -MaxWidth 116
    Write-RunMe "  continue? [Y/N]: " Cyan -NoNewline
    $choice = (Read-RunMeMenuChoice).Trim().ToUpperInvariant()
    Write-RunMe "" DarkCyan
    return ($choice -eq "Y")
}

function Confirm-RunMeCoffeeMode {
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in @(Get-RunMeCoffeeLines)) { $lines.Add($line) | Out-Null }
    $lines.Add("") | Out-Null
    $lines.Add("This is NOT the normal green check.") | Out-Null
    $lines.Add("It checks optional, historical, native/DX12 and stale surfaces.") | Out-Null
    $lines.Add("It may fail because old specs/docs are incomplete, not because Arqen exploded.") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("1  Continue audit") | Out-Null
    $lines.Add("0  Back to menu") | Out-Null

    Write-RunMeBox -Title "BRING COFFEE MODE" -Lines @($lines) -Color Yellow -TextColor Yellow -Center -MinWidth 86 -MaxWidth 116
    Write-RunMe "  choose [1/0]: " Cyan -NoNewline
    $choice = (Read-RunMeMenuChoice).Trim().ToUpperInvariant()
    Write-RunMe "" DarkCyan
    return ($choice -eq "1" -or $choice -eq "Y")
}

function Show-RunMeInteractiveMenu {
    while ($true) {
        Write-Banner
        Write-RunMeInteractiveMenu
        $choice = (Read-RunMeMenuChoice).Trim().ToUpperInvariant()
        Write-RunMe "" DarkGray

        switch ($choice) {
            ""  { return (New-RunMeMenuSelection -Action "Run") }
            "1" { return (New-RunMeMenuSelection -Action "Run") }
            "S" { return (New-RunMeMenuSelection -Action "Run") }
            "2" {
                if (Confirm-RunMeAuditMode -Title "DEEP AUDIT WARNING" -Lines @(
                    "This is not the normal passing sweep.",
                    "It enables optional old/spec/ExpectedIR/scaffold surfaces.",
                    "Those surfaces may fail because they intentionally expose stale docs or old contracts.",
                    "Use option 1 for the normal health check."
                )) { return (New-RunMeMenuSelection -Action "Run" -DeepMode $true) }
                continue
            }
            "D" {
                if (Confirm-RunMeAuditMode -Title "DEEP AUDIT WARNING" -Lines @(
                    "This is not the normal passing sweep.",
                    "It enables optional old/spec/ExpectedIR/scaffold surfaces.",
                    "Those surfaces may fail because they intentionally expose stale docs or old contracts.",
                    "Use option 1 for the normal health check."
                )) { return (New-RunMeMenuSelection -Action "Run" -DeepMode $true) }
                continue
            }
            "3" {
                if (Confirm-RunMeCoffeeMode) { return (New-RunMeMenuSelection -Action "Run" -AbsoluteMode $true) }
                continue
            }
            "C" {
                if (Confirm-RunMeCoffeeMode) { return (New-RunMeMenuSelection -Action "Run" -AbsoluteMode $true) }
                continue
            }
            "A" {
                if (Confirm-RunMeCoffeeMode) { return (New-RunMeMenuSelection -Action "Run" -AbsoluteMode $true) }
                continue
            }
            "4" { return (New-RunMeMenuSelection -Action "Run" -StrictLocalMode $true) }
            "L" { return (New-RunMeMenuSelection -Action "List") }
            "5" { return (New-RunMeMenuSelection -Action "Run" -StrictGitMode $true) }
            "G" { return (New-RunMeMenuSelection -Action "Run" -StrictGitMode $true) }
            "6" { return (New-RunMeMenuSelection -Action "Run" -KeepGoingMode $true) }
            "K" { return (New-RunMeMenuSelection -Action "Run" -KeepGoingMode $true) }
            "7" { return (New-RunMeMenuSelection -Action "Run" -NoAnimationMode $true) }
            "Q" { return (New-RunMeMenuSelection -Action "Exit") }
            "8" { return (New-RunMeMenuSelection -Action "Run" -NoEmojiMode $true) }
            "E" { return (New-RunMeMenuSelection -Action "Run" -NoEmojiMode $true) }
            "9" { return (New-RunMeMenuSelection -Action "List") }
            "R" { return (New-RunMeMenuSelection -Action "Report") }
            "0" { return (New-RunMeMenuSelection -Action "Exit") }
            default {
                Write-RunMeBox -Title "INPUT REJECTED" -Lines @("'$choice' is not a menu option.", "Apparently even numbers need validation now.") -Color Red -TextColor Yellow -Center -MinWidth 70 -MaxWidth 96
                Start-Sleep -Milliseconds 700
            }
        }
    }
}

function New-RunMeStepObject {
    param(
        [string]$Name,
        [string]$Category,
        [string]$Status,
        [int]$ExitCode,
        [double]$Seconds,
        [string]$Command,
        [string]$LogPath,
        [string]$Cause,
        [string[]]$FailLines
    )

    return [pscustomobject]@{
        Name = $Name
        Category = $Category
        Status = $Status
        ExitCode = $ExitCode
        Seconds = $Seconds
        Command = $Command
        LogPath = $LogPath
        Cause = $Cause
        FailLines = @($FailLines)
    }
}

function Get-RunMeProblemLines {
    param([string]$LogPath)

    if (-not (Test-Path $LogPath)) { return @() }

    $patterns = @(
        '^(FAIL|ERROR|FATAL)\|',
        '(^|\s)(Exception|RuntimeException|ParserError|FullyQualifiedErrorId|Cannot find|not found|was not loaded|Access is denied|UnauthorizedAccess|The term .+ is not recognized)',
        '^\s*At\s+.+:\d+\s+char:\d+',
        '^\s*\+\s+'
    )

    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content $LogPath -ErrorAction SilentlyContinue) {
        foreach ($pattern in $patterns) {
            if ($line -match $pattern) {
                $hits.Add($line) | Out-Null
                break
            }
        }
        if ($hits.Count -ge 80) { break }
    }

    return @($hits)
}

function Get-RunMeLogReferences {
    param([string]$LogPath)

    if (-not (Test-Path $LogPath)) { return @() }

    $refs = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content $LogPath -ErrorAction SilentlyContinue) {
        $matches = [regex]::Matches($line, 'log=([^|\s]+)')
        foreach ($match in $matches) {
            $value = $match.Groups[1].Value.Trim()
            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            $full = if ([System.IO.Path]::IsPathRooted($value)) { $value } else { Join-Path $script:RepoRoot $value }
            if ((Test-Path $full) -and -not ($refs -contains $full)) {
                $refs.Add($full) | Out-Null
            }
        }
    }

    return @($refs)
}

function Get-RunMeCause {
    param(
        [string]$LogPath,
        [int]$ExitCode,
        [string]$ExceptionMessage
    )

    if (-not [string]::IsNullOrWhiteSpace($ExceptionMessage)) {
        return $ExceptionMessage
    }

    $problemLines = @(Get-RunMeProblemLines $LogPath)
    if ($problemLines.Count -gt 0) {
        return $problemLines[0]
    }

    $summary = $null
    if (Test-Path $LogPath) {
        $summary = @(Get-Content $LogPath | Where-Object { $_ -match '^SUMMARY\|' } | Select-Object -Last 1)
    }
    if ($summary) { return $summary }

    return "Process exited with code $ExitCode. No explicit FAIL line was found; check the log tail. Naturally."
}

function Show-RunMeLogTail {
    param(
        [string]$Title,
        [string]$Path,
        [int]$Lines = 80
    )

    if (-not (Test-Path $Path)) { return }

    Write-RunMe "" DarkGray
    Write-RunMe "--- $Title :: $(ConvertTo-RunMeRelativePath $Path) ---" Yellow
    foreach ($line in Get-Content $Path -Tail $Lines -ErrorAction SilentlyContinue) {
        if ($line -match '^(FAIL|ERROR|FATAL)\|') { Write-RunMe $line Red }
        elseif ($line -match '^PASS\|') { Write-RunMe $line DarkGreen }
        elseif ($line -match '^SKIP\|') { Write-RunMe $line DarkYellow }
        elseif ($line -match '^SUMMARY\|') { Write-RunMe $line Yellow }
        else { Write-RunMe $line DarkGray }
    }
}

function Add-RunMeStep {
    param([object]$Step)

    $script:StepRows.Add($Step) | Out-Null
    $relLog = if ([string]::IsNullOrWhiteSpace($Step.LogPath)) { "" } else { ConvertTo-RunMeRelativePath $Step.LogPath }
    Add-ReportLine ("STEP|{0}|{1}|exit={2}|seconds={3:n2}|log={4}" -f $Step.Status,$Step.Name,$Step.ExitCode,$Step.Seconds,$relLog)

    if ($Step.Status -ne "PASS") {
        $script:FailureLines.Add("$($Step.Name): $($Step.Cause)") | Out-Null
        Add-ReportLine ("CAUSE|{0}|{1}" -f $Step.Name,$Step.Cause)
        foreach ($line in @($Step.FailLines | Select-Object -First 40)) {
            Add-ReportLine ("FAIL_LINE|{0}|{1}" -f $Step.Name,$line)
        }
    }
}

function Invoke-RunMeCommand {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][string]$CommandPath,
        [string[]]$Arguments = @(),
        [string[]]$Switches = @(),
        [switch]$Optional
    )

    $safeName = ConvertTo-SafeStepName $Name
    $logPath = Join-Path $script:RunLogDir ("{0:00}_{1}.log" -f ($script:StepRows.Count + 1), $safeName)
    $switchText = (@($Switches) | ForEach-Object { if ($_.StartsWith('-')) { $_ } else { "-$_" } }) -join ' '
    $argText = $Arguments -join ' '
    $cmdText = "$CommandPath $switchText $argText".Trim()
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $exceptionMessage = ""
    $exitCode = 0

    Write-RunMeStepStart -Name $Name -Category $Category -Command $cmdText
    Invoke-RunMePulse "initializing $Name"
    Add-ReportLine "COMMAND|$Name|$cmdText"

    try {
        Push-Location $script:RepoRoot
        try {
            $global:LASTEXITCODE = 0
            New-Item -ItemType Directory -Force -Path $script:RunLogDir | Out-Null
            "COMMAND|$cmdText" | Set-Content -Path $logPath -Encoding UTF8
            "START|$(Get-Date -Format o)" | Add-Content -Path $logPath -Encoding UTF8

            # Capture all streams in memory first instead of redirecting directly to the step log.
            # This avoids a self-lock if a checked command touches Build/Logs while run_me is open.
            # For PowerShell scripts, switch parameters must be bound by name, not forwarded as loose strings,
            # otherwise wrappers with ValueFromRemainingArguments can eat -Everything/-List like snacks.
            $invokeArgs = @($Arguments)
            $switchSplat = @{}
            foreach ($switchName in @($Switches)) {
                if ([string]::IsNullOrWhiteSpace($switchName)) { continue }
                $cleanSwitchName = $switchName.TrimStart('-')
                if ([string]::IsNullOrWhiteSpace($cleanSwitchName)) { continue }
                $switchSplat[$cleanSwitchName] = $true
            }

            if ($switchSplat.Count -gt 0) {
                $capturedOutput = @(& $CommandPath @switchSplat @invokeArgs *>&1)
            } else {
                $capturedOutput = @(& $CommandPath @invokeArgs *>&1)
            }

            if ($null -eq $LASTEXITCODE) {
                if ($?) { $exitCode = 0 } else { $exitCode = 1 }
            } else {
                $exitCode = [int]$LASTEXITCODE
            }

            New-Item -ItemType Directory -Force -Path $script:RunLogDir | Out-Null
            foreach ($item in $capturedOutput) {
                if ($null -eq $item) { continue }
                $item.ToString() | Add-Content -Path $logPath -Encoding UTF8
            }
            "END|$(Get-Date -Format o)|exit=$exitCode" | Add-Content -Path $logPath -Encoding UTF8
        } finally {
            Pop-Location
        }
    } catch {
        $exitCode = 1
        $exceptionMessage = $_.Exception.Message
        New-Item -ItemType Directory -Force -Path $script:RunLogDir | Out-Null
        "EXCEPTION|$exceptionMessage" | Add-Content -Path $logPath -Encoding UTF8
        $_.ScriptStackTrace | Add-Content -Path $logPath -Encoding UTF8
    }

    $stopwatch.Stop()
    $problemLines = @(Get-RunMeProblemLines $logPath)
    $status = "PASS"
    if ($exitCode -ne 0) {
        if ($Optional) { $status = "SKIP" } else { $status = "FAIL" }
    }
    $cause = if ($status -eq "PASS") { "" } else { Get-RunMeCause -LogPath $logPath -ExitCode $exitCode -ExceptionMessage $exceptionMessage }
    $step = New-RunMeStepObject -Name $Name -Category $Category -Status $status -ExitCode $exitCode -Seconds $stopwatch.Elapsed.TotalSeconds -Command $cmdText -LogPath $logPath -Cause $cause -FailLines $problemLines
    Add-RunMeStep $step

    Write-RunMeStepResult $step
    if ($status -eq "FAIL") {
        foreach ($line in @($problemLines | Select-Object -First 20)) {
            Write-RunMe ("    > {0}" -f $line) DarkRed
        }
        Show-RunMeLogTail -Title "step log tail" -Path $logPath -Lines $TailLines
        foreach ($refLog in Get-RunMeLogReferences $logPath) {
            Show-RunMeLogTail -Title "referenced log tail" -Path $refLog -Lines $TailLines
        }
        if (-not $KeepGoing) { return $false }
    }

    return $true
}

function Add-RunMeSyntheticStep {
    param(
        [string]$Name,
        [string]$Category,
        [bool]$Ok,
        [string]$Detail
    )

    $status = if ($Ok) { "PASS" } else { "FAIL" }
    $exitCode = if ($Ok) { 0 } else { 1 }
    $cause = if ($Ok) { "" } else { $Detail }
    $step = New-RunMeStepObject -Name $Name -Category $Category -Status $status -ExitCode $exitCode -Seconds 0 -Command "internal" -LogPath "" -Cause $cause -FailLines @($Detail)
    Add-RunMeStep $step

    Write-RunMeStepResult $step
    if (-not $Ok) {
        Write-RunMe ("    detail: {0}" -f $Detail) Red
        if (-not $KeepGoing) { return $false }
    }
    return $true
}

function Write-RunMeList {
    Write-Banner
    Write-RunMeMenu

    Write-RunMeRule "WRAPPER SURFACES" Magenta
    $wrappers = @(
        @{ Name = "build"; Path = "Tools\build.ps1" },
        @{ Name = "generate"; Path = "Tools\generate.ps1" },
        @{ Name = "validate"; Path = "Tools\validate.ps1" },
        @{ Name = "test"; Path = "Tools\test.ps1" }
    )

    foreach ($wrapper in $wrappers) {
        $path = Join-Path $script:RepoRoot $wrapper.Path
        Write-RunMe "" DarkGray
        $wrapperTitle = $wrapper.Name.ToUpperInvariant()
        Write-RunMeBox -Title $wrapperTitle -Color Cyan -TextColor Yellow -Lines @($wrapper.Path)
        if (-not (Test-Path $path)) {
            Write-RunMe "  X missing $($wrapper.Path)" Red
            continue
        }
        try {
            Push-Location $script:RepoRoot
            & $path -List
        } catch {
            Write-RunMe $_.Exception.Message Red
        } finally {
            Pop-Location
        }
    }
}

function Write-FinalSummary {
    $endedAt = Get-Date
    $elapsed = $endedAt - $script:StartedAt
    $pass = @($script:StepRows | Where-Object { $_.Status -eq "PASS" }).Count
    $fail = @($script:StepRows | Where-Object { $_.Status -eq "FAIL" }).Count
    $skip = @($script:StepRows | Where-Object { $_.Status -eq "SKIP" }).Count
    $total = $script:StepRows.Count

    Add-ReportLine ""
    Add-ReportLine ("SUMMARY|pass={0}|fail={1}|skip={2}|total={3}|seconds={4:n2}" -f $pass,$fail,$skip,$total,$elapsed.TotalSeconds)
    Add-ReportLine ("FINISHED|{0:o}" -f $endedAt)

    Write-RunMe "" DarkGray
    $verdict = if ($fail -eq 0) { "PASS" } else { "FAIL" }
    $verdictColor = if ($fail -eq 0) { "Green" } else { "Red" }
    $bar = Get-RunMeProgressBar -Done ($pass + $skip) -Total $total -Width 34
    Write-RunMeBox -Title "RUN_ME FINAL REPORT" -Color $verdictColor -TextColor Yellow -Lines @(
        "verdict : $verdict",
        "summary : $pass passed, $fail failed, $skip skipped, $total total",
        "elapsed : $([string]::Format('{0:n2}s', $elapsed.TotalSeconds))",
        "progress: $bar"
    )

    Write-RunMeRule "STEPS" cyan
    foreach ($step in $script:StepRows) {
        Write-RunMeStepResult -Step $step -NoProgress
    }

    if ($fail -gt 0) {
        Write-RunMe "" DarkGray
        Write-RunMeBox -Title "MAIN CAUSES" -Color Red -TextColor Red -Lines @($script:FailureLines)
    }

    New-Item -ItemType Directory -Force -Path $script:GeneratedDir | Out-Null
    $reportPath = Join-Path $script:GeneratedDir "run_me_report.txt"
    [System.IO.File]::WriteAllLines($reportPath, $script:ReportLines.ToArray(), [System.Text.UTF8Encoding]::new($false))
    Write-RunMe "" DarkGray
    Write-RunMeBox -Title "ARTIFACT" -Color Cyan -TextColor Yellow -Lines @("report: $reportPath")

    if ($fail -gt 0) { exit 1 }
    exit 0
}

$script:RepoRoot = Get-ArqenRepoRootFromRunMe
$script:UseEmoji = Test-RunMeEmojiHost
$script:GeneratedDir = Join-Path $script:RepoRoot "Build\Generated"
$script:BuildLogDir = Join-Path $script:RepoRoot "Build\Logs"
$script:RunLogDir = Join-Path $script:BuildLogDir "run_me"
New-Item -ItemType Directory -Force -Path $script:GeneratedDir,$script:RunLogDir | Out-Null
Remove-Item (Join-Path $script:RunLogDir "*.log") -Force -ErrorAction SilentlyContinue

if (-not (Test-RunMeHasExplicitAction)) {
    $menuSelection = Show-RunMeInteractiveMenu
    switch ($menuSelection.Action) {
        "Exit" { exit 0 }
        "List" { $List = $true }
        "Report" { $ReportOnly = $true }
        default { }
    }

    if ($menuSelection.DeepMode) { $Deep = $true }
    if ($menuSelection.AbsoluteMode) { $AbsolutelyEverything = $true }
    if ($menuSelection.StrictLocalMode) { $StrictLocal = $true }
    if ($menuSelection.StrictGitMode) { $StrictGit = $true }
    if ($menuSelection.KeepGoingMode) { $KeepGoing = $true }
    if ($menuSelection.NoAnimationMode) { $NoAnimation = $true }
    if ($menuSelection.NoEmojiMode) { $NoEmoji = $true }

    $script:UseAnimation = (-not $NoAnimation) -and (-not $NoColor)
    $script:UseEmoji = Test-RunMeEmojiHost
}

if ($ReportOnly) {
    $report = Join-Path $script:GeneratedDir "run_me_report.txt"
    if (Test-Path $report) { Get-Content $report -Raw; exit 0 }
    Write-RunMe "No run_me report found yet." Yellow
    exit 1
}

if ($List) {
    Write-RunMeList
    exit 0
}

if ($AbsolutelyEverything) {
    $Deep = $true
    $IncludeBuildScripts = $true
    $IncludeScaffoldScripts = $true
    $IncludeHistoricalValidators = $true
    $IncludeSpecCoverageValidators = $true
    $IncludeExpectedIr = $true
}

if ($Deep) {
    $IncludeScaffoldScripts = $true
    $IncludeHistoricalValidators = $true
    $IncludeSpecCoverageValidators = $true
    $IncludeExpectedIr = $true
}

Write-Banner
Add-ReportLine ("START|{0:o}" -f $script:StartedAt)
Add-ReportLine "REPO|$script:RepoRoot"
Add-ReportLine "MODE|Deep=$Deep|AbsolutelyEverything=$AbsolutelyEverything|IncludeBuildScripts=$IncludeBuildScripts|IncludeScaffoldScripts=$IncludeScaffoldScripts|IncludeHistoricalValidators=$IncludeHistoricalValidators|IncludeSpecCoverageValidators=$IncludeSpecCoverageValidators|IncludeExpectedIr=$IncludeExpectedIr|StrictLocal=$StrictLocal|StrictGit=$StrictGit|KeepGoing=$KeepGoing"

$modeText = "standard full sweep"
if ($Deep) { $modeText += " + deep surfaces" }
if ($IncludeBuildScripts) { $modeText += " + native build scripts" }
Write-RunMeBox -Title "SESSION" -Color Magenta -TextColor Yellow -Lines @(
    "repo : $script:RepoRoot",
    "mode : $modeText",
    "flags: StrictLocal=$StrictLocal StrictGit=$StrictGit KeepGoing=$KeepGoing"
)
Write-RunMe "" DarkGray

$criticalFiles = @(
    "Tools\arqc.ps1",
    "Tools\build.ps1",
    "Tools\clean.ps1",
    "Tools\generate.ps1",
    "Tools\validate.ps1",
    "Tools\test.ps1",
    "Tools\run_test_slice.ps1",
    "Tools\verify_repo.ps1",
    "Tools\Internal\Test\run_test_slice.ps1",
    "Tools\Internal\Test\run_everything.ps1"
)

foreach ($rel in $criticalFiles) {
    $ok = Test-Path (Join-Path $script:RepoRoot $rel)
    if (-not (Add-RunMeSyntheticStep -Name ("preflight_" + (ConvertTo-SafeStepName $rel)) -Category "preflight" -Ok $ok -Detail $rel)) { Write-FinalSummary }
}

$publicTestScripts = @(Get-ChildItem (Join-Path $script:RepoRoot "Tools\Test") -File -Filter "*.ps1" -ErrorAction SilentlyContinue)
$publicTestOk = ($publicTestScripts.Count -eq 0)
$publicTestDetail = if ($publicTestOk) { "Tools\Test has no public .ps1 engine scripts" } else { ($publicTestScripts | ForEach-Object { ConvertTo-RunMeRelativePath $_.FullName }) -join ", " }
if (-not (Add-RunMeSyntheticStep -Name "preflight_public_test_folder_clean" -Category "preflight" -Ok $publicTestOk -Detail $publicTestDetail)) { Write-FinalSummary }

$toolsPs1 = @(Get-ChildItem (Join-Path $script:RepoRoot "Tools") -Recurse -File -Filter "*.ps1" -ErrorAction SilentlyContinue)
Add-RunMeSyntheticStep -Name "preflight_tools_ps1_count" -Category "preflight" -Ok ($toolsPs1.Count -gt 0) -Detail "Tools ps1 count=$($toolsPs1.Count)" | Out-Null

$gitDiffOptional = -not $StrictGit
if (-not (Invoke-RunMeCommand -Name "git_diff_check" -Category "git" -CommandPath "git" -Arguments @("-C", $script:RepoRoot, "diff", "--check") -Optional:$gitDiffOptional)) { Write-FinalSummary }
if (-not (Invoke-RunMeCommand -Name "clean_check" -Category "hygiene" -CommandPath (Join-Path $script:RepoRoot "Tools\clean.ps1") -Switches @("CheckOnly"))) { Write-FinalSummary }
if (-not (Invoke-RunMeCommand -Name "tool_surface" -Category "hygiene" -CommandPath (Join-Path $script:RepoRoot "Tools\validate.ps1") -Arguments @("tool_surface"))) { Write-FinalSummary }

$trashArgs = @("trash")
$trashSwitches = @()
if ($StrictLocal) { $trashSwitches += "StrictLocal" }
if (-not (Invoke-RunMeCommand -Name "trash" -Category "hygiene" -CommandPath (Join-Path $script:RepoRoot "Tools\validate.ps1") -Arguments $trashArgs -Switches $trashSwitches)) { Write-FinalSummary }
if (-not (Invoke-RunMeCommand -Name "repo_verify_validators" -Category "repo" -CommandPath (Join-Path $script:RepoRoot "Tools\verify_repo.ps1") -Switches @("RunValidators"))) { Write-FinalSummary }

$testSwitches = @("Everything")
if (-not $KeepGoing) { $testSwitches += "StopOnFail" }
if ($IncludeBuildScripts) { $testSwitches += "IncludeBuildScripts" }
if ($IncludeScaffoldScripts) { $testSwitches += "IncludeScaffoldScripts" }
if ($IncludeHistoricalValidators) { $testSwitches += "IncludeHistoricalValidators" }
if ($IncludeSpecCoverageValidators) { $testSwitches += "IncludeSpecCoverageValidators" }
if ($IncludeExpectedIr) { $testSwitches += "IncludeExpectedIr" }
if (-not (Invoke-RunMeCommand -Name "official_full_test" -Category "test" -CommandPath (Join-Path $script:RepoRoot "Tools\test.ps1") -Switches $testSwitches)) { Write-FinalSummary }

try {
    $statusLog = Join-Path $script:RunLogDir "git_status_short.log"
    git -C $script:RepoRoot status --short *> $statusLog
    Add-ReportLine "GIT_STATUS|$(ConvertTo-RunMeRelativePath $statusLog)"
} catch {
    Add-ReportLine "GIT_STATUS|unavailable|$($_.Exception.Message)"
}

Write-FinalSummary
