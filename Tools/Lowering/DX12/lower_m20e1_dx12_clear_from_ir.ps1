
param(
    [Parameter(Mandatory = $true)]
    [string]$IrPath,
    [string]$OutDir = "",
    [string]$Renderer = "",
    [switch]$RequireFrame,
    [switch]$RequireTriangle,
    [int]$HoldMilliseconds = 1600,
    [int]$FrameCount = 0,
    [int]$TargetFps = 60,
    [switch]$KeepOpen,
    [switch]$Diagnostics,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Fail-M20E1 {
    param([string]$Message)
    throw "M20E1 DX12 lowering failed: $Message"
}

function New-StringMap {
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
    return ,$map
}

function Unescape-IrValue {
    param([string]$Value)
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Value.Length; $i++) {
        $ch = $Value[$i]
        if ($ch -ne '\\' -or $i + 1 -ge $Value.Length) {
            [void]$sb.Append($ch)
            continue
        }
        $i += 1
        $next = $Value[$i]
        switch ($next) {
            'p' { [void]$sb.Append('|') }
            'r' { [void]$sb.Append("`r") }
            'n' { [void]$sb.Append("`n") }
            '\\' { [void]$sb.Append('\\') }
            default { [void]$sb.Append($next) }
        }
    }
    return $sb.ToString()
}

function Split-IrLine {
    param([string]$Line)
    $parts = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $escaped = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $ch = $Line[$i]
        if ($escaped) {
            [void]$sb.Append('\\')
            [void]$sb.Append($ch)
            $escaped = $false
            continue
        }
        if ($ch -eq '\\') {
            $escaped = $true
            continue
        }
        if ($ch -eq '|') {
            $parts.Add((Unescape-IrValue $sb.ToString())) | Out-Null
            [void]$sb.Clear()
            continue
        }
        [void]$sb.Append($ch)
    }
    if ($escaped) { [void]$sb.Append('\\') }
    $parts.Add((Unescape-IrValue $sb.ToString())) | Out-Null
    return @($parts.ToArray())
}

function Parse-IrFields {
    param([string[]]$Parts)
    $map = New-StringMap
    for ($i = 1; $i -lt $Parts.Length; $i++) {
        $part = $Parts[$i]
        $eq = $part.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $part.Substring(0, $eq)
        $value = $part.Substring($eq + 1)
        if (-not $map.ContainsKey($key)) {
            $map.Add($key, $value)
        }
    }
    return ,$map
}

function Get-Field {
    param($Map, [string]$Name, [string]$Context)
    if (-not $Map.ContainsKey($Name)) {
        Fail-M20E1 "$Context is missing required field '$Name'."
    }
    return $Map[$Name]
}

function Escape-CString {
    param([string]$Value)
    return $Value.Replace('\', '\\').Replace('"', '\"')
}
function Format-FloatLiteral {
    param([double]$Value)
    return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:0.000000}f", $Value))
}

function Format-TransformLiteral {
    param([double[]]$Position, [double[]]$Rotation, [double[]]$Scale)
    return ("{{ {0}, {1}, {2}, {3}, {4}, {5}, {6}, {7}, {8} }}" -f (Format-FloatLiteral $Position[0]), (Format-FloatLiteral $Position[1]), (Format-FloatLiteral $Position[2]), (Format-FloatLiteral $Rotation[0]), (Format-FloatLiteral $Rotation[1]), (Format-FloatLiteral $Rotation[2]), (Format-FloatLiteral $Scale[0]), (Format-FloatLiteral $Scale[1]), (Format-FloatLiteral $Scale[2]))
}

function Format-DirectionalLightLiteral {
    param([double[]]$Direction, [double]$Intensity, [double]$Ambient)
    return ("{{ {0}, {1}, {2}, {3}, {4} }}" -f (Format-FloatLiteral $Direction[0]), (Format-FloatLiteral $Direction[1]), (Format-FloatLiteral $Direction[2]), (Format-FloatLiteral $Intensity), (Format-FloatLiteral $Ambient))
}

function Format-PerspectiveCameraLiteral {
    param([double[]]$Position, [double[]]$Rotation, [double]$FovYDegrees, [double]$NearPlane, [double]$FarPlane)
    return ("{{ {0}, {1}, {2}, {3}, {4}, {5}, {6}, {7}, {8} }}" -f (Format-FloatLiteral $Position[0]), (Format-FloatLiteral $Position[1]), (Format-FloatLiteral $Position[2]), (Format-FloatLiteral $Rotation[0]), (Format-FloatLiteral $Rotation[1]), (Format-FloatLiteral $Rotation[2]), (Format-FloatLiteral $FovYDegrees), (Format-FloatLiteral $NearPlane), (Format-FloatLiteral $FarPlane))
}

function Resolve-KeyVirtualCodeLiteral {
    param([string]$Key)
    if ($Key.Length -eq 1) {
        $c = $Key.ToUpperInvariant()[0]
        if (($c -ge [char]'A' -and $c -le [char]'Z') -or ($c -ge [char]'0' -and $c -le [char]'9')) { return "'$c'" }
    }
    switch ($Key) {
        'Space' { return 'VK_SPACE' }
        'Left' { return 'VK_LEFT' }
        'Right' { return 'VK_RIGHT' }
        'Up' { return 'VK_UP' }
        'Down' { return 'VK_DOWN' }
        default { Fail-M20E1 "unsupported M26 key '$Key'." }
    }
}

function Resolve-KeyActionLiteral {
    param([string]$Action)
    switch ($Action) {
        'move_camera_held' { return 'ARQEN_DX12_KEY_ACTION_MOVE_CAMERA_HELD' }
        'reset_camera_pressed' { return 'ARQEN_DX12_KEY_ACTION_RESET_CAMERA_PRESSED' }
        'toggle_animation_pressed' { return 'ARQEN_DX12_KEY_ACTION_TOGGLE_ANIMATION_PRESSED' }
        default { Fail-M20E1 "unsupported M26 key action '$Action'." }
    }
}

function Resolve-MouseButtonLiteral {
    param([string]$Button)
    switch ($Button) {
        'Left' { return 'ARQEN_DX12_MOUSE_BUTTON_LEFT' }
        'Right' { return 'ARQEN_DX12_MOUSE_BUTTON_RIGHT' }
        'Middle' { return 'ARQEN_DX12_MOUSE_BUTTON_MIDDLE' }
        default { Fail-M20E1 "unsupported M28B mouse button '$Button'." }
    }
}

function Resolve-MouseButtonActionLiteral {
    param([string]$Action)
    switch ($Action) {
        'move_camera_held' { return 'ARQEN_DX12_MOUSE_BUTTON_ACTION_MOVE_CAMERA_HELD' }
        'reset_camera_pressed' { return 'ARQEN_DX12_MOUSE_BUTTON_ACTION_RESET_CAMERA_PRESSED' }
        'toggle_animation_pressed' { return 'ARQEN_DX12_MOUSE_BUTTON_ACTION_TOGGLE_ANIMATION_PRESSED' }
        default { Fail-M20E1 "unsupported M28B mouse button action '$Action'." }
    }
}

function Resolve-MouseWheelActionLiteral {
    param([string]$Action)
    switch ($Action) {
        'move_camera_wheel' { return 'ARQEN_DX12_MOUSE_WHEEL_ACTION_MOVE_CAMERA' }
        default { Fail-M20E1 "unsupported M28B mouse wheel action '$Action'." }
    }
}

function Resolve-SelectorAxisLiteral {
    param([string]$Axis)
    switch ($Axis) {
        'y' { return 'ARQEN_DX12_SELECTOR_ROTATE_AXIS_Y' }
        default { Fail-M20E1 "unsupported M29C selected object rotation axis '$Axis'." }
    }
}

function Resolve-SelectorMouseAxisLiteral {
    param([string]$Axis)
    switch ($Axis) {
        'x' { return 'ARQEN_DX12_SELECTOR_MOUSE_AXIS_X' }
        default { Fail-M20E1 "unsupported M29C selected object rotation mouse axis '$Axis'." }
    }
}

function Parse-VectorValue {
    param([string]$Value, [int]$Count, [string]$Context)
    $inner = $Value.Trim()
    if ($inner.StartsWith("[") -and $inner.EndsWith("]")) { $inner = $inner.Substring(1, $inner.Length - 2) }
    $parts = @($inner.Split([char[]]@(','), [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() })
    if ($parts.Count -ne $Count) { Fail-M20E1 "$Context must have $Count components, got '$Value'." }
    $values = @()
    foreach ($part in $parts) {
        $parsed = 0.0
        if (-not [double]::TryParse($part, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            Fail-M20E1 "$Context contains a non-numeric component: '$part'."
        }
        $values += $parsed
    }
    # Return scalar components as separate pipeline values.
    # Do not use `return ,$values` here: callers wrap this function in @(...),
    # and the unary comma would produce a nested System.Object[] as element 0.
    # That later makes Format-FloatLiteral receive Object[] instead of Double
    # during M21D triangle vertex config generation.
    return $values
}

function Resolve-ShaderSourcePath {
    param([string]$RepoRoot, [string]$Path, [string]$Context)
    if ([System.IO.Path]::IsPathRooted($Path)) { $full = [System.IO.Path]::GetFullPath($Path) }
    else { $full = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path)) }
    if (-not (Test-Path $full)) { Fail-M20E1 "$Context shader source file not found: $full" }
    return $full
}

function Escape-WideCString {
    param([string]$Value)
    return (Escape-CString $Value)
}

function Parse-HexColorRgb {
    param([string]$Hex)
    if ($Hex -notmatch '^#[0-9A-Fa-f]{6}$') {
        Fail-M20E1 "clear color must be #RRGGBB, got '$Hex'."
    }
    $r = [Convert]::ToInt32($Hex.Substring(1, 2), 16) / 255.0
    $g = [Convert]::ToInt32($Hex.Substring(3, 2), 16) / 255.0
    $b = [Convert]::ToInt32($Hex.Substring(5, 2), 16) / 255.0
    return @{ R = $r; G = $g; B = $b; A = 1.0 }
}


function Parse-UiColorRgba {
    param([string]$Value, [double]$Opacity)
    $hex = $Value
    switch ($Value.ToLowerInvariant()) {
        'black' { $hex = '#000000' }
        'white' { $hex = '#FFFFFF' }
        'cyan' { $hex = '#00FFFF' }
        'blue' { $hex = '#0000FF' }
        'purple' { $hex = '#800080' }
        'green' { $hex = '#00FF00' }
        'red' { $hex = '#FF0000' }
        'gray' { $hex = '#808080' }
        'grey' { $hex = '#808080' }
        'transparent' { $hex = '#000000'; $Opacity = 0.0 }
    }
    $c = Parse-HexColorRgb $hex
    return @{ R = $c.R; G = $c.G; B = $c.B; A = $Opacity }
}

function Format-ColorVector {
    param($Color)
    return ('[{0},{1},{2},{3}]' -f (Format-FloatLiteral $Color.R).Replace('f',''), (Format-FloatLiteral $Color.G).Replace('f',''), (Format-FloatLiteral $Color.B).Replace('f',''), (Format-FloatLiteral $Color.A).Replace('f',''))
}

function New-UiVertex {
    param([double]$X, [double]$Y, [double]$Z, [string]$Color)
    return [pscustomobject]@{
        Index = 0
        Buffer = '__generated_m30_ui'
        Position = ('[{0},{1},{2}]' -f ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.000000}', $X)), ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.000000}', $Y)), ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.000000}', $Z)))
        Color = $Color
    }
}

function Convert-UiXToNdc { param([double]$X, [double]$ViewportWidth) return ((($X / $ViewportWidth) * 2.0) - 1.0) }
function Convert-UiYToNdc { param([double]$Y, [double]$ViewportHeight) return (1.0 - (($Y / $ViewportHeight) * 2.0)) }

function New-UiRectVertices {
    param([double]$X, [double]$Y, [double]$W, [double]$H, [double]$ViewportWidth, [double]$ViewportHeight, [string]$Color, [double]$Z)
    $x0 = Convert-UiXToNdc $X $ViewportWidth
    $x1 = Convert-UiXToNdc ($X + $W) $ViewportWidth
    $y0 = Convert-UiYToNdc $Y $ViewportHeight
    $y1 = Convert-UiYToNdc ($Y + $H) $ViewportHeight
    return @(
        (New-UiVertex $x0 $y1 $Z $Color), (New-UiVertex $x1 $y1 $Z $Color), (New-UiVertex $x1 $y0 $Z $Color),
        (New-UiVertex $x0 $y1 $Z $Color), (New-UiVertex $x1 $y0 $Z $Color), (New-UiVertex $x0 $y0 $Z $Color)
    )
}

function New-UiClipRect {
    param([double]$X, [double]$Y, [double]$W, [double]$H)
    return [pscustomobject]@{ X = [double]$X; Y = [double]$Y; W = [double]$W; H = [double]$H }
}

function Join-UiClipRect {
    param($A, $B)
    if ($null -eq $A) { return $B }
    if ($null -eq $B) { return $A }
    $x0 = [Math]::Max([double]$A.X, [double]$B.X)
    $y0 = [Math]::Max([double]$A.Y, [double]$B.Y)
    $x1 = [Math]::Min([double]$A.X + [double]$A.W, [double]$B.X + [double]$B.W)
    $y1 = [Math]::Min([double]$A.Y + [double]$A.H, [double]$B.Y + [double]$B.H)
    if ($x1 -le $x0 -or $y1 -le $y0) { return (New-UiClipRect 0 0 0 0) }
    return (New-UiClipRect $x0 $y0 ($x1 - $x0) ($y1 - $y0))
}

function New-UiRectVerticesClipped {
    param([double]$X, [double]$Y, [double]$W, [double]$H, [double]$ViewportWidth, [double]$ViewportHeight, [string]$Color, [double]$Z, $Clip)
    $rect = New-UiClipRect $X $Y $W $H
    if ($null -ne $Clip) { $rect = Join-UiClipRect $rect $Clip }
    if ($rect.W -le 0 -or $rect.H -le 0) { return @() }
    return @(New-UiRectVertices $rect.X $rect.Y $rect.W $rect.H $ViewportWidth $ViewportHeight $Color $Z)
}

function Get-UiTextAdvance {
    param([string]$Text, [double]$Scale)
    $width = 0.0
    foreach ($ch in $Text.ToCharArray()) {
        if ($ch -eq ' ') { $width += 4.0 * $Scale }
        else { $width += 6.0 * $Scale }
    }
    return [double]$width
}

function Get-UiFontRows {
    param([char]$Ch)
    switch ([char]::ToUpperInvariant($Ch)) {
        'A' { return @('01110','10001','10001','11111','10001','10001','10001') }
        'B' { return @('11110','10001','10001','11110','10001','10001','11110') }
        'C' { return @('01111','10000','10000','10000','10000','10000','01111') }
        'D' { return @('11110','10001','10001','10001','10001','10001','11110') }
        'E' { return @('11111','10000','10000','11110','10000','10000','11111') }
        'F' { return @('11111','10000','10000','11110','10000','10000','10000') }
        'G' { return @('01111','10000','10000','10111','10001','10001','01111') }
        'H' { return @('10001','10001','10001','11111','10001','10001','10001') }
        'I' { return @('11111','00100','00100','00100','00100','00100','11111') }
        'J' { return @('00111','00010','00010','00010','10010','10010','01100') }
        'K' { return @('10001','10010','10100','11000','10100','10010','10001') }
        'L' { return @('10000','10000','10000','10000','10000','10000','11111') }
        'M' { return @('10001','11011','10101','10101','10001','10001','10001') }
        'N' { return @('10001','11001','10101','10011','10001','10001','10001') }
        'O' { return @('01110','10001','10001','10001','10001','10001','01110') }
        'P' { return @('11110','10001','10001','11110','10000','10000','10000') }
        'Q' { return @('01110','10001','10001','10001','10101','10010','01101') }
        'R' { return @('11110','10001','10001','11110','10100','10010','10001') }
        'S' { return @('01111','10000','10000','01110','00001','00001','11110') }
        'T' { return @('11111','00100','00100','00100','00100','00100','00100') }
        'U' { return @('10001','10001','10001','10001','10001','10001','01110') }
        'V' { return @('10001','10001','10001','10001','10001','01010','00100') }
        'W' { return @('10001','10001','10001','10101','10101','10101','01010') }
        'X' { return @('10001','10001','01010','00100','01010','10001','10001') }
        'Y' { return @('10001','10001','01010','00100','00100','00100','00100') }
        'Z' { return @('11111','00001','00010','00100','01000','10000','11111') }
        '0' { return @('01110','10001','10011','10101','11001','10001','01110') }
        '1' { return @('00100','01100','00100','00100','00100','00100','01110') }
        '2' { return @('01110','10001','00001','00010','00100','01000','11111') }
        '3' { return @('11110','00001','00001','01110','00001','00001','11110') }
        '4' { return @('00010','00110','01010','10010','11111','00010','00010') }
        '5' { return @('11111','10000','10000','11110','00001','00001','11110') }
        '6' { return @('01110','10000','10000','11110','10001','10001','01110') }
        '7' { return @('11111','00001','00010','00100','01000','01000','01000') }
        '8' { return @('01110','10001','10001','01110','10001','10001','01110') }
        '9' { return @('01110','10001','10001','01111','00001','00001','01110') }
        ':' { return @('00000','00100','00100','00000','00100','00100','00000') }
        '|' { return @('00100','00100','00100','00100','00100','00100','00100') }
        '/' { return @('00001','00010','00010','00100','01000','01000','10000') }
        '-' { return @('00000','00000','00000','11111','00000','00000','00000') }
        '+' { return @('00000','00100','00100','11111','00100','00100','00000') }
        '.' { return @('00000','00000','00000','00000','00000','00100','00100') }
        default { return @('00000','00000','00000','00000','00000','00000','00000') }
    }
}

function New-UiTextVertices {
    param([string]$Text, [double]$X, [double]$Y, [double]$ViewportWidth, [double]$ViewportHeight, [string]$Color, [double]$Scale, [double]$Z, [double]$MaxWidth = 100000.0, [double]$MaxHeight = 100000.0, $Clip = $null)
    $verts = @()
    $cursorX = [double]$X
    $textClip = New-UiClipRect $X $Y $MaxWidth $MaxHeight
    if ($null -ne $Clip) { $textClip = Join-UiClipRect $textClip $Clip }
    if ($textClip.W -le 0 -or $textClip.H -le 0) { return @() }
    $maxX = [double]$X + [double]$MaxWidth
    foreach ($ch in $Text.ToCharArray()) {
        $advance = if ($ch -eq ' ') { 4.0 * $Scale } else { 6.0 * $Scale }
        if ($cursorX -ge $maxX) { break }
        if ($ch -eq ' ') { $cursorX += $advance; continue }
        $rows = Get-UiFontRows $ch
        for ($row = 0; $row -lt $rows.Count; $row++) {
            for ($col = 0; $col -lt 5; $col++) {
                if ($rows[$row][$col] -eq '1') {
                    $px = [double]$cursorX + [double]$col * [double]$Scale
                    $py = [double]$Y + [double]$row * [double]$Scale
                    if ($px -ge $maxX) { continue }
                    $verts += New-UiRectVerticesClipped $px $py $Scale $Scale $ViewportWidth $ViewportHeight $Color $Z $textClip
                }
            }
        }
        $cursorX += $advance
    }
    return @($verts)
}


# M32A: real DX12 font/texture consumption without a second rendering pipeline.
# The lowerer rasterizes assigned font/texture resources into colored UI quads,
# so the existing vertex-color DX12 runtime can render them immediately. If GDI+
# is unavailable or a resource file is missing, the old bitmap text path remains
# the safe fallback instead of failing the whole scene.
$script:ArqenM32DrawingReady = $null
$script:ArqenM32FontCollections = @{}

function Initialize-UiDrawingBridge {
    if ($null -ne $script:ArqenM32DrawingReady) { return [bool]$script:ArqenM32DrawingReady }
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop | Out-Null
        $script:ArqenM32DrawingReady = $true
    } catch {
        $script:ArqenM32DrawingReady = $false
    }
    return [bool]$script:ArqenM32DrawingReady
}

function Resolve-UiAssetPath {
    param([string]$RepoRoot, [string]$AssetPath)
    if ([string]::IsNullOrWhiteSpace($AssetPath)) { return "" }
    if ([System.IO.Path]::IsPathRooted($AssetPath)) { return [System.IO.Path]::GetFullPath($AssetPath) }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $AssetPath))
}

function Format-UiColorVectorFromBytes {
    param([int]$R, [int]$G, [int]$B, [double]$A)
    $alpha = [Math]::Max(0.0, [Math]::Min(1.0, [double]$A))
    return ('[{0},{1},{2},{3}]' -f (Format-FloatLiteral ([double]$R / 255.0)).Replace('f',''), (Format-FloatLiteral ([double]$G / 255.0)).Replace('f',''), (Format-FloatLiteral ([double]$B / 255.0)).Replace('f',''), (Format-FloatLiteral $alpha).Replace('f',''))
}

function Scale-UiColorAlpha {
    param([string]$Color, [double]$AlphaMultiplier)
    $mul = [Math]::Max(0.0, [Math]::Min(1.0, [double]$AlphaMultiplier))
    $match = [regex]::Match(([string]$Color).Trim(), '^\[([^,]+),([^,]+),([^,]+),([^\]]+)\]$')
    if (-not $match.Success) { return $Color }
    try {
        $baseAlpha = [double]::Parse($match.Groups[4].Value.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
        $scaledAlpha = [Math]::Max(0.0, [Math]::Min(1.0, $baseAlpha * $mul))
        return ('[{0},{1},{2},{3}]' -f $match.Groups[1].Value.Trim(), $match.Groups[2].Value.Trim(), $match.Groups[3].Value.Trim(), (Format-FloatLiteral $scaledAlpha).Replace('f',''))
    } catch {
        return $Color
    }
}

function Resolve-UiFontStyle {
    param([string]$Weight, [string]$Style)
    $flags = [System.Drawing.FontStyle]::Regular
    $w = ([string]$Weight).Trim().ToLowerInvariant()
    $numericWeight = 0
    $isNumeric = [int]::TryParse($w, [ref]$numericWeight)
    if ($w -in @('bold','bolder','semibold','semi bold') -or ($isNumeric -and $numericWeight -ge 600)) {
        $flags = $flags -bor [System.Drawing.FontStyle]::Bold
    }
    $s = ([string]$Style).Trim().ToLowerInvariant()
    if ($s -in @('italic','oblique')) {
        $flags = $flags -bor [System.Drawing.FontStyle]::Italic
    }
    return $flags
}

function Resolve-UiFontFamily {
    param([string]$FontSpec, [string]$FontPath)
    if ((Initialize-UiDrawingBridge) -eq $false) { return $null }
    if (-not [string]::IsNullOrWhiteSpace($FontPath) -and (Test-Path $FontPath)) {
        if (-not $script:ArqenM32FontCollections.ContainsKey($FontPath)) {
            $collection = New-Object System.Drawing.Text.PrivateFontCollection
            $collection.AddFontFile($FontPath)
            $script:ArqenM32FontCollections[$FontPath] = $collection
        }
        $families = $script:ArqenM32FontCollections[$FontPath].Families
        if ($families.Count -gt 0) { return $families[0] }
    }
    $familyName = if ([string]::IsNullOrWhiteSpace($FontSpec)) { 'Segoe UI' } else { [string]$FontSpec }
    try { return (New-Object -TypeName System.Drawing.FontFamily -ArgumentList $familyName) } catch { return (New-Object -TypeName System.Drawing.FontFamily -ArgumentList 'Segoe UI') }
}

function New-UiRasterFontTextVertices {
    param(
        [string]$Text,
        [string]$Target,
        $ContentRect,
        [double]$ViewportWidth,
        [double]$ViewportHeight,
        [string]$Color,
        [double]$PixelSize,
        [double]$Z,
        [string]$HorizontalAlign,
        [string]$VerticalAlign,
        $Clip,
        $FontResourcePathMap
    )
    if ([string]::IsNullOrEmpty($Text)) { return @() }
    if ((Initialize-UiDrawingBridge) -eq $false) { return @() }

    # M32A recovery: only use the expensive GDI raster path when the object
    # explicitly asks for a font. The previous auto-DebugFont fallback made every
    # control with text enter the rasterizer, including large control rects, which
    # can stall PowerShell lowerings for minutes. Controls without explicit font
    # keep the proven bitmap fallback until the runtime gets a real atlas path.
    $fontSpec = Get-EffectiveUiStyleValue $Target 'font' ''
    if ([string]::IsNullOrWhiteSpace($fontSpec)) { return @() }
    $fontPath = ""
    if ($null -ne $FontResourcePathMap -and $FontResourcePathMap.ContainsKey($fontSpec)) { $fontPath = Resolve-UiAssetPath $repoRoot $FontResourcePathMap[$fontSpec] }

    $contentW = [double]$ContentRect.W
    $contentH = [double]$ContentRect.H
    if ($contentW -le 0 -or $contentH -le 0 -or $contentW -gt 4096 -or $contentH -gt 4096) { return @() }

    # M32A recovery: keep the authoring-time rasterizer bounded. A real DX12
    # atlas is the correct long-term path; this bridge must never hang compile.
    # 1x anti-aliased GDI is enough to prove the font command without exploding
    # vertex generation in PowerShell.
    $oversample = 1

    $fontFamily = Resolve-UiFontFamily $fontSpec $fontPath
    if ($null -eq $fontFamily) { return @() }
    $weight = Get-EffectiveUiStyleValue $Target 'font weight' 'normal'
    $fontStyle = Get-EffectiveUiStyleValue $Target 'font style' 'normal'
    $styleFlags = Resolve-UiFontStyle $weight $fontStyle
    $fontSize = [single][Math]::Max(1.0, [double]$PixelSize * [double]$oversample)

    $measureBitmap = $null
    $measureGraphics = $null
    $measureFormat = $null
    $bitmap = $null
    $graphics = $null
    $font = $null
    $format = $null
    try {
        $font = New-Object -TypeName System.Drawing.Font -ArgumentList $fontFamily, $fontSize, $styleFlags, ([System.Drawing.GraphicsUnit]::Pixel)
        $measureBitmap = New-Object -TypeName System.Drawing.Bitmap -ArgumentList 1, 1, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $measureGraphics = [System.Drawing.Graphics]::FromImage($measureBitmap)
        $measureGraphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $measureFormat = New-Object System.Drawing.StringFormat
        $measureFormat.FormatFlags = $measureFormat.FormatFlags -bor [System.Drawing.StringFormatFlags]::NoWrap
        $measured = $measureGraphics.MeasureString($Text, $font, 100000, $measureFormat)

        $maxRasterW = [int][Math]::Ceiling($contentW * [double]$oversample)
        $maxRasterH = [int][Math]::Ceiling($contentH * [double]$oversample)
        $rasterW = [int][Math]::Min($maxRasterW, [Math]::Max(1.0, [Math]::Ceiling([double]$measured.Width) + (4 * $oversample)))
        $rasterH = [int][Math]::Min($maxRasterH, [Math]::Max(1.0, [Math]::Ceiling([double]$measured.Height) + (4 * $oversample)))
        if ($rasterW -le 0 -or $rasterH -le 0 -or $rasterW -gt 4096 -or $rasterH -gt 4096) { return @() }
        # Hard budget: big/long labels fall back to the old bitmap text instead of
        # turning one compile into tens of thousands of colored quads.
        if (($rasterW * $rasterH) -gt 4096) { return @() }

        $logicalTextW = [double]$rasterW / [double]$oversample
        $logicalTextH = [double]$rasterH / [double]$oversample
        $drawX = [double]$ContentRect.X
        $drawY = [double]$ContentRect.Y
        switch ($HorizontalAlign) {
            'center' { $drawX = [double]$ContentRect.X + [Math]::Max(0.0, ($contentW - $logicalTextW) * 0.5) }
            'right' { $drawX = [double]$ContentRect.X + [Math]::Max(0.0, $contentW - $logicalTextW) }
        }
        switch ($VerticalAlign) {
            'center' { $drawY = [double]$ContentRect.Y + [Math]::Max(0.0, ($contentH - $logicalTextH) * 0.5) }
            'bottom' { $drawY = [double]$ContentRect.Y + [Math]::Max(0.0, $contentH - $logicalTextH) }
        }

        $bitmap = New-Object -TypeName System.Drawing.Bitmap -ArgumentList $rasterW, $rasterH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $format = New-Object System.Drawing.StringFormat
        $format.FormatFlags = $format.FormatFlags -bor [System.Drawing.StringFormatFlags]::NoWrap
        $format.Alignment = [System.Drawing.StringAlignment]::Near
        $format.LineAlignment = [System.Drawing.StringAlignment]::Near
        $rectF = New-Object -TypeName System.Drawing.RectangleF -ArgumentList ([single]0.0), ([single]0.0), ([single]$rasterW), ([single]$rasterH)
        $graphics.DrawString($Text, $font, [System.Drawing.Brushes]::White, $rectF, $format)

        $verts = New-Object 'System.Collections.Generic.List[object]'
        $cell = 1.0 / [double]$oversample
        $bucketColors = @{}
        for ($b = 1; $b -le 4; $b++) { $bucketColors[$b] = Scale-UiColorAlpha $Color ([double]$b / 4.0) }

        $bounds = New-Object -TypeName System.Drawing.Rectangle -ArgumentList 0, 0, $rasterW, $rasterH
        $data = $bitmap.LockBits($bounds, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $stride = [Math]::Abs($data.Stride)
            $byteCount = $stride * $rasterH
            $bytes = New-Object byte[] $byteCount
            [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $byteCount)
            for ($yy = 0; $yy -lt $rasterH; $yy++) {
                $rowBase = $yy * $stride
                $spanStart = -1
                $spanBucket = 0
                for ($xx = 0; $xx -le $rasterW; $xx++) {
                    $bucket = 0
                    if ($xx -lt $rasterW) {
                        $alpha = [int]$bytes[$rowBase + ($xx * 4) + 3]
                        if ($alpha -gt 0) {
                            $bucket = [int][Math]::Ceiling(([double]$alpha / 255.0) * 4.0)
                            if ($bucket -lt 1) { $bucket = 1 }
                            if ($bucket -gt 4) { $bucket = 4 }
                        }
                    }
                    if ($bucket -gt 0 -and $spanStart -lt 0) {
                        $spanStart = $xx
                        $spanBucket = $bucket
                    }
                    $shouldFlush = ($spanStart -ge 0) -and (($bucket -eq 0) -or ($bucket -ne $spanBucket) -or ($xx -eq $rasterW))
                    if ($shouldFlush) {
                        $spanW = ([double]($xx - $spanStart)) * $cell
                        $pieces = @(New-UiRectVerticesClipped ($drawX + ([double]$spanStart * $cell)) ($drawY + ([double]$yy * $cell)) $spanW $cell $ViewportWidth $ViewportHeight $bucketColors[$spanBucket] $Z $Clip)
                        foreach ($piece in $pieces) { [void]$verts.Add($piece) }
                        $spanStart = -1
                        $spanBucket = 0
                        if ($bucket -gt 0 -and $xx -lt $rasterW) {
                            $spanStart = $xx
                            $spanBucket = $bucket
                        }
                    }
                }
            }
        } finally {
            if ($null -ne $data) { $bitmap.UnlockBits($data) }
        }
        return @($verts.ToArray())
    } catch {
        return @()
    } finally {
        if ($null -ne $format) { $format.Dispose() }
        if ($null -ne $font) { $font.Dispose() }
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $bitmap) { $bitmap.Dispose() }
        if ($null -ne $measureFormat) { $measureFormat.Dispose() }
        if ($null -ne $measureGraphics) { $measureGraphics.Dispose() }
        if ($null -ne $measureBitmap) { $measureBitmap.Dispose() }
    }
}

function New-UiEffectiveTextVertices {
    param([string]$Text, [string]$Target, $ContentRect, [double]$ViewportWidth, [double]$ViewportHeight, [string]$Color, [double]$Scale, [double]$Z, [string]$HorizontalAlign, [string]$VerticalAlign, $Clip, $FontResourcePathMap)
    $pixelSize = [Math]::Max(1.0, [double]$Scale * 7.0)
    $fontVerts = @(New-UiRasterFontTextVertices $Text $Target $ContentRect $ViewportWidth $ViewportHeight $Color $pixelSize $Z $HorizontalAlign $VerticalAlign $Clip $FontResourcePathMap)
    if ($fontVerts.Count -gt 0) { return @($fontVerts) }
    $origin = Get-UiAlignedTextOrigin $Text $ContentRect $Scale $HorizontalAlign $VerticalAlign
    return @(New-UiTextVertices $Text $origin.X $origin.Y $ViewportWidth $ViewportHeight $Color $Scale $Z $origin.MaxW $origin.MaxH $Clip)
}

function New-UiTextureVertices {
    param([string]$Target, $Rect, [double]$ViewportWidth, [double]$ViewportHeight, [double]$Z, $Clip, $TextureResourcePathMap)
    $textureSpec = Get-EffectiveUiStyleValue $Target 'texture' ''
    if ([string]::IsNullOrWhiteSpace($textureSpec)) { return @() }
    $verts = @()
    $texturePath = ""
    if ($TextureResourcePathMap.ContainsKey($textureSpec)) { $texturePath = Resolve-UiAssetPath $repoRoot $TextureResourcePathMap[$textureSpec] }
    if ((Initialize-UiDrawingBridge) -and -not [string]::IsNullOrWhiteSpace($texturePath) -and (Test-Path $texturePath)) {
        $bitmap = $null
        try {
            $bitmap = New-Object -TypeName System.Drawing.Bitmap -ArgumentList $texturePath
            $maxCells = 96.0
            $cell = [Math]::Max(1.0, [Math]::Ceiling([Math]::Max([double]$Rect.W, [double]$Rect.H) / $maxCells))
            for ($yy = 0.0; $yy -lt [double]$Rect.H; $yy += $cell) {
                for ($xx = 0.0; $xx -lt [double]$Rect.W; $xx += $cell) {
                    $srcX = [int][Math]::Max(0, [Math]::Min($bitmap.Width - 1, [Math]::Floor((($xx + $cell * 0.5) / [Math]::Max(1.0, [double]$Rect.W)) * $bitmap.Width)))
                    $srcY = [int][Math]::Max(0, [Math]::Min($bitmap.Height - 1, [Math]::Floor((($yy + $cell * 0.5) / [Math]::Max(1.0, [double]$Rect.H)) * $bitmap.Height)))
                    $px = $bitmap.GetPixel($srcX, $srcY)
                    if ($px.A -le 8) { continue }
                    $cw = [Math]::Min($cell, [double]$Rect.W - $xx)
                    $ch = [Math]::Min($cell, [double]$Rect.H - $yy)
                    $color = Format-UiColorVectorFromBytes $px.R $px.G $px.B ([double]$px.A / 255.0)
                    $verts += New-UiRectVerticesClipped ([double]$Rect.X + $xx) ([double]$Rect.Y + $yy) $cw $ch $ViewportWidth $ViewportHeight $color $Z $Clip
                }
            }
            return @($verts)
        } catch {
            # Missing/invalid images fall through to the deterministic authoring preview below.
        } finally {
            if ($null -ne $bitmap) { $bitmap.Dispose() }
        }
    }

    # Deterministic texture preview fallback. The command is no longer a no-op
    # even without bundled art assets: assigned texture resources produce a
    # visible glow/highlight on the target, while real PNGs are sampled above.
    $cyan = Format-UiColorVectorFromBytes 57 213 255 0.16
    $violet = Format-UiColorVectorFromBytes 203 166 255 0.14
    $shineH = [Math]::Max(2.0, [double]$Rect.H * 0.34)
    $verts += New-UiRectVerticesClipped $Rect.X $Rect.Y $Rect.W $shineH $ViewportWidth $ViewportHeight $cyan $Z $Clip
    $stripeW = [Math]::Max(4.0, [double]$Rect.W * 0.08)
    $verts += New-UiRectVerticesClipped ([double]$Rect.X + [double]$Rect.W - $stripeW) $Rect.Y $stripeW $Rect.H $ViewportWidth $ViewportHeight $violet $Z $Clip
    return @($verts)
}

function Get-MapValue {
    param($Map, [string]$Target, [string]$Property, [string]$DefaultValue)
    $key = "$Target|$Property"
    if ($Map.ContainsKey($key)) { return $Map[$key] }
    return $DefaultValue
}

function Get-MapNumber {
    param($Map, [string]$Target, [string]$Property, [double]$DefaultValue)
    $value = Get-MapValue $Map $Target $Property ([string]$DefaultValue)
    # PowerShell can accidentally preserve array-shaped values when metadata is
    # piped through helper functions. M30A layout math must always receive a
    # scalar double, not an Object[] that later explodes on subtraction.
    foreach ($candidate in @($value)) {
        if ($null -eq $candidate) { continue }
        $parsed = 0.0
        if ([double]::TryParse(([string]$candidate), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { return [double]$parsed }
    }
    return [double]$DefaultValue
}

function Get-MapBool {
    param($Map, [string]$Target, [string]$Property, [bool]$DefaultValue)
    $fallback = if ($DefaultValue) { 'true' } else { 'false' }
    $value = (Get-MapValue $Map $Target $Property $fallback).ToString().ToLowerInvariant()
    return ($value -eq 'true' -or $value -eq 'yes' -or $value -eq '1' -or $value -eq 'hidden')
}

function Get-UiTextScale {
    param($StyleMap, [string]$Target, [double]$DefaultScale)
    $size = Get-MapNumber $StyleMap $Target 'size' 0.0
    if ($size -le 0.0) { $size = Get-MapNumber $StyleMap $Target 'font size' 0.0 }
    if ($size -gt 0.0) { return [Math]::Max(1.0, [Math]::Min(6.0, $size / 7.0)) }
    return [double]$DefaultScale
}

function New-UiContentRect {
    param($Rect, [double]$Padding)
    $pad = [Math]::Max(0.0, [double]$Padding)
    return (New-UiClipRect ([double]$Rect.X + $pad) ([double]$Rect.Y + $pad) ([Math]::Max(0.0, [double]$Rect.W - 2.0 * $pad)) ([Math]::Max(0.0, [double]$Rect.H - 2.0 * $pad)))
}

function Get-UiHorizontalAlign {
    param($StyleMap, [string]$Target, [string]$DefaultValue)
    $value = (Get-MapValue $StyleMap $Target 'text align' $DefaultValue).ToString().ToLowerInvariant()
    if ($value -in @('left','center','right')) { return $value }
    return $DefaultValue
}

function Get-UiVerticalAlign {
    param($StyleMap, [string]$Target, [string]$DefaultValue)
    $value = (Get-MapValue $StyleMap $Target 'vertical align' $DefaultValue).ToString().ToLowerInvariant()
    if ($value -eq 'middle') { return 'center' }
    if ($value -eq 'baseline') { return 'bottom' }
    if ($value -in @('top','center','bottom')) { return $value }
    return $DefaultValue
}

function Get-UiAlignedTextOrigin {
    param([string]$Text, $ContentRect, [double]$Scale, [string]$HorizontalAlign, [string]$VerticalAlign)
    $textWidth = Get-UiTextAdvance $Text $Scale
    $textHeight = 7.0 * [double]$Scale
    $tx = [double]$ContentRect.X
    $ty = [double]$ContentRect.Y
    $right = [double]$ContentRect.X + [double]$ContentRect.W
    $bottom = [double]$ContentRect.Y + [double]$ContentRect.H
    switch ($HorizontalAlign) {
        'center' { $tx = [double]$ContentRect.X + [Math]::Max(0.0, ([double]$ContentRect.W - $textWidth) * 0.5) }
        'right' { $tx = [double]$ContentRect.X + [Math]::Max(0.0, [double]$ContentRect.W - $textWidth) }
    }
    switch ($VerticalAlign) {
        'center' { $ty = [double]$ContentRect.Y + [Math]::Max(0.0, ([double]$ContentRect.H - $textHeight) * 0.5) }
        'bottom' { $ty = [double]$ContentRect.Y + [Math]::Max(0.0, [double]$ContentRect.H - $textHeight) }
    }
    # M31C parent containment: MaxW/MaxH are measured from the aligned
    # origin to the content edge, not from the content origin. Center/right
    # aligned text must stay inside the same content box instead of getting
    # an accidental extra draw range after the origin shifts.
    return [pscustomobject]@{ X = $tx; Y = $ty; MaxW = [Math]::Max(0.0, $right - $tx); MaxH = [Math]::Max(1.0, $bottom - $ty) }
}

function Resolve-UiAction {
    param([string]$EventBody)
    # M30D: map the existing `when clicked ... end when` body into known
    # runtime actions. This intentionally reads the event body captured by the
    # parser instead of guessing from target names or labels.
    $probe = ([string]$EventBody).ToLowerInvariant()
    if ($probe.Contains('toggle animation')) { return 'ARQEN_DX12_UI_ACTION_TOGGLE_ANIMATION' }
    if ($probe.Contains('toggle fake light') -or $probe.Contains('toggle light')) { return 'ARQEN_DX12_UI_ACTION_TOGGLE_FAKE_LIGHT' }
    return 'ARQEN_DX12_UI_ACTION_NONE'
}


function Resolve-UiControlTypeLiteral {
    param([string]$Type)
    switch ($Type) {
        'button' { return 'ARQEN_DX12_UI_CONTROL_BUTTON' }
        'checkbox' { return 'ARQEN_DX12_UI_CONTROL_CHECKBOX' }
        'slider' { return 'ARQEN_DX12_UI_CONTROL_SLIDER' }
        'input field' { return 'ARQEN_DX12_UI_CONTROL_INPUT_FIELD' }
        'dropdown' { return 'ARQEN_DX12_UI_CONTROL_DROPDOWN' }
        default { return 'ARQEN_DX12_UI_CONTROL_NONE' }
    }
}

function Get-MapEnabled {
    param($EnabledMap, $StateMap, [string]$Target)
    if ($StateMap.ContainsKey($Target) -and ([string]$StateMap[$Target]).ToLowerInvariant() -eq 'disabled') { return 0 }
    if ($EnabledMap.ContainsKey($Target) -and ([string]$EnabledMap[$Target]).ToLowerInvariant() -eq 'false') { return 0 }
    return 1
}

function New-GeneratedVertex {
    param([string]$Position, [string]$Color)
    return [pscustomobject]@{
        Index = 0
        Buffer = "__generated_m28_box"
        Position = $Position
        Color = $Color
    }
}

function New-M28BoxPrimitiveVertices {
    param([string]$ObjectName)
    $front = "[0.10,0.95,0.80,1.0]"
    $right = "[0.05,0.55,1.00,1.0]"
    $top = "[0.55,1.00,0.45,1.0]"
    $left = "[0.04,0.30,0.55,1.0]"
    $bottom = "[0.03,0.18,0.28,1.0]"
    $back = "[0.35,0.20,0.85,1.0]"
    $v = @()
    # front z=0.5
    $v += New-GeneratedVertex "[-0.5,-0.5,0.5]" $front; $v += New-GeneratedVertex "[0.5,-0.5,0.5]" $front; $v += New-GeneratedVertex "[0.5,0.5,0.5]" $front
    $v += New-GeneratedVertex "[-0.5,-0.5,0.5]" $front; $v += New-GeneratedVertex "[0.5,0.5,0.5]" $front; $v += New-GeneratedVertex "[-0.5,0.5,0.5]" $front
    # right x=0.5
    $v += New-GeneratedVertex "[0.5,-0.5,0.5]" $right; $v += New-GeneratedVertex "[0.5,-0.5,-0.5]" $right; $v += New-GeneratedVertex "[0.5,0.5,-0.5]" $right
    $v += New-GeneratedVertex "[0.5,-0.5,0.5]" $right; $v += New-GeneratedVertex "[0.5,0.5,-0.5]" $right; $v += New-GeneratedVertex "[0.5,0.5,0.5]" $right
    # back z=-0.5
    $v += New-GeneratedVertex "[0.5,-0.5,-0.5]" $back; $v += New-GeneratedVertex "[-0.5,-0.5,-0.5]" $back; $v += New-GeneratedVertex "[-0.5,0.5,-0.5]" $back
    $v += New-GeneratedVertex "[0.5,-0.5,-0.5]" $back; $v += New-GeneratedVertex "[-0.5,0.5,-0.5]" $back; $v += New-GeneratedVertex "[0.5,0.5,-0.5]" $back
    # left x=-0.5
    $v += New-GeneratedVertex "[-0.5,-0.5,-0.5]" $left; $v += New-GeneratedVertex "[-0.5,-0.5,0.5]" $left; $v += New-GeneratedVertex "[-0.5,0.5,0.5]" $left
    $v += New-GeneratedVertex "[-0.5,-0.5,-0.5]" $left; $v += New-GeneratedVertex "[-0.5,0.5,0.5]" $left; $v += New-GeneratedVertex "[-0.5,0.5,-0.5]" $left
    # top y=0.5
    $v += New-GeneratedVertex "[-0.5,0.5,0.5]" $top; $v += New-GeneratedVertex "[0.5,0.5,0.5]" $top; $v += New-GeneratedVertex "[0.5,0.5,-0.5]" $top
    $v += New-GeneratedVertex "[-0.5,0.5,0.5]" $top; $v += New-GeneratedVertex "[0.5,0.5,-0.5]" $top; $v += New-GeneratedVertex "[-0.5,0.5,-0.5]" $top
    # bottom y=-0.5
    $v += New-GeneratedVertex "[-0.5,-0.5,-0.5]" $bottom; $v += New-GeneratedVertex "[0.5,-0.5,-0.5]" $bottom; $v += New-GeneratedVertex "[0.5,-0.5,0.5]" $bottom
    $v += New-GeneratedVertex "[-0.5,-0.5,-0.5]" $bottom; $v += New-GeneratedVertex "[0.5,-0.5,0.5]" $bottom; $v += New-GeneratedVertex "[-0.5,-0.5,0.5]" $bottom
    for ($i = 0; $i -lt $v.Count; $i++) {
        $v[$i].Index = $i
        $v[$i].Buffer = "__arqen_m28_box_$ObjectName"
    }
    return @($v)
}

if (-not (Test-Path $IrPath)) {
    Fail-M20E1 "IR file not found: $IrPath"
}
if ($HoldMilliseconds -lt 1) {
    Fail-M20E1 "hold milliseconds must be positive, got '$HoldMilliseconds'."
}
if ($FrameCount -lt 0) {
    Fail-M20E1 "frame count must be zero/auto or positive, got '$FrameCount'."
}
if ($TargetFps -lt 1) {
    Fail-M20E1 "target fps must be positive, got '$TargetFps'."
}
$effectiveFrameCount = if ($KeepOpen) { 0 } elseif ($FrameCount -gt 0) { $FrameCount } else { [int][Math]::Max(1, [Math]::Ceiling(($HoldMilliseconds * $TargetFps) / 1000.0)) }
$m22FrameMode = if ($KeepOpen) { "keep_open_until_close" } else { "fixed_frame_count" }

$repoRoot = (git rev-parse --show-toplevel).Trim()
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $repoRoot "Build\M20E1"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$renderers = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$parents = @()
$readies = @()
$frames = @()
$shaders = @()
$pipelines = @()
$pipelineBinds = @()
$vertexBuffers = @()
$vertices = @()
$vertexBufferBinds = @()
$draws = @()
$objects = @()
$objectBindings = @()
$drawObjects = @()
$objectTransforms = @()
$objectPrimitives = @()
$cameras = @()
$cameraUses = @()
$cameraProjections = @()
$cameraTransforms = @()
$keyBindings = @()
$mouseCaptures = @()
$mouseMoveBindings = @()
$mouseButtonBindings = @()
$mouseWheelBindings = @()
$objectSelectors = @()
$objectSelectorUses = @()
$objectSelectionBindings = @()
$selectedObjectRotateBindings = @()
$directionalLights = @()
$lightUses = @()
$lightProperties = @()
$constantBuffers = @()
$constantBufferBinds = @()
$colorSequences = @()
$colorKeys = @()
$animateColors = @()
$uiObjects = @()
$uiProperties = @()
$uiLayouts = @()
$styleProperties = @()
$uiEvents = @()
$uiBindings = @()
$uiStates = @()
$uiResources = @()
$uiResourceUses = @()
$uiParents = @()
$uiDocks = @()
$windowCreates = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$windowTitles = New-StringMap
$windowSizes = New-StringMap
$windowTitleBarColors = New-StringMap
$windowTitleTextColors = New-StringMap
$targetName = ""
$sourcePath = ""

foreach ($rawLine in [System.IO.File]::ReadAllLines($IrPath, [System.Text.Encoding]::UTF8)) {
    if ([string]::IsNullOrWhiteSpace($rawLine)) { continue }
    $line = $rawLine.TrimStart([char]0xFEFF)
    $parts = @(Split-IrLine $line)
    if ($parts.Count -eq 0) { continue }
    $op = $parts[0]
    $fields = Parse-IrFields $parts

    switch ($op) {
        'TARGET' {
            if ($fields.ContainsKey('name')) { $targetName = $fields['name'] }
        }
        'META' {
            if ($fields.ContainsKey('source')) { $sourcePath = $fields['source'] }
        }
        'DX12_RENDERER' {
            $name = Get-Field $fields 'name' 'DX12_RENDERER'
            [void]$renderers.Add($name)
        }
        'DX12_PARENT' {
            $parents += [pscustomobject]@{
                Renderer = Get-Field $fields 'renderer' 'DX12_PARENT'
                Window = Get-Field $fields 'window' 'DX12_PARENT'
            }
        }
        'DX12_CLEAR_READY' {
            $readies += [pscustomobject]@{
                Renderer = Get-Field $fields 'renderer' 'DX12_CLEAR_READY'
                Window = Get-Field $fields 'window' 'DX12_CLEAR_READY'
                Kind = Get-Field $fields 'kind' 'DX12_CLEAR_READY'
                Value = Get-Field $fields 'value' 'DX12_CLEAR_READY'
                Unit = if ($fields.ContainsKey('unit')) { $fields['unit'] } else { "" }
                Source = Get-Field $fields 'source' 'DX12_CLEAR_READY'
            }
        }
        'DX12_FRAME' {
            $frames += [pscustomobject]@{
                Command = Get-Field $fields 'command' 'DX12_FRAME'
                Renderer = Get-Field $fields 'renderer' 'DX12_FRAME'
            }
        }
        'DX12_SHADER' {
            $shaders += [pscustomobject]@{
                Name = Get-Field $fields 'name' 'DX12_SHADER'
                Vertex = Get-Field $fields 'vertex' 'DX12_SHADER'
                Pixel = Get-Field $fields 'pixel' 'DX12_SHADER'
            }
        }
        'DX12_PIPELINE' {
            $pipelines += [pscustomobject]@{
                Name = Get-Field $fields 'name' 'DX12_PIPELINE'
                Renderer = Get-Field $fields 'renderer' 'DX12_PIPELINE'
                Shader = Get-Field $fields 'shader' 'DX12_PIPELINE'
                Topology = Get-Field $fields 'topology' 'DX12_PIPELINE'
            }
        }
        'DX12_PIPELINE_BIND' {
            $pipelineBinds += [pscustomobject]@{
                Pipeline = Get-Field $fields 'pipeline' 'DX12_PIPELINE_BIND'
                Renderer = Get-Field $fields 'renderer' 'DX12_PIPELINE_BIND'
            }
        }
        'DX12_VERTEX_BUFFER' {
            $vertexBuffers += [pscustomobject]@{ Name = Get-Field $fields 'name' 'DX12_VERTEX_BUFFER' }
        }
        'DX12_VERTEX' {
            $vertices += [pscustomobject]@{
                Buffer = Get-Field $fields 'buffer' 'DX12_VERTEX'
                Index = [int](Get-Field $fields 'index' 'DX12_VERTEX')
                Position = Get-Field $fields 'position' 'DX12_VERTEX'
                Color = Get-Field $fields 'color' 'DX12_VERTEX'
            }
        }
        'DX12_VERTEX_BUFFER_BIND' {
            $vertexBufferBinds += [pscustomobject]@{
                Buffer = Get-Field $fields 'buffer' 'DX12_VERTEX_BUFFER_BIND'
                Renderer = Get-Field $fields 'renderer' 'DX12_VERTEX_BUFFER_BIND'
            }
        }
        'DX12_DRAW' {
            $draws += [pscustomobject]@{
                Renderer = Get-Field $fields 'renderer' 'DX12_DRAW'
                Vertices = [int](Get-Field $fields 'vertices' 'DX12_DRAW')
                Buffer = Get-Field $fields 'buffer' 'DX12_DRAW'
                Pipeline = Get-Field $fields 'pipeline' 'DX12_DRAW'
                Object = if ($fields.ContainsKey('object')) { $fields['object'] } else { "" }
            }
        }
        'DX12_OBJECT' {
            $objects += [pscustomobject]@{ Name = Get-Field $fields 'name' 'DX12_OBJECT' }
        }
        'DX12_OBJECT_BIND' {
            $objectBindings += [pscustomobject]@{
                Object = Get-Field $fields 'object' 'DX12_OBJECT_BIND'
                Renderer = Get-Field $fields 'renderer' 'DX12_OBJECT_BIND'
                Pipeline = Get-Field $fields 'pipeline' 'DX12_OBJECT_BIND'
                Buffer = Get-Field $fields 'buffer' 'DX12_OBJECT_BIND'
                Vertices = [int](Get-Field $fields 'vertices' 'DX12_OBJECT_BIND')
            }
        }
        'DX12_DRAW_OBJECT' {
            $drawObjects += [pscustomobject]@{
                Object = Get-Field $fields 'object' 'DX12_DRAW_OBJECT'
                Renderer = Get-Field $fields 'renderer' 'DX12_DRAW_OBJECT'
                Vertices = [int](Get-Field $fields 'vertices' 'DX12_DRAW_OBJECT')
                Buffer = Get-Field $fields 'buffer' 'DX12_DRAW_OBJECT'
                Pipeline = Get-Field $fields 'pipeline' 'DX12_DRAW_OBJECT'
            }
        }
        'DX12_OBJECT_TRANSFORM' {
            $objectTransforms += [pscustomobject]@{
                Object = Get-Field $fields 'object' 'DX12_OBJECT_TRANSFORM'
                Property = Get-Field $fields 'property' 'DX12_OBJECT_TRANSFORM'
                Value = Get-Field $fields 'value' 'DX12_OBJECT_TRANSFORM'
            }
        }
        'DX12_OBJECT_PRIMITIVE' {
            $objectPrimitives += [pscustomobject]@{
                Object = Get-Field $fields 'object' 'DX12_OBJECT_PRIMITIVE'
                Kind = Get-Field $fields 'kind' 'DX12_OBJECT_PRIMITIVE'
            }
        }
        'DX12_CAMERA' {
            $cameras += [pscustomobject]@{ Name = Get-Field $fields 'name' 'DX12_CAMERA' }
        }
        'DX12_CAMERA_USE' {
            $cameraUses += [pscustomobject]@{
                Camera = Get-Field $fields 'camera' 'DX12_CAMERA_USE'
                Renderer = Get-Field $fields 'renderer' 'DX12_CAMERA_USE'
            }
        }
        'DX12_CAMERA_PROJECTION' {
            $cameraProjections += [pscustomobject]@{
                Camera = Get-Field $fields 'camera' 'DX12_CAMERA_PROJECTION'
                Projection = Get-Field $fields 'projection' 'DX12_CAMERA_PROJECTION'
            }
        }
        'DX12_CAMERA_TRANSFORM' {
            $cameraTransforms += [pscustomobject]@{
                Camera = Get-Field $fields 'camera' 'DX12_CAMERA_TRANSFORM'
                Property = Get-Field $fields 'property' 'DX12_CAMERA_TRANSFORM'
                Value = Get-Field $fields 'value' 'DX12_CAMERA_TRANSFORM'
            }
        }
        'DX12_KEY_BINDING' {
            $keyBindings += [pscustomobject]@{
                Key = Get-Field $fields 'key' 'DX12_KEY_BINDING'
                Action = Get-Field $fields 'action' 'DX12_KEY_BINDING'
                Target = Get-Field $fields 'target' 'DX12_KEY_BINDING'
                Delta = Get-Field $fields 'delta' 'DX12_KEY_BINDING'
            }
        }
        'DX12_MOUSE_CAPTURE' {
            $mouseCaptures += [pscustomobject]@{ Window = Get-Field $fields 'window' 'DX12_MOUSE_CAPTURE' }
        }
        'DX12_MOUSE_MOVE' {
            $mouseMoveBindings += [pscustomobject]@{
                Target = Get-Field $fields 'target' 'DX12_MOUSE_MOVE'
                Sensitivity = Get-Field $fields 'sensitivity' 'DX12_MOUSE_MOVE'
            }
        }
        'DX12_MOUSE_BUTTON' {
            $mouseButtonBindings += [pscustomobject]@{
                Button = Get-Field $fields 'button' 'DX12_MOUSE_BUTTON'
                Action = Get-Field $fields 'action' 'DX12_MOUSE_BUTTON'
                Target = Get-Field $fields 'target' 'DX12_MOUSE_BUTTON'
                Delta = Get-Field $fields 'delta' 'DX12_MOUSE_BUTTON'
            }
        }
        'DX12_MOUSE_WHEEL' {
            $mouseWheelBindings += [pscustomobject]@{
                Action = Get-Field $fields 'action' 'DX12_MOUSE_WHEEL'
                Target = Get-Field $fields 'target' 'DX12_MOUSE_WHEEL'
                Delta = Get-Field $fields 'delta' 'DX12_MOUSE_WHEEL'
            }
        }
        'DX12_OBJECT_SELECTOR' {
            $objectSelectors += [pscustomobject]@{ Name = Get-Field $fields 'name' 'DX12_OBJECT_SELECTOR' }
        }
        'DX12_OBJECT_SELECTOR_USE' {
            $objectSelectorUses += [pscustomobject]@{
                Selector = Get-Field $fields 'selector' 'DX12_OBJECT_SELECTOR_USE'
                Renderer = Get-Field $fields 'renderer' 'DX12_OBJECT_SELECTOR_USE'
            }
        }
        'DX12_OBJECT_SELECT_BINDING' {
            $objectSelectionBindings += [pscustomobject]@{
                Button = Get-Field $fields 'button' 'DX12_OBJECT_SELECT_BINDING'
                Selector = Get-Field $fields 'selector' 'DX12_OBJECT_SELECT_BINDING'
            }
        }
        'DX12_SELECTED_OBJECT_ROTATE' {
            $selectedObjectRotateBindings += [pscustomobject]@{
                Key = Get-Field $fields 'key' 'DX12_SELECTED_OBJECT_ROTATE'
                Axis = Get-Field $fields 'axis' 'DX12_SELECTED_OBJECT_ROTATE'
                MouseAxis = Get-Field $fields 'mouse_axis' 'DX12_SELECTED_OBJECT_ROTATE'
                Sensitivity = Get-Field $fields 'sensitivity' 'DX12_SELECTED_OBJECT_ROTATE'
            }
        }
        'DX12_DIRECTIONAL_LIGHT' {
            $directionalLights += [pscustomobject]@{ Name = Get-Field $fields 'name' 'DX12_DIRECTIONAL_LIGHT' }
        }
        'DX12_LIGHT_USE' {
            $lightUses += [pscustomobject]@{
                Light = Get-Field $fields 'light' 'DX12_LIGHT_USE'
                Renderer = Get-Field $fields 'renderer' 'DX12_LIGHT_USE'
            }
        }
        'DX12_LIGHT_PROPERTY' {
            $lightProperties += [pscustomobject]@{
                Light = Get-Field $fields 'light' 'DX12_LIGHT_PROPERTY'
                Property = Get-Field $fields 'property' 'DX12_LIGHT_PROPERTY'
                Value = Get-Field $fields 'value' 'DX12_LIGHT_PROPERTY'
            }
        }
        'DX12_CONSTANT_BUFFER' {
            $constantBuffers += [pscustomobject]@{
                Name = Get-Field $fields 'name' 'DX12_CONSTANT_BUFFER'
                Field = Get-Field $fields 'field' 'DX12_CONSTANT_BUFFER'
                Type = Get-Field $fields 'type' 'DX12_CONSTANT_BUFFER'
                Value = Get-Field $fields 'value' 'DX12_CONSTANT_BUFFER'
            }
        }
        'DX12_CONSTANT_BUFFER_BIND' {
            $constantBufferBinds += [pscustomobject]@{
                Buffer = Get-Field $fields 'buffer' 'DX12_CONSTANT_BUFFER_BIND'
                Pipeline = Get-Field $fields 'pipeline' 'DX12_CONSTANT_BUFFER_BIND'
            }
        }
        'DX12_COLOR_SEQUENCE' {
            $colorSequences += [pscustomobject]@{ Name = Get-Field $fields 'name' 'DX12_COLOR_SEQUENCE' }
        }
        'DX12_COLOR_KEY' {
            $colorKeys += [pscustomobject]@{
                Sequence = Get-Field $fields 'sequence' 'DX12_COLOR_KEY'
                Index = [int](Get-Field $fields 'index' 'DX12_COLOR_KEY')
                Value = Get-Field $fields 'value' 'DX12_COLOR_KEY'
            }
        }
        'DX12_ANIMATE_COLOR' {
            $animateColors += [pscustomobject]@{
                Target = Get-Field $fields 'target' 'DX12_ANIMATE_COLOR'
                Buffer = Get-Field $fields 'buffer' 'DX12_ANIMATE_COLOR'
                Field = Get-Field $fields 'field' 'DX12_ANIMATE_COLOR'
                Sequence = Get-Field $fields 'sequence' 'DX12_ANIMATE_COLOR'
                EveryFrames = [int](Get-Field $fields 'every_frames' 'DX12_ANIMATE_COLOR')
            }
        }
        'UI_OBJECT' {
            $uiObjects += [pscustomobject]@{
                Type = Get-Field $fields 'type' 'UI_OBJECT'
                Name = Get-Field $fields 'name' 'UI_OBJECT'
            }
        }
        'UI_SET' {
            $uiProperties += [pscustomobject]@{
                Target = Get-Field $fields 'target' 'UI_SET'
                Property = Get-Field $fields 'property' 'UI_SET'
                Kind = Get-Field $fields 'kind' 'UI_SET'
                Value = Get-Field $fields 'value' 'UI_SET'
            }
        }
        'UI_LAYOUT' {
            $uiLayouts += [pscustomobject]@{
                Target = Get-Field $fields 'target' 'UI_LAYOUT'
                Property = Get-Field $fields 'property' 'UI_LAYOUT'
                Kind = Get-Field $fields 'kind' 'UI_LAYOUT'
                Value = Get-Field $fields 'value' 'UI_LAYOUT'
                Unit = if ($fields.ContainsKey('unit')) { $fields['unit'] } else { '' }
            }
        }
        'STYLE' {
            $styleProperties += [pscustomobject]@{
                Target = Get-Field $fields 'target' 'STYLE'
                State = Get-Field $fields 'state' 'STYLE'
                Property = Get-Field $fields 'property' 'STYLE'
                Kind = Get-Field $fields 'kind' 'STYLE'
                Value = Get-Field $fields 'value' 'STYLE'
                Unit = if ($fields.ContainsKey('unit')) { $fields['unit'] } else { '' }
            }
        }
        'UI_PARENT' {
            $uiParents += [pscustomobject]@{
                Child = Get-Field $fields 'child' 'UI_PARENT'
                Parent = Get-Field $fields 'parent' 'UI_PARENT'
            }
        }
        'UI_DOCK' {
            $uiDocks += [pscustomobject]@{
                Target = Get-Field $fields 'target' 'UI_DOCK'
                Side = Get-Field $fields 'side' 'UI_DOCK'
                Parent = Get-Field $fields 'parent' 'UI_DOCK'
            }
        }
        'UI_EVENT' {
            $uiEvents += [pscustomobject]@{
                Event = Get-Field $fields 'event' 'UI_EVENT'
                Target = Get-Field $fields 'target' 'UI_EVENT'
                TargetKind = Get-Field $fields 'target_kind' 'UI_EVENT'
                Body = if ($fields.ContainsKey('body')) { $fields['body'] } else { '' }
            }
        }
        'UI_BIND' {
            $uiBindings += [pscustomobject]@{
                Target = Get-Field $fields 'target' 'UI_BIND'
                Property = Get-Field $fields 'property' 'UI_BIND'
                Source = Get-Field $fields 'source' 'UI_BIND'
                SourceType = Get-Field $fields 'source_type' 'UI_BIND'
            }
        }
        'UI_STATE' {
            $uiStates += [pscustomobject]@{
                Target = Get-Field $fields 'target' 'UI_STATE'
                Property = Get-Field $fields 'property' 'UI_STATE'
                Kind = Get-Field $fields 'kind' 'UI_STATE'
                Value = Get-Field $fields 'value' 'UI_STATE'
            }
        }
        'UI_RESOURCE' {
            $uiResources += [pscustomobject]@{
                Type = Get-Field $fields 'type' 'UI_RESOURCE'
                Name = Get-Field $fields 'name' 'UI_RESOURCE'
                Path = Get-Field $fields 'path' 'UI_RESOURCE'
            }
        }
        'UI_RESOURCE_USE' {
            $uiResourceUses += [pscustomobject]@{
                Target = Get-Field $fields 'target' 'UI_RESOURCE_USE'
                Property = Get-Field $fields 'property' 'UI_RESOURCE_USE'
                Resource = Get-Field $fields 'resource' 'UI_RESOURCE_USE'
                ResourceType = Get-Field $fields 'resource_type' 'UI_RESOURCE_USE'
            }
        }
        'ACTION' {
            if (-not $fields.ContainsKey('op')) { continue }
            $actionOp = $fields['op']
            $target = if ($fields.ContainsKey('target')) { $fields['target'] } else { "" }
            $value = if ($fields.ContainsKey('value')) { $fields['value'] } else { "" }
            if ($actionOp -eq 'window_create' -and -not [string]::IsNullOrWhiteSpace($target)) {
                [void]$windowCreates.Add($target)
            } elseif ($actionOp -eq 'window_set_title' -and -not [string]::IsNullOrWhiteSpace($target)) {
                $windowTitles[$target] = $value
            } elseif ($actionOp -eq 'window_set_resolution' -and -not [string]::IsNullOrWhiteSpace($target)) {
                $windowSizes[$target] = $value
            } elseif ($actionOp -eq 'window_style_title_bar_color' -and -not [string]::IsNullOrWhiteSpace($target)) {
                $windowTitleBarColors[$target] = $value
            } elseif ($actionOp -eq 'window_style_title_text_color' -and -not [string]::IsNullOrWhiteSpace($target)) {
                $windowTitleTextColors[$target] = $value
            }
        }
    }
}

if ($readies.Count -eq 0) {
    Fail-M20E1 "IR does not contain DX12_CLEAR_READY metadata. Run the compiler on an M20E0 clear-ready program first."
}

$selected = @()
if ([string]::IsNullOrWhiteSpace($Renderer)) {
    $selected = @($readies)
    if ($selected.Count -ne 1) {
        Fail-M20E1 "IR contains $($selected.Count) DX12_CLEAR_READY records. Pass -Renderer to select one."
    }
} else {
    $selected = @($readies | Where-Object { $_.Renderer -eq $Renderer })
    if ($selected.Count -eq 0) { Fail-M20E1 "renderer '$Renderer' is not clear-ready in this IR." }
    if ($selected.Count -gt 1) { Fail-M20E1 "renderer '$Renderer' has duplicate DX12_CLEAR_READY records." }
}

$ready = $selected[0]
if (-not $renderers.Contains($ready.Renderer)) {
    Fail-M20E1 "DX12_CLEAR_READY references renderer '$($ready.Renderer)' but no DX12_RENDERER metadata exists."
}
$matchingParents = @($parents | Where-Object { $_.Renderer -eq $ready.Renderer -and $_.Window -eq $ready.Window })
if ($matchingParents.Count -ne 1) {
    Fail-M20E1 "DX12_CLEAR_READY for renderer '$($ready.Renderer)' must match exactly one DX12_PARENT record."
}
if (-not $windowCreates.Contains($ready.Window)) {
    Fail-M20E1 "DX12_CLEAR_READY references window '$($ready.Window)' but no window_create ACTION exists."
}
if ($ready.Kind -ne 'color') {
    Fail-M20E1 "only kind=color is supported for M20E1 lowering, got '$($ready.Kind)'."
}

foreach ($frame in $frames) {
    if (-not $renderers.Contains($frame.Renderer)) {
        Fail-M20E1 "DX12_FRAME references renderer '$($frame.Renderer)' but no DX12_RENDERER metadata exists."
    }
}

$frameMode = "clear_ready_metadata_only"
$frameSequence = ""
$selectedFrames = @($frames | Where-Object { $_.Renderer -eq $ready.Renderer })
if ($RequireFrame -or $selectedFrames.Count -gt 0) {
    if ($selectedFrames.Count -eq 0) {
        Fail-M20E1 "renderer '$($ready.Renderer)' has no DX12_FRAME sequence. Pass an IR produced by M20G frame syntax or omit -RequireFrame."
    }

    $expectedFrame = @("begin", "clear", "end", "present")
    if ($selectedFrames.Count -ne $expectedFrame.Count) {
        Fail-M20E1 "renderer '$($ready.Renderer)' must have exactly one M20H frame sequence: begin,clear,end,present. Found $($selectedFrames.Count) commands."
    }

    for ($i = 0; $i -lt $expectedFrame.Count; $i++) {
        if ($selectedFrames[$i].Command -ne $expectedFrame[$i]) {
            $got = ($selectedFrames | ForEach-Object { $_.Command }) -join ","
            Fail-M20E1 "renderer '$($ready.Renderer)' frame sequence must be begin,clear,end,present. Got '$got'."
        }
    }

    $frameMode = "oneshot_clear_frame"
    $frameSequence = ($selectedFrames | ForEach-Object { $_.Command }) -join ","
}

$width = 960
$height = 540
if ($windowSizes.ContainsKey($ready.Window)) {
    $size = $windowSizes[$ready.Window]
    if ($size -notmatch '^(\d+)x(\d+)$') {
        Fail-M20E1 "window resolution for '$($ready.Window)' must be WIDTHxHEIGHT, got '$size'."
    }
    $width = [int]$Matches[1]
    $height = [int]$Matches[2]
    if ($width -le 0 -or $height -le 0) {
        Fail-M20E1 "window resolution for '$($ready.Window)' must be positive."
    }
}

$triangleMode = "none"
$triangleShader = $null
$trianglePipeline = $null
$triangleVertexBuffer = $null
$triangleDraw = $null
$triangleVertices = @()
$triangleDraws = @()
$triangleDrawCalls = @()
$triangleObjectNames = @()
$resolvedVertexShader = ""
$resolvedPixelShader = ""
$tintBuffer = $null
$tintColor = $null
$animation = $null
$animationColors = @()
$m23ObjectMode = $false
$m24TransformRows = @()
$m24TransformNames = @()
$m24TransformIndexByObject = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
$m24TransformData = "{ { 0.000000f, 0.000000f, 0.000000f, 0.000000f, 1.000000f, 1.000000f, 1.000000f } }"
$m24TransformCount = 1
$m24TransformEnabled = $false
$m25CameraEnabled = $false
$m25CameraName = ""
$m25CameraPosition = @(0.0, 0.0, 0.0)
$m25CameraZoom = 1.0
$m27CameraProjection = "orthographic"
$m27PerspectiveEnabled = $false
$m27DepthEnabled = $false
$m27CameraRotation = @(0.0, 0.0, 0.0)
$m27CameraFovYDegrees = 70.0
$m27CameraNearPlane = 0.1
$m27CameraFarPlane = 100.0
$m27HasFov = $false
$m27HasNear = $false
$m27HasFar = $false
$m26KeyBindingRows = @()
$m26KeyBindingData = "{ { 0u, 0u, 0.000000f, 0.000000f, 0.000000f } }"
$m26KeyBindingCount = 0
$m26KeyboardEnabled = $false
$m28bMouseCaptureEnabled = $false
$m28bMouseMoveRows = @()
$m28bMouseMoveData = "{ { 0.000000f, 0.000000f } }"
$m28bMouseMoveCount = 0
$m28bMouseButtonRows = @()
$m28bMouseButtonData = "{ { 0u, 0u, 0.000000f, 0.000000f, 0.000000f } }"
$m28bMouseButtonCount = 0
$m28bMouseWheelRows = @()
$m28bMouseWheelData = "{ { 0u, 0.000000f, 0.000000f, 0.000000f } }"
$m28bMouseWheelCount = 0
$m29cObjectSelectorEnabled = $false
$m29cObjectSelectorName = ""
$m29cObjectSelectButton = "0u"
$m29cObjectSelectBindingCount = 0
$m29cSelectedObjectRotateRows = @()
$m29cSelectedObjectRotateData = "{ { 0u, 0u, 0u, 0.000000f } }"
$m29cSelectedObjectRotateCount = 0
$m29FakeLightingEnabled = $false
$m29LightName = ""
$m29LightDirection = @( -0.35, -0.70, -0.60 )
$m29LightIntensity = 0.85
$m29LightAmbient = 0.18
$m28bPeripheralInputEnabled = $false
$m28BoxPrimitiveEnabled = $false
$m28BoxPrimitiveCount = 0
$m30UiOverlayEnabled = $false
$m30UiControlRows = @()
$m30UiControlData = "{ { 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, ARQEN_DX12_UI_CONTROL_NONE, ARQEN_DX12_UI_ACTION_NONE, 0u, 0u, 0.000000f, 0.000000f, 1.000000f } }"
$m30UiControlCount = 0
$primitiveKindByObject = @{}
foreach ($primitive in $objectPrimitives) {
    if ($primitive.Kind -ne "box") { Fail-M20E1 "unsupported M28 primitive kind '$($primitive.Kind)'." }
    $primitiveKindByObject[$primitive.Object] = $primitive.Kind
}

if ($RequireTriangle) {
    if ($frameMode -ne "oneshot_clear_frame") {
        Fail-M20E1 "-RequireTriangle requires a complete M20H frame sequence for renderer '$($ready.Renderer)'."
    }

    $matchingDrawObjects = @($drawObjects | Where-Object { $_.Renderer -eq $ready.Renderer })
    if ($matchingDrawObjects.Count -gt 0) {
        $m23ObjectMode = $true
        $triangleDraws = $matchingDrawObjects
    } else {
        $triangleDraws = @($draws | Where-Object { $_.Renderer -eq $ready.Renderer })
    }

    if ($triangleDraws.Count -lt 1) {
        Fail-M20E1 "renderer '$($ready.Renderer)' must have at least one DX12_DRAW or DX12_DRAW_OBJECT for M23C scene lowering. Found 0."
    }

    $pipelineNames = @($triangleDraws | ForEach-Object { $_.Pipeline } | Sort-Object -Unique)
    if ($pipelineNames.Count -ne 1) {
        Fail-M20E1 "M23C native scene currently requires all draw calls for renderer '$($ready.Renderer)' to use one pipeline. Found $($pipelineNames.Count)."
    }

    $trianglePipeline = @($pipelines | Where-Object { $_.Name -eq $pipelineNames[0] -and $_.Renderer -eq $ready.Renderer })
    if ($trianglePipeline.Count -ne 1) {
        Fail-M20E1 "DX12 draw references pipeline '$($pipelineNames[0])' but no matching DX12_PIPELINE exists for renderer '$($ready.Renderer)'."
    }
    $trianglePipeline = $trianglePipeline[0]
    if ($trianglePipeline.Topology -ne "triangle_list") {
        Fail-M20E1 "M23C scene smoke supports topology=triangle_list only, got '$($trianglePipeline.Topology)'."
    }

    $selectedCameraUses = @($cameraUses | Where-Object { $_.Renderer -eq $ready.Renderer })
    if ($selectedCameraUses.Count -gt 1) {
        Fail-M20E1 "renderer '$($ready.Renderer)' has more than one M25 camera binding."
    }
    if ($selectedCameraUses.Count -eq 1) {
        $m25CameraEnabled = $true
        $m25CameraName = $selectedCameraUses[0].Camera
        $matchingCamera = @($cameras | Where-Object { $_.Name -eq $m25CameraName })
        if ($matchingCamera.Count -ne 1) { Fail-M20E1 "M25 camera use references missing camera '$m25CameraName'." }

        $selectedProjection = @($cameraProjections | Where-Object { $_.Camera -eq $m25CameraName })
        if ($selectedProjection.Count -gt 1) { Fail-M20E1 "camera '$m25CameraName' has more than one M27 projection setting." }
        if ($selectedProjection.Count -eq 1) {
            $m27CameraProjection = $selectedProjection[0].Projection
            if ($m27CameraProjection -ne "orthographic" -and $m27CameraProjection -ne "perspective") { Fail-M20E1 "unsupported M27 camera projection '$m27CameraProjection'." }
        }

        $camProps = @($cameraTransforms | Where-Object { $_.Camera -eq $m25CameraName })
        foreach ($prop in $camProps) {
            switch ($prop.Property) {
                'position' { $m25CameraPosition = @(Parse-VectorValue $prop.Value 3 "M25/M27 camera position") }
                'rotation' { $m27CameraRotation = @(Parse-VectorValue $prop.Value 3 "M27 camera rotation") }
                'zoom' {
                    $zoomParsed = 0.0
                    if (-not [double]::TryParse($prop.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$zoomParsed)) { Fail-M20E1 "M25 camera zoom must be numeric." }
                    if ($zoomParsed -le 0) { Fail-M20E1 "M25 camera zoom must be positive." }
                    $m25CameraZoom = $zoomParsed
                }
                'fov_y_degrees' {
                    $fovParsed = 0.0
                    if (-not [double]::TryParse($prop.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$fovParsed)) { Fail-M20E1 "M27 camera field of view must be numeric." }
                    if ($fovParsed -le 1.0 -or $fovParsed -ge 179.0) { Fail-M20E1 "M27 camera field of view must be greater than 1 and less than 179 degrees." }
                    $m27CameraFovYDegrees = $fovParsed
                    $m27HasFov = $true
                }
                'near_plane' {
                    $nearParsed = 0.0
                    if (-not [double]::TryParse($prop.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$nearParsed)) { Fail-M20E1 "M27 camera near plane must be numeric." }
                    if ($nearParsed -le 0.0) { Fail-M20E1 "M27 camera near plane must be positive." }
                    $m27CameraNearPlane = $nearParsed
                    $m27HasNear = $true
                }
                'far_plane' {
                    $farParsed = 0.0
                    if (-not [double]::TryParse($prop.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$farParsed)) { Fail-M20E1 "M27 camera far plane must be numeric." }
                    if ($farParsed -le 0.0) { Fail-M20E1 "M27 camera far plane must be positive." }
                    $m27CameraFarPlane = $farParsed
                    $m27HasFar = $true
                }
                default { Fail-M20E1 "unsupported M25/M27 camera property '$($prop.Property)'." }
            }
        }

        if ($m27CameraProjection -eq "perspective") {
            if (-not $m27HasFov) { Fail-M20E1 "M27 perspective camera '$m25CameraName' requires field of view metadata." }
            if (-not $m27HasNear) { Fail-M20E1 "M27 perspective camera '$m25CameraName' requires near plane metadata." }
            if (-not $m27HasFar) { Fail-M20E1 "M27 perspective camera '$m25CameraName' requires far plane metadata." }
            if ($m27CameraFarPlane -le $m27CameraNearPlane) { Fail-M20E1 "M27 perspective camera far plane must be greater than near plane." }
            $m27PerspectiveEnabled = $true
            $m27DepthEnabled = $true
        }
    }

    $triangleShader = @($shaders | Where-Object { $_.Name -eq $trianglePipeline.Shader })
    if ($triangleShader.Count -ne 1) {
        Fail-M20E1 "DX12_PIPELINE references shader '$($trianglePipeline.Shader)' but no matching DX12_SHADER exists."
    }
    $triangleShader = $triangleShader[0]

    $combined = @()
    $sourceBufferNames = @()

    $drawObjectNames = @($triangleDraws | ForEach-Object { if ($_.PSObject.Properties.Name -contains 'Object') { $_.Object } else { "" } } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    foreach ($objectName in $drawObjectNames) {
        $position = @(0.0, 0.0, 0.0)
        $rotation = @(0.0, 0.0, 0.0)
        $scale = @(1.0, 1.0, 1.0)
        $props = @($objectTransforms | Where-Object { $_.Object -eq $objectName })
        foreach ($prop in $props) {
            switch ($prop.Property) {
                'position' { $position = @(Parse-VectorValue $prop.Value 3 "M24 object position") }
                'scale' { $scale = @(Parse-VectorValue $prop.Value 3 "M24 object scale") }
                'rotation' { $rotation = @(Parse-VectorValue $prop.Value 3 "M28C object rotation") }
                'rotation_x' {
                    $rx = 0.0
                    if (-not [double]::TryParse($prop.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$rx)) { Fail-M20E1 "M28C object rotation_x must be numeric." }
                    $rotation[0] = $rx
                }
                'rotation_y' {
                    $ry = 0.0
                    if (-not [double]::TryParse($prop.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$ry)) { Fail-M20E1 "M28C object rotation_y must be numeric." }
                    $rotation[1] = $ry
                }
                'rotation_z' {
                    $rz = 0.0
                    if (-not [double]::TryParse($prop.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$rz)) { Fail-M20E1 "M24 object rotation_z must be numeric." }
                    $rotation[2] = $rz
                }
                default { Fail-M20E1 "unsupported M24/M28C object transform property '$($prop.Property)'." }
            }
        }
        $index = $m24TransformRows.Count
        $m24TransformIndexByObject[$objectName] = $index
        $m24TransformRows += (Format-TransformLiteral $position $rotation $scale)
        $m24TransformNames += $objectName
        if ($props.Count -gt 0) { $m24TransformEnabled = $true }
    }
    if ($m24TransformRows.Count -eq 0) {
        $m24TransformRows += (Format-TransformLiteral @(0.0, 0.0, 0.0) @(0.0, 0.0, 0.0) @(1.0, 1.0, 1.0))
        $m24TransformNames += "identity"
    }
    $m24TransformData = "{ " + ($m24TransformRows -join ", ") + " }"
    $m24TransformCount = $m24TransformRows.Count

    foreach ($binding in $keyBindings) {
        if (($binding.Action -eq 'move_camera_held' -or $binding.Action -eq 'reset_camera_pressed') -and [string]::IsNullOrWhiteSpace($binding.Target)) {
            Fail-M20E1 "M26 camera input binding requires a camera target."
        }
        if (($binding.Action -eq 'move_camera_held' -or $binding.Action -eq 'reset_camera_pressed') -and $binding.Target -ne $m25CameraName) {
            Fail-M20E1 "M26 input target '$($binding.Target)' must match selected M25 camera '$m25CameraName'."
        }
        $delta = @(Parse-VectorValue $binding.Delta 3 "M26 input delta")
        $m26KeyBindingRows += ("{{ {0}, {1}, {2}, {3}, {4} }}" -f (Resolve-KeyVirtualCodeLiteral $binding.Key), (Resolve-KeyActionLiteral $binding.Action), (Format-FloatLiteral $delta[0]), (Format-FloatLiteral $delta[1]), (Format-FloatLiteral $delta[2]))
    }
    if ($m26KeyBindingRows.Count -gt 0) {
        if (-not $m25CameraEnabled -and @($keyBindings | Where-Object { $_.Action -like '*camera*' }).Count -gt 0) { Fail-M20E1 "M26 camera input requires an M25 camera bound to renderer '$($ready.Renderer)'." }
        $m26KeyBindingData = "{ " + ($m26KeyBindingRows -join ", ") + " }"
        $m26KeyBindingCount = $m26KeyBindingRows.Count
        $m26KeyboardEnabled = $true
    }

    foreach ($capture in $mouseCaptures) {
        if ($capture.Window -ne $ready.Window) { Fail-M20E1 "M28B mouse capture window '$($capture.Window)' must match selected DX12 window '$($ready.Window)'." }
        $m28bMouseCaptureEnabled = $true
    }
    foreach ($move in $mouseMoveBindings) {
        if ($move.Target -ne $m25CameraName) { Fail-M20E1 "M28B mouse move target '$($move.Target)' must match selected M25 camera '$m25CameraName'." }
        $sens = @(Parse-VectorValue $move.Sensitivity 2 "M28B mouse move sensitivity")
        $m28bMouseMoveRows += ("{{ {0}, {1} }}" -f (Format-FloatLiteral $sens[0]), (Format-FloatLiteral $sens[1]))
    }
    if ($m28bMouseMoveRows.Count -gt 0) {
        if (-not $m25CameraEnabled) { Fail-M20E1 "M28B mouse move camera input requires an M25 camera bound to renderer '$($ready.Renderer)'." }
        $m28bMouseMoveData = "{ " + ($m28bMouseMoveRows -join ", ") + " }"
        $m28bMouseMoveCount = $m28bMouseMoveRows.Count
    }
    foreach ($button in $mouseButtonBindings) {
        if (($button.Action -eq 'move_camera_held' -or $button.Action -eq 'reset_camera_pressed') -and $button.Target -ne $m25CameraName) { Fail-M20E1 "M28B mouse button target '$($button.Target)' must match selected M25 camera '$m25CameraName'." }
        $delta = @(Parse-VectorValue $button.Delta 3 "M28B mouse button delta")
        $m28bMouseButtonRows += ("{{ {0}, {1}, {2}, {3}, {4} }}" -f (Resolve-MouseButtonLiteral $button.Button), (Resolve-MouseButtonActionLiteral $button.Action), (Format-FloatLiteral $delta[0]), (Format-FloatLiteral $delta[1]), (Format-FloatLiteral $delta[2]))
    }
    if ($m28bMouseButtonRows.Count -gt 0) {
        if (-not $m25CameraEnabled -and @($mouseButtonBindings | Where-Object { $_.Action -like '*camera*' }).Count -gt 0) { Fail-M20E1 "M28B mouse button camera input requires an M25 camera bound to renderer '$($ready.Renderer)'." }
        $m28bMouseButtonData = "{ " + ($m28bMouseButtonRows -join ", ") + " }"
        $m28bMouseButtonCount = $m28bMouseButtonRows.Count
    }
    foreach ($wheel in $mouseWheelBindings) {
        if ($wheel.Target -ne $m25CameraName) { Fail-M20E1 "M28B mouse wheel target '$($wheel.Target)' must match selected M25 camera '$m25CameraName'." }
        $delta = @(Parse-VectorValue $wheel.Delta 3 "M28B mouse wheel delta")
        $m28bMouseWheelRows += ("{{ {0}, {1}, {2}, {3} }}" -f (Resolve-MouseWheelActionLiteral $wheel.Action), (Format-FloatLiteral $delta[0]), (Format-FloatLiteral $delta[1]), (Format-FloatLiteral $delta[2]))
    }
    if ($m28bMouseWheelRows.Count -gt 0) {
        if (-not $m25CameraEnabled) { Fail-M20E1 "M28B mouse wheel camera input requires an M25 camera bound to renderer '$($ready.Renderer)'." }
        $m28bMouseWheelData = "{ " + ($m28bMouseWheelRows -join ", ") + " }"
        $m28bMouseWheelCount = $m28bMouseWheelRows.Count
    }

    if ($objectSelectors.Count -gt 0 -or $objectSelectorUses.Count -gt 0 -or $objectSelectionBindings.Count -gt 0 -or $selectedObjectRotateBindings.Count -gt 0) {
        if ($objectSelectorUses.Count -ne 1) { Fail-M20E1 "M29C currently requires exactly one object selector bound to renderer '$($ready.Renderer)'." }
        $selectorUse = $objectSelectorUses[0]
        if ($selectorUse.Renderer -ne $ready.Renderer) { Fail-M20E1 "M29C object selector renderer '$($selectorUse.Renderer)' must match selected renderer '$($ready.Renderer)'." }
        $selectorDefs = @($objectSelectors | Where-Object { $_.Name -eq $selectorUse.Selector })
        if ($selectorDefs.Count -ne 1) { Fail-M20E1 "M29C object selector use references missing selector '$($selectorUse.Selector)'." }
        if (@($matchingDrawObjects).Count -lt 1 -or -not $m23ObjectMode) { Fail-M20E1 "M29C object selector requires drawn DX12 objects for picking." }
        $m29cObjectSelectorEnabled = $true
        $m29cObjectSelectorName = $selectorUse.Selector

        foreach ($select in $objectSelectionBindings) {
            if ($select.Selector -ne $m29cObjectSelectorName) { Fail-M20E1 "M29C selection binding selector '$($select.Selector)' must match '$m29cObjectSelectorName'." }
            if ($m29cObjectSelectBindingCount -gt 0) { Fail-M20E1 "M29C currently supports one object selection mouse binding." }
            $m29cObjectSelectButton = Resolve-MouseButtonLiteral $select.Button
            $m29cObjectSelectBindingCount = 1
        }
        if ($m29cObjectSelectBindingCount -ne 1) { Fail-M20E1 "M29C object selector requires a mouse selection binding." }

        foreach ($rotate in $selectedObjectRotateBindings) {
            $sensitivity = 0.0
            if (-not [double]::TryParse($rotate.Sensitivity, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$sensitivity)) { Fail-M20E1 "M29C selected object rotate sensitivity must be numeric." }
            if ($sensitivity -le 0.0 -or $sensitivity -gt 10.0) { Fail-M20E1 "M29C selected object rotate sensitivity must be greater than 0 and at most 10." }
            $m29cSelectedObjectRotateRows += ("{{ {0}, {1}, {2}, {3} }}" -f (Resolve-KeyVirtualCodeLiteral $rotate.Key), (Resolve-SelectorAxisLiteral $rotate.Axis), (Resolve-SelectorMouseAxisLiteral $rotate.MouseAxis), (Format-FloatLiteral $sensitivity))
        }
        if ($m29cSelectedObjectRotateRows.Count -gt 0) {
            $m29cSelectedObjectRotateData = "{ " + ($m29cSelectedObjectRotateRows -join ", ") + " }"
            $m29cSelectedObjectRotateCount = $m29cSelectedObjectRotateRows.Count
        }
        if ($m29cSelectedObjectRotateCount -ne 1) { Fail-M20E1 "M29C object selector requires one selected-object rotate binding." }
    }

    $m28bPeripheralInputEnabled = $m28bMouseCaptureEnabled -or $m28bMouseMoveCount -gt 0 -or $m28bMouseButtonCount -gt 0 -or $m28bMouseWheelCount -gt 0 -or $m29cObjectSelectorEnabled

    $selectedLightUses = @($lightUses | Where-Object { $_.Renderer -eq $ready.Renderer })
    if ($selectedLightUses.Count -gt 1) { Fail-M20E1 "M29A renderer '$($ready.Renderer)' has more than one directional light." }
    if ($selectedLightUses.Count -eq 1) {
        $m29LightName = $selectedLightUses[0].Light
        if (@($directionalLights | Where-Object { $_.Name -eq $m29LightName }).Count -ne 1) { Fail-M20E1 "M29A light '$m29LightName' is used but not defined." }
        $m29FakeLightingEnabled = $true
        $props = @($lightProperties | Where-Object { $_.Light -eq $m29LightName })
        foreach ($prop in $props) {
            switch ($prop.Property) {
                'direction' { $m29LightDirection = @(Parse-VectorValue $prop.Value 3 "M29A light direction") }
                'intensity' {
                    $parsed = 0.0
                    if (-not [double]::TryParse($prop.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { Fail-M20E1 "M29A light intensity must be numeric." }
                    if ($parsed -lt 0.0 -or $parsed -gt 4.0) { Fail-M20E1 "M29A light intensity must be between 0 and 4." }
                    $m29LightIntensity = $parsed
                }
                'ambient' {
                    $parsed = 0.0
                    if (-not [double]::TryParse($prop.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { Fail-M20E1 "M29A light ambient must be numeric." }
                    if ($parsed -lt 0.0 -or $parsed -gt 1.0) { Fail-M20E1 "M29A light ambient must be between 0 and 1." }
                    $m29LightAmbient = $parsed
                }
                default { Fail-M20E1 "unsupported M29A light property '$($prop.Property)'." }
            }
        }
        if ([Math]::Abs($m29LightDirection[0]) -lt 0.000001 -and [Math]::Abs($m29LightDirection[1]) -lt 0.000001 -and [Math]::Abs($m29LightDirection[2]) -lt 0.000001) { Fail-M20E1 "M29A light direction cannot be zero." }
    }

    foreach ($draw in $triangleDraws) {
        $sourceBufferNames += $draw.Buffer
        $nameForManifest = if ($draw.PSObject.Properties.Name -contains 'Object') { $draw.Object } else { "" }
        $isM28Box = -not [string]::IsNullOrWhiteSpace($nameForManifest) -and $primitiveKindByObject.ContainsKey($nameForManifest) -and $primitiveKindByObject[$nameForManifest] -eq "box"

        if ($isM28Box) {
            $bufferVertices = @(New-M28BoxPrimitiveVertices $nameForManifest)
            $m28BoxPrimitiveEnabled = $true
        } else {
            $sourceVertexBuffer = @($vertexBuffers | Where-Object { $_.Name -eq $draw.Buffer })
            if ($sourceVertexBuffer.Count -ne 1) {
                Fail-M20E1 "DX12 draw references vertex buffer '$($draw.Buffer)' but no matching DX12_VERTEX_BUFFER exists."
            }
            $bufferVertices = @($vertices | Where-Object { $_.Buffer -eq $draw.Buffer } | Sort-Object Index)
        }

        if ($bufferVertices.Count -lt 3) {
            Fail-M20E1 "M23C/M28A scene draw requires at least 3 vertices in buffer '$($draw.Buffer)'. Found $($bufferVertices.Count)."
        }
        for ($i = 0; $i -lt $bufferVertices.Count; $i++) {
            if ($bufferVertices[$i].Index -ne $i) {
                Fail-M20E1 "DX12_VERTEX entries for buffer '$($draw.Buffer)' must be contiguous from index 0. Expected $i, got $($bufferVertices[$i].Index)."
            }
            [void](Parse-VectorValue $bufferVertices[$i].Position 3 "DX12 vertex position")
            $colorValues = @(Parse-VectorValue $bufferVertices[$i].Color 4 "DX12 vertex color")
            foreach ($component in $colorValues) {
                if ($component -lt 0 -or $component -gt 1) { Fail-M20E1 "DX12 vertex color components must be between 0 and 1." }
            }
        }
        if ($draw.Vertices -lt 3 -or $draw.Vertices -gt $bufferVertices.Count) {
            Fail-M20E1 "DX12 draw for buffer '$($draw.Buffer)' requests $($draw.Vertices) vertices but buffer has $($bufferVertices.Count)."
        }

        $firstVertex = $combined.Count
        for ($i = 0; $i -lt $draw.Vertices; $i++) {
            $src = $bufferVertices[$i]
            $combined += [pscustomobject]@{
                Index = $combined.Count
                Buffer = $draw.Buffer
                Position = $src.Position
                Color = $src.Color
            }
        }
        if ([string]::IsNullOrWhiteSpace($nameForManifest)) { $nameForManifest = "draw_$($triangleDrawCalls.Count)" }
        $triangleObjectNames += $nameForManifest
        $transformIndex = 0
        if ($m24TransformIndexByObject.ContainsKey($nameForManifest)) { $transformIndex = $m24TransformIndexByObject[$nameForManifest] }
        $triangleDrawCalls += [pscustomobject]@{
            Object = $nameForManifest
            FirstVertex = $firstVertex
            VertexCount = $draw.Vertices
            Buffer = $draw.Buffer
            Pipeline = $draw.Pipeline
            TransformIndex = $transformIndex
        }
    }

    # M30B/M30C: lower existing M19 UI/style/layout metadata into a real DX12 overlay.
    # This bridge intentionally adds no public syntax: it consumes UI_OBJECT/UI_SET/UI_LAYOUT/STYLE/UI_PARENT/UI_DOCK/UI_EVENT.
    $layoutMap = New-StringMap
    foreach ($layout in $uiLayouts) {
        if ($layout.Unit -eq 'px' -or $layout.Property -in @('x','y','width','height','padding','margin','gap')) {
            $layoutMap[($layout.Target + '|' + $layout.Property)] = $layout.Value
        }
    }
    $contentMap = New-StringMap
    $checkedMap = New-StringMap
    $valueMap = New-StringMap
    $rangeMinMap = New-StringMap
    $rangeMaxMap = New-StringMap
    $placeholderMap = New-StringMap
    $optionMap = @{}
    foreach ($prop in $uiProperties) {
        if ($prop.Property -eq 'content') { $contentMap[$prop.Target] = $prop.Value }
        elseif ($prop.Property -eq 'checked') { $checkedMap[$prop.Target] = $prop.Value }
        elseif ($prop.Property -eq 'value') { $valueMap[$prop.Target] = $prop.Value }
        elseif ($prop.Property -eq 'placeholder') { $placeholderMap[$prop.Target] = $prop.Value }
        elseif ($prop.Property -eq 'range') {
            $parts = @(([string]$prop.Value).Split(','))
            if ($parts.Count -ge 2) {
                $rangeMinMap[$prop.Target] = $parts[0].Trim()
                $rangeMaxMap[$prop.Target] = $parts[1].Trim()
            }
        } elseif ($prop.Property -eq 'option') {
            if (-not $optionMap.ContainsKey($prop.Target)) { $optionMap[$prop.Target] = New-Object 'System.Collections.Generic.List[string]' }
            $optionMap[$prop.Target].Add($prop.Value)
        }
    }
    $styleMap = New-StringMap
    $hoverStyleMap = New-StringMap
    $pressedStyleMap = New-StringMap
    $disabledStyleMap = New-StringMap
    foreach ($style in $styleProperties) {
        if ($style.State -eq 'default') { $styleMap[($style.Target + '|' + $style.Property)] = $style.Value }
        elseif ($style.State -eq 'hovered') { $hoverStyleMap[($style.Target + '|' + $style.Property)] = $style.Value }
        elseif ($style.State -eq 'pressed') { $pressedStyleMap[($style.Target + '|' + $style.Property)] = $style.Value }
        elseif ($style.State -eq 'disabled') { $disabledStyleMap[($style.Target + '|' + $style.Property)] = $style.Value }
    }
    $enabledMap = New-StringMap
    $visibilityMap = New-StringMap
    $stateMap = New-StringMap
    foreach ($state in $uiStates) {
        if ($state.Property -eq 'enabled') { $enabledMap[$state.Target] = $state.Value }
        elseif ($state.Property -eq 'visibility') { $visibilityMap[$state.Target] = $state.Value }
        elseif ($state.Property -eq 'state') { $stateMap[$state.Target] = $state.Value }
        elseif ($state.Property -eq 'selected') { $checkedMap[$state.Target] = $state.Value }
    }
    foreach ($use in $uiResourceUses) {
        if ($use.Property -eq 'font') { $styleMap[($use.Target + '|font')] = $use.Resource }
        elseif ($use.Property -eq 'texture') { $styleMap[($use.Target + '|texture')] = $use.Resource }
    }
    $parentMap = New-StringMap
    foreach ($parent in $uiParents) { $parentMap[$parent.Child] = $parent.Parent }
    $uiTypeMap = New-StringMap
    foreach ($ui in $uiObjects) { $uiTypeMap[$ui.Name] = $ui.Type }
    $uiControlTypes = @('button','checkbox','slider','input field','dropdown')
    $fontResourcePathMap = New-StringMap
    $textureResourcePathMap = New-StringMap
    foreach ($resource in $uiResources) {
        if ($resource.Type -eq 'font') { $fontResourcePathMap[$resource.Name] = $resource.Path }
        elseif ($resource.Type -eq 'texture') { $textureResourcePathMap[$resource.Name] = $resource.Path }
    }

    function Get-UiTypeDefaultPadding {
        param([string]$Type)
        # M31C_UI_STYLE_BOX_MODEL: text/shape are content by default;
        # controls keep an authored-friendly inset so labels never sit on borders.
        if ($Type -eq 'text' -or $Type -eq 'shape') { return 0.0 }
        if ($Type -in $uiControlTypes) { return 8.0 }
        return 0.0
    }

    function Get-EffectiveUiStyleValue {
        param([string]$Target, [string]$Property, [string]$DefaultValue)
        $key = $Target + '|' + $Property
        $value = if ($styleMap.ContainsKey($key)) { [string]$styleMap[$key] } else { [string]$DefaultValue }
        # Compile-time state overlays are merged here. Runtime hover/pressed still use
        # the native feedback bridge; disabled state can safely affect the initial draw.
        if ($stateMap.ContainsKey($Target) -and ([string]$stateMap[$Target]).ToLowerInvariant() -eq 'disabled') {
            if ($disabledStyleMap.ContainsKey($key)) { $value = [string]$disabledStyleMap[$key] }
        }
        return $value
    }

    function Get-EffectiveUiStyleNumber {
        param([string]$Target, [string]$Property, [double]$DefaultValue)
        $value = Get-EffectiveUiStyleValue $Target $Property ([string]$DefaultValue)
        $parsed = 0.0
        if ([double]::TryParse(([string]$value), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { return [double]$parsed }
        return [double]$DefaultValue
    }

    function Get-EffectiveUiPadding {
        param([string]$Target)
        $type = if ($uiTypeMap.ContainsKey($Target)) { [string]$uiTypeMap[$Target] } else { '' }
        $defaultPadding = Get-UiTypeDefaultPadding $type
        $layoutPadding = Get-MapNumber $layoutMap $Target 'padding' $defaultPadding
        $padding = Get-EffectiveUiStyleNumber $Target 'padding' $layoutPadding
        return [Math]::Max(0.0, [double]$padding)
    }

    function Get-EffectiveUiBorderSize {
        param([string]$Target)
        return [Math]::Max(0.0, [double](Get-EffectiveUiStyleNumber $Target 'border size' 0.0))
    }

    function Get-EffectiveUiContentRect {
        param([string]$Target, $Rect)
        $inset = (Get-EffectiveUiPadding $Target) + (Get-EffectiveUiBorderSize $Target)
        return (New-UiContentRect $Rect $inset)
    }

    function Get-EffectiveUiTextScale {
        param([string]$Target, [double]$DefaultScale)
        $size = Get-EffectiveUiStyleNumber $Target 'size' 0.0
        if ($size -le 0.0) { $size = Get-EffectiveUiStyleNumber $Target 'font size' 0.0 }
        if ($size -gt 0.0) { return [Math]::Max(1.0, [Math]::Min(6.0, $size / 7.0)) }
        return [double]$DefaultScale
    }

    function Get-EffectiveUiHorizontalAlign {
        param([string]$Target, [string]$DefaultValue)
        $value = (Get-EffectiveUiStyleValue $Target 'text align' $DefaultValue).ToString().ToLowerInvariant()
        if ($value -in @('left','center','right')) { return $value }
        return $DefaultValue
    }

    function Get-EffectiveUiVerticalAlign {
        param([string]$Target, [string]$DefaultValue)
        $value = (Get-EffectiveUiStyleValue $Target 'vertical align' $DefaultValue).ToString().ToLowerInvariant()
        if ($value -eq 'middle') { return 'center' }
        if ($value -eq 'baseline') { return 'bottom' }
        if ($value -in @('top','center','bottom')) { return $value }
        return $DefaultValue
    }

    $dockMap = New-StringMap
    foreach ($dock in $uiDocks) { $dockMap[$dock.Target] = ($dock.Side + '|' + $dock.Parent) }
    $clickedTargets = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $clickedActionMap = New-StringMap
    foreach ($ev in $uiEvents) {
        if ($ev.Event -eq 'clicked') {
            [void]$clickedTargets.Add($ev.Target)
            $clickedActionMap[$ev.Target] = Resolve-UiAction $ev.Body
        }
    }

    function Get-ResolvedUiRect {
        param([string]$Name, $Resolving)
        if ($script:resolvedUiRects.ContainsKey($Name)) { return $script:resolvedUiRects[$Name] }
        if ($Resolving.Contains($Name)) { Fail-M20E1 "M30C UI parent/dock cycle reached while resolving '$Name'." }
        [void]$Resolving.Add($Name)
        $rawX = Get-MapNumber $layoutMap $Name 'x' 0.0
        $rawY = Get-MapNumber $layoutMap $Name 'y' 0.0
        $rawW = Get-MapNumber $layoutMap $Name 'width' 80.0
        $rawH = Get-MapNumber $layoutMap $Name 'height' 24.0
        if ($rawW -le 0 -or $rawH -le 0) { Fail-M20E1 "M30B/M30C UI object '$Name' must have positive width/height." }
        $rect = New-UiClipRect $rawX $rawY $rawW $rawH
        if ($dockMap.ContainsKey($Name)) {
            $parts = @($dockMap[$Name].Split('|'))
            $side = $parts[0]
            $parentName = $parts[1]
            $parentRect = if ($parentName -eq $ready.Window) { New-UiClipRect 0 0 $width $height } else { Get-ResolvedUiRect $parentName $Resolving }
            switch ($side) {
                'top' { $rect = New-UiClipRect $parentRect.X $parentRect.Y $parentRect.W $rawH }
                'bottom' { $rect = New-UiClipRect $parentRect.X ($parentRect.Y + $parentRect.H - $rawH) $parentRect.W $rawH }
                'left' { $rect = New-UiClipRect $parentRect.X $parentRect.Y $rawW $parentRect.H }
                'right' { $rect = New-UiClipRect ($parentRect.X + $parentRect.W - $rawW) $parentRect.Y $rawW $parentRect.H }
                'fill' { $rect = New-UiClipRect $parentRect.X $parentRect.Y $parentRect.W $parentRect.H }
                'center' { $rect = New-UiClipRect ($parentRect.X + (($parentRect.W - $rawW) * 0.5)) ($parentRect.Y + (($parentRect.H - $rawH) * 0.5)) $rawW $rawH }
                default { Fail-M20E1 "M30C unsupported UI dock side '$side'." }
            }
        } elseif ($parentMap.ContainsKey($Name)) {
            $parentName = $parentMap[$Name]
            $parentRect = if ($parentName -eq $ready.Window) { New-UiClipRect 0 0 $width $height } else { Get-ResolvedUiRect $parentName $Resolving }
            $parentContentRect = Get-EffectiveUiContentRect $parentName $parentRect
            $parentType = if ($uiTypeMap.ContainsKey($parentName)) { [string]$uiTypeMap[$parentName] } else { '' }
            $childType = if ($uiTypeMap.ContainsKey($Name)) { [string]$uiTypeMap[$Name] } else { '' }
            $hasExplicitRect = $layoutMap.ContainsKey($Name + '|x') -or $layoutMap.ContainsKey($Name + '|y') -or $layoutMap.ContainsKey($Name + '|width') -or $layoutMap.ContainsKey($Name + '|height')
            if ($childType -eq 'text' -and $parentType -in $uiControlTypes -and -not $hasExplicitRect) {
                # M31C: a text child parented to a control is treated as the
                # control content label by default. This lets authoring use
                # parent "Label" to "Button" without pixel-perfect math.
                $rect = New-UiClipRect $parentContentRect.X $parentContentRect.Y $parentContentRect.W $parentContentRect.H
            } else {
                $rect = New-UiClipRect ($parentContentRect.X + $rawX) ($parentContentRect.Y + $rawY) $rawW $rawH
            }
        }
        $script:resolvedUiRects[$Name] = $rect
        [void]$Resolving.Remove($Name)
        return $rect
    }

    function Get-ResolvedUiClip {
        param([string]$Name, $Resolving)
        if ($script:resolvedUiClips.ContainsKey($Name)) { return $script:resolvedUiClips[$Name] }
        if ($Resolving.Contains($Name)) { return $null }
        [void]$Resolving.Add($Name)
        $clip = $null
        $parentName = $null
        if ($parentMap.ContainsKey($Name)) { $parentName = $parentMap[$Name] }
        elseif ($dockMap.ContainsKey($Name)) { $parentName = @($dockMap[$Name].Split('|'))[1] }
        if (-not [string]::IsNullOrWhiteSpace($parentName) -and $parentName -ne $ready.Window) {
            $parentClip = Get-ResolvedUiClip $parentName $Resolving
            $clip = $parentClip
            # M31C_UI_PARENT_CONTAINMENT: parent means coordinate containment,
            # not just metadata. Children are clipped to the parent content box by
            # default, while explicit `overflow: visible` or `clip children: false`
            # can opt out for future authoring cases.
            $overflowValue = (Get-MapValue $styleMap $parentName 'overflow' 'hidden').ToString().ToLowerInvariant()
            $clipChildrenValue = (Get-MapValue $styleMap $parentName 'clip children' 'true').ToString().ToLowerInvariant()
            $parentClipsChildren = -not (($overflowValue -eq 'visible') -or ($clipChildrenValue -in @('false','no','0')))
            if ($parentClipsChildren) {
                $parentRect = Get-ResolvedUiRect $parentName (New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal))
                $parentContentClip = Get-EffectiveUiContentRect $parentName $parentRect
                $clip = Join-UiClipRect $clip $parentContentClip
            }
        }
        $script:resolvedUiClips[$Name] = $clip
        [void]$Resolving.Remove($Name)
        return $clip
    }

    $script:resolvedUiRects = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    $script:resolvedUiClips = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    $orderedUiObjects = @($uiObjects | ForEach-Object -Begin { $i = 0 } -Process {
        $z = [int](Get-EffectiveUiStyleNumber $_.Name 'z index' 0.0)
        [pscustomobject]@{ Ui = $_; Index = $i; ZIndex = $z }
        $i++
    } | Sort-Object ZIndex, Index)

    foreach ($entry in $orderedUiObjects) {
        $ui = $entry.Ui
        if ($visibilityMap.ContainsKey($ui.Name) -and ([string]$visibilityMap[$ui.Name]).ToLowerInvariant() -eq 'hidden') { continue }
        if ($stateMap.ContainsKey($ui.Name) -and ([string]$stateMap[$ui.Name]).ToLowerInvariant() -eq 'hidden') { continue }
        $hasRect = $layoutMap.ContainsKey($ui.Name + '|x') -and $layoutMap.ContainsKey($ui.Name + '|y') -and $layoutMap.ContainsKey($ui.Name + '|width') -and $layoutMap.ContainsKey($ui.Name + '|height')
        $smartParentText = $false
        if ($parentMap.ContainsKey($ui.Name) -and $ui.Type -eq 'text') {
            $parentNameForSmartLayout = $parentMap[$ui.Name]
            if ($uiTypeMap.ContainsKey($parentNameForSmartLayout) -and ([string]$uiTypeMap[$parentNameForSmartLayout]) -in $uiControlTypes) { $smartParentText = $true }
        }
        if (-not $hasRect -and -not $dockMap.ContainsKey($ui.Name) -and -not $smartParentText) { continue }
        $rect = Get-ResolvedUiRect $ui.Name (New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal))
        $x = [double]$rect.X; $y = [double]$rect.Y; $w = [double]$rect.W; $h = [double]$rect.H
        if ($w -le 0 -or $h -le 0) { continue }
        $clip = Get-ResolvedUiClip $ui.Name (New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal))
        $ownClip = Join-UiClipRect $clip (New-UiClipRect $x $y $w $h)
        # M31C_UI_STYLE_BOX_MODEL: one style resolver owns defaults/state/padding.
        # Text defaults to zero padding; controls default to 8px; border size is
        # part of the content inset so child text cannot sit on top of borders.
        $padding = Get-EffectiveUiPadding $ui.Name
        $borderSize = Get-EffectiveUiBorderSize $ui.Name
        $contentRect = Get-EffectiveUiContentRect $ui.Name $rect
        $opacity = Get-EffectiveUiStyleNumber $ui.Name 'opacity' 1.0
        if ($opacity -lt 0.0) { $opacity = 0.0 }
        if ($opacity -gt 1.0) { $opacity = 1.0 }
        $bgValue = Get-EffectiveUiStyleValue $ui.Name 'background color' '#15202A'
        $fgValue = Get-EffectiveUiStyleValue $ui.Name 'foreground color' '#E8FFFF'
        $borderValue = Get-EffectiveUiStyleValue $ui.Name 'border color' ''
        $bg = Format-ColorVector (Parse-UiColorRgba $bgValue $opacity)
        $fg = Format-ColorVector (Parse-UiColorRgba $fgValue 1.0)
        $z = 0.0
        $transformIndex = '0xFFFFFFFF'
        $content = if ($contentMap.ContainsKey($ui.Name)) { $contentMap[$ui.Name] } else { '' }
        # M31A polish: object names are implementation identifiers, not default labels.
        # Shapes/sliders without explicit content should stay visually silent; otherwise
        # panels draw their own names and the UI looks like it lost a fight with metadata.
        if ($ui.Type -eq 'input field') {
            if ($valueMap.ContainsKey($ui.Name)) { $content = $valueMap[$ui.Name] }
            elseif ($placeholderMap.ContainsKey($ui.Name)) { $content = $placeholderMap[$ui.Name] }
        } elseif ($ui.Type -eq 'dropdown') {
            if (-not $contentMap.ContainsKey($ui.Name) -and $optionMap.ContainsKey($ui.Name) -and $optionMap[$ui.Name].Count -gt 0) { $content = $optionMap[$ui.Name][0] }
        } elseif ($ui.Type -eq 'slider') {
            if (-not $contentMap.ContainsKey($ui.Name)) { $content = '' }
        } elseif ($ui.Type -eq 'shape') {
            if (-not $contentMap.ContainsKey($ui.Name)) { $content = '' }
        }
        $textScale = Get-EffectiveUiTextScale $ui.Name 2.5

        if ($ui.Type -in @('shape','button','checkbox','slider','input field','dropdown')) {
            $controlIndex = -1
            if ($ui.Type -in @('button','checkbox','slider','input field','dropdown')) {
                $action = if ($clickedActionMap.ContainsKey($ui.Name)) { $clickedActionMap[$ui.Name] } else { 'ARQEN_DX12_UI_ACTION_NONE' }
                $checked = if ($checkedMap.ContainsKey($ui.Name)) { if ($checkedMap[$ui.Name].ToLowerInvariant() -eq 'false') { 0 } else { 1 } } elseif ($ui.Type -eq 'checkbox') { 1 } else { 0 }
                $enabled = Get-MapEnabled $enabledMap $stateMap $ui.Name
                $controlType = Resolve-UiControlTypeLiteral $ui.Type
                $minValue = if ($rangeMinMap.ContainsKey($ui.Name)) { [double]::Parse($rangeMinMap[$ui.Name], [System.Globalization.CultureInfo]::InvariantCulture) } else { 0.0 }
                $maxValue = if ($rangeMaxMap.ContainsKey($ui.Name)) { [double]::Parse($rangeMaxMap[$ui.Name], [System.Globalization.CultureInfo]::InvariantCulture) } else { 1.0 }
                if ($ui.Type -ne 'slider') { $minValue = 0.0; $maxValue = 1.0 }
                if ($maxValue -le $minValue) { $maxValue = $minValue + 1.0 }
                $defaultValue = if ($ui.Type -eq 'checkbox' -and $checked -ne 0) { 1.0 } else { 0.0 }
                $controlValue = $defaultValue
                if ($ui.Type -eq 'slider' -and $valueMap.ContainsKey($ui.Name)) {
                    $parsedControlValue = 0.0
                    if (-not [double]::TryParse(([string]$valueMap[$ui.Name]), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedControlValue)) {
                        Fail-M20E1 "M31A slider value must be numeric."
                    }
                    $controlValue = [double]$parsedControlValue
                }
                if ($ui.Type -eq 'slider') { $controlValue = [Math]::Max($minValue, [Math]::Min($maxValue, $controlValue)) }
                $controlIndex = $m30UiControlRows.Count
                $controlTrackX = [double]$contentRect.X
                $controlTrackY = [double]$contentRect.Y
                $controlTrackW = [double]$contentRect.W
                $controlTrackH = [double]$contentRect.H
                if ($ui.Type -eq 'slider') {
                    $trackPadForControl = [Math]::Max(6.0, [Math]::Min(14.0, [double]$h * 0.25))
                    $trackHeightForControl = [Math]::Max(4.0, [Math]::Min(10.0, [double]$h * 0.24))
                    $controlTrackX = [double]$x + $trackPadForControl
                    $controlTrackW = [Math]::Max(1.0, [double]$w - (2.0 * $trackPadForControl))
                    $controlTrackY = [double]$y + (([double]$h - $trackHeightForControl) * 0.5)
                    $controlTrackH = $trackHeightForControl
                }
                $m30UiControlRows += ('{{ {0}, {1}, {2}, {3}, {4}, {5}, {6}, {7}, {8}, {9}, {10}u, {11}u, {12}, {13}, {14} }}' -f (Format-FloatLiteral $x), (Format-FloatLiteral $y), (Format-FloatLiteral $w), (Format-FloatLiteral $h), (Format-FloatLiteral $controlTrackX), (Format-FloatLiteral $controlTrackY), (Format-FloatLiteral $controlTrackW), (Format-FloatLiteral $controlTrackH), $controlType, $action, $checked, $enabled, (Format-FloatLiteral $controlValue), (Format-FloatLiteral $minValue), (Format-FloatLiteral $maxValue))
                $transformIndexBase = [uint64]2147483648
                $sliderFillTransformIndex = [string]($transformIndexBase + [uint64]268435456 + [uint64]$controlIndex)
                $sliderKnobTransformIndex = [string]($transformIndexBase + [uint64]536870912 + [uint64]$controlIndex)
                $transformIndex = [string]($transformIndexBase + [uint64]$controlIndex)
            }
            $first = $combined.Count
            $rectVerts = @(New-UiRectVerticesClipped $x $y $w $h $width $height $bg $z $clip)
            foreach ($v in $rectVerts) { $combined += $v }
            if ($rectVerts.Count -gt 0) { $triangleDrawCalls += [pscustomobject]@{ Object = $ui.Name; FirstVertex = $first; VertexCount = $rectVerts.Count; Buffer = '__generated_m30_ui'; Pipeline = $trianglePipeline.Name; TransformIndex = $transformIndex } }
            $textureVerts = @(New-UiTextureVertices $ui.Name $rect $width $height $z $ownClip $textureResourcePathMap)
            if ($textureVerts.Count -gt 0) {
                $texFirst = $combined.Count
                foreach ($v in $textureVerts) { $combined += $v }
                $triangleDrawCalls += [pscustomobject]@{ Object = ($ui.Name + '_texture'); FirstVertex = $texFirst; VertexCount = $textureVerts.Count; Buffer = '__generated_m30_ui'; Pipeline = $trianglePipeline.Name; TransformIndex = $transformIndex }
            }
            if (-not [string]::IsNullOrWhiteSpace($borderValue) -and $borderSize -gt 0.0) {
                $bc = Format-ColorVector (Parse-UiColorRgba $borderValue 1.0)
                $borderRects = @(
                    @([double]$x, [double]$y, [double]$w, [double]$borderSize),
                    @([double]$x, ([double]$y + [double]$h - [double]$borderSize), [double]$w, [double]$borderSize),
                    @([double]$x, [double]$y, [double]$borderSize, [double]$h),
                    @(([double]$x + [double]$w - [double]$borderSize), [double]$y, [double]$borderSize, [double]$h)
                )
                foreach ($r in $borderRects) {
                    $bf = $combined.Count
                    $bv = @(New-UiRectVerticesClipped $r[0] $r[1] $r[2] $r[3] $width $height $bc $z $clip)
                    foreach ($v in $bv) { $combined += $v }
                    if ($bv.Count -gt 0) { $triangleDrawCalls += [pscustomobject]@{ Object = ($ui.Name + '_border'); FirstVertex = $bf; VertexCount = $bv.Count; Buffer = '__generated_m30_ui'; Pipeline = $trianglePipeline.Name; TransformIndex = '0xFFFFFFFF' } }
                }
            }
            if ($ui.Type -eq 'slider') {
                $trackPad = [Math]::Max(6.0, [Math]::Min(14.0, [double]$h * 0.25))
                $trackH = [Math]::Max(4.0, [Math]::Min(10.0, [double]$h * 0.24))
                $trackX = [double]$x + $trackPad
                $trackW = [Math]::Max(1.0, [double]$w - (2.0 * $trackPad))
                $trackY = [double]$y + (([double]$h - $trackH) * 0.5)
                $ratio = if ($maxValue -gt $minValue) { ([double]$controlValue - [double]$minValue) / ([double]$maxValue - [double]$minValue) } else { 0.0 }
                $ratio = [Math]::Max(0.0, [Math]::Min(1.0, $ratio))
                $fillW = [Math]::Max(2.0, $trackW * $ratio)
                $fillColor = Format-ColorVector (Parse-UiColorRgba '#39D5FF' 0.88)
                $ff = $combined.Count
                $fv = @(New-UiRectVerticesClipped $trackX $trackY $fillW $trackH $width $height $fillColor $z $ownClip)
                foreach ($v in $fv) { $combined += $v }
                if ($fv.Count -gt 0) { $triangleDrawCalls += [pscustomobject]@{ Object = ($ui.Name + '_slider_fill'); FirstVertex = $ff; VertexCount = $fv.Count; Buffer = '__generated_m30_ui'; Pipeline = $trianglePipeline.Name; TransformIndex = $sliderFillTransformIndex } }
                $knobSize = [Math]::Max(10.0, [Math]::Min(18.0, [double]$h - 2.0 * $trackPad))
                $knobX = $trackX + ($trackW * $ratio) - ($knobSize * 0.5)
                $knobY = [double]$y + (([double]$h - $knobSize) * 0.5)
                $knobColor = Format-ColorVector (Parse-UiColorRgba '#E8FFFF' 1.0)
                $kf = $combined.Count
                $kv = @(New-UiRectVerticesClipped $knobX $knobY $knobSize $knobSize $width $height $knobColor $z $ownClip)
                foreach ($v in $kv) { $combined += $v }
                if ($kv.Count -gt 0) { $triangleDrawCalls += [pscustomobject]@{ Object = ($ui.Name + '_slider_knob'); FirstVertex = $kf; VertexCount = $kv.Count; Buffer = '__generated_m30_ui'; Pipeline = $trianglePipeline.Name; TransformIndex = $sliderKnobTransformIndex } }
            }
            if ($ui.Type -eq 'dropdown') {
                $arrowW = [Math]::Max(18.0, [Math]::Min(28.0, [double]$h))
                $arrowColor = Format-ColorVector (Parse-UiColorRgba '#39D5FF' 0.35)
                $af = $combined.Count
                $av = @(New-UiRectVerticesClipped ([double]$x + [double]$w - $arrowW) $y $arrowW $h $width $height $arrowColor $z $ownClip)
                foreach ($v in $av) { $combined += $v }
                if ($av.Count -gt 0) { $triangleDrawCalls += [pscustomobject]@{ Object = ($ui.Name + '_dropdown_arrow_box'); FirstVertex = $af; VertexCount = $av.Count; Buffer = '__generated_m30_ui'; Pipeline = $trianglePipeline.Name; TransformIndex = $transformIndex } }
            }
            if ($ui.Type -eq 'checkbox') {
                $knobColor = Format-ColorVector (Parse-UiColorRgba '#E8FFFF' 1.0)
                $knobSize = [Math]::Max(8.0, [Math]::Min(18.0, [double]$h - (2.0 * [double]$padding)))
                $knobX = [double]$x + [double]$w - [double]$padding - [double]$knobSize
                $knobY = [double]$y + (([double]$h - [double]$knobSize) * 0.5)
                $kf = $combined.Count
                $kv = @(New-UiRectVerticesClipped $knobX $knobY $knobSize $knobSize $width $height $knobColor $z $ownClip)
                foreach ($v in $kv) { $combined += $v }
                if ($kv.Count -gt 0) { $triangleDrawCalls += [pscustomobject]@{ Object = ($ui.Name + '_switch_knob'); FirstVertex = $kf; VertexCount = $kv.Count; Buffer = '__generated_m30_ui'; Pipeline = $trianglePipeline.Name; TransformIndex = $transformIndex } }
            }
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                $tf = $combined.Count
                $textRect = $contentRect
                $hAlign = Get-EffectiveUiHorizontalAlign $ui.Name 'left'
                $vAlign = Get-EffectiveUiVerticalAlign $ui.Name 'center'
                if ($ui.Type -eq 'button') {
                    $hAlign = Get-EffectiveUiHorizontalAlign $ui.Name 'center'
                    $vAlign = Get-EffectiveUiVerticalAlign $ui.Name 'center'
                } elseif ($ui.Type -eq 'checkbox') {
                    $knobReserve = [Math]::Max(26.0, [double]$h)
                    $textRect = New-UiClipRect $contentRect.X $contentRect.Y ([Math]::Max(0.0, [double]$contentRect.W - $knobReserve)) $contentRect.H
                } elseif ($ui.Type -eq 'dropdown') {
                    $arrowReserve = [Math]::Max(20.0, [Math]::Min(30.0, [double]$h))
                    $textRect = New-UiClipRect $contentRect.X $contentRect.Y ([Math]::Max(0.0, [double]$contentRect.W - $arrowReserve)) $contentRect.H
                }
                $textClip = Join-UiClipRect $ownClip $textRect
                $textVerts = @(New-UiEffectiveTextVertices $content $ui.Name $textRect $width $height $fg $textScale $z $hAlign $vAlign $textClip $fontResourcePathMap)
                foreach ($v in $textVerts) { $combined += $v }
                if ($textVerts.Count -gt 0) { $triangleDrawCalls += [pscustomobject]@{ Object = ($ui.Name + '_text'); FirstVertex = $tf; VertexCount = $textVerts.Count; Buffer = '__generated_m30_ui'; Pipeline = $trianglePipeline.Name; TransformIndex = '0xFFFFFFFF' } }
            }
        } elseif ($ui.Type -eq 'text') {
            $tf = $combined.Count
            $hAlign = Get-EffectiveUiHorizontalAlign $ui.Name 'left'
            $vAlign = Get-EffectiveUiVerticalAlign $ui.Name 'top'
            if ($parentMap.ContainsKey($ui.Name)) {
                $parentNameForText = $parentMap[$ui.Name]
                if ($uiTypeMap.ContainsKey($parentNameForText) -and ([string]$uiTypeMap[$parentNameForText]) -in $uiControlTypes) {
                    $hAlign = Get-EffectiveUiHorizontalAlign $ui.Name 'center'
                    $vAlign = Get-EffectiveUiVerticalAlign $ui.Name 'center'
                }
            }
            $textRect = $contentRect
            $textClip = Join-UiClipRect $ownClip $textRect
            $textVerts = @(New-UiEffectiveTextVertices $content $ui.Name $textRect $width $height $fg $textScale $z $hAlign $vAlign $textClip $fontResourcePathMap)
            foreach ($v in $textVerts) { $combined += $v }
            if ($textVerts.Count -gt 0) { $triangleDrawCalls += [pscustomobject]@{ Object = $ui.Name; FirstVertex = $tf; VertexCount = $textVerts.Count; Buffer = '__generated_m30_ui'; Pipeline = $trianglePipeline.Name; TransformIndex = '0xFFFFFFFF' } }
        }
    }
    if ($m30UiControlRows.Count -gt 0) {
        $m30UiControlData = "{ " + ($m30UiControlRows -join ', ') + " }"
        $m30UiControlCount = $m30UiControlRows.Count
    }
    $m30UiOverlayEnabled = @($triangleDrawCalls | Where-Object { $_.Buffer -eq '__generated_m30_ui' }).Count -gt 0
    $m30dEventBodyActionCount = @($uiEvents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Body) }).Count
    $m31aExpandedControlCount = @($uiObjects | Where-Object { $_.Type -in @('slider','input field','dropdown') }).Count
    $m31bResourceBridgeEnabled = [bool]($uiResources.Count -gt 0 -or $uiResourceUses.Count -gt 0)
    $triangleVertices = @($combined)
    if ($triangleVertices.Count -lt 3) {
        Fail-M20E1 "M23C scene generated merged vertex buffer is empty."
    }
    $triangleDraw = $triangleDraws[0]
    $triangleDrawCount = ($triangleDrawCalls | ForEach-Object { $_.VertexCount } | Measure-Object -Sum).Sum
    $uniqueBuffers = @($sourceBufferNames | Sort-Object -Unique)
    $triangleVertexBuffer = [pscustomobject]@{ Name = if ($uniqueBuffers.Count -eq 1) { $uniqueBuffers[0] } else { "M23MergedSceneVertices" } }

    $matchingConstantBufferBinds = @($constantBufferBinds | Where-Object { $_.Pipeline -eq $trianglePipeline.Name })
    if ($matchingConstantBufferBinds.Count -gt 1) {
        Fail-M20E1 "DX12 pipeline '$($trianglePipeline.Name)' has more than one M21G constant buffer binding."
    }
    if ($matchingConstantBufferBinds.Count -eq 1) {
        $cbName = $matchingConstantBufferBinds[0].Buffer
        $allBindsForBuffer = @($constantBufferBinds | Where-Object { $_.Buffer -eq $cbName })
        if ($allBindsForBuffer.Count -ne 1) {
            Fail-M20E1 "DX12 color animation smoke path requires constant buffer '$cbName' to be bound to exactly one pipeline. Found $($allBindsForBuffer.Count)."
        }
        $matchingConstantBuffers = @($constantBuffers | Where-Object { $_.Name -eq $cbName -and $_.Field -eq 'tint' -and $_.Type -eq 'color4' })
        if ($matchingConstantBuffers.Count -ne 1) {
            Fail-M20E1 "DX12 constant buffer bind references '$cbName' but no color4 tint buffer exists."
        }
        $tintBuffer = $matchingConstantBuffers[0]
        $tintColor = Parse-HexColorRgb $tintBuffer.Value

        $orphanAnimations = @($animateColors | Where-Object { $_.Buffer -ne $tintBuffer.Name -or $_.Field -ne 'tint' })
        if ($orphanAnimations.Count -gt 0) {
            $target = $orphanAnimations[0].Target
            Fail-M20E1 "DX12 color animation target '$target' is not the selected renderer tint constant buffer '$($tintBuffer.Name).tint'."
        }

        $matchingAnimations = @($animateColors | Where-Object { $_.Buffer -eq $tintBuffer.Name -and $_.Field -eq 'tint' })
        if ($matchingAnimations.Count -gt 1) {
            Fail-M20E1 "DX12 color target '$($tintBuffer.Name).tint' has more than one animation."
        }
        if ($matchingAnimations.Count -eq 1) {
            $animation = $matchingAnimations[0]
            if ($animation.EveryFrames -lt 1) { Fail-M20E1 "DX12 color animation interval must be positive." }
            $sequence = @($colorSequences | Where-Object { $_.Name -eq $animation.Sequence })
            if ($sequence.Count -ne 1) { Fail-M20E1 "DX12 color animation references missing sequence '$($animation.Sequence)'." }
            $animationColors = @($colorKeys | Where-Object { $_.Sequence -eq $animation.Sequence } | Sort-Object Index)
            if ($animationColors.Count -lt 2) { Fail-M20E1 "DX12 color animation sequence '$($animation.Sequence)' must contain at least two colors." }
            for ($i = 0; $i -lt $animationColors.Count; $i++) {
                if ($animationColors[$i].Index -ne $i) { Fail-M20E1 "DX12 color sequence '$($animation.Sequence)' keys must be contiguous from index 0." }
                [void](Parse-HexColorRgb $animationColors[$i].Value)
            }
        }
    }

    $resolvedVertexShader = Resolve-ShaderSourcePath $repoRoot $triangleShader.Vertex "vertex"
    $resolvedPixelShader = Resolve-ShaderSourcePath $repoRoot $triangleShader.Pixel "pixel"
    $triangleMode = if ($m23ObjectMode -or $triangleDrawCalls.Count -gt 1) { "native_m23_scene_multi_draw" } else { "native_triangle_smoke" }
}

$color = Parse-HexColorRgb $ready.Value
$width = 960
$height = 540
if ($windowSizes.ContainsKey($ready.Window)) {
    $size = $windowSizes[$ready.Window]
    if ($size -notmatch '^(\d+)x(\d+)$') {
        Fail-M20E1 "window resolution for '$($ready.Window)' must be WIDTHxHEIGHT, got '$size'."
    }
    $width = [int]$Matches[1]
    $height = [int]$Matches[2]
    if ($width -le 0 -or $height -le 0) {
        Fail-M20E1 "window resolution for '$($ready.Window)' must be positive."
    }
}
$title = if ($windowTitles.ContainsKey($ready.Window)) { $windowTitles[$ready.Window] } else { "Arqen DX12 Clear" }

$manifestPath = Join-Path $OutDir "dx12_clear_manifest.generated.txt"
$configPath = Join-Path $OutDir "dx12_clear_config.generated.h"

$floatLine = "{0},{1},{2},{3}" -f (Format-FloatLiteral $color.R), (Format-FloatLiteral $color.G), (Format-FloatLiteral $color.B), (Format-FloatLiteral $color.A)
$diagnosticsFlag = if ($Diagnostics) { 1 } else { 0 }
$keepOpenFlag = if ($KeepOpen) { 1 } else { 0 }
$triangleEnabled = if ($RequireTriangle) { 1 } else { 0 }
$frameRequiredFlag = [bool]($RequireFrame -or $RequireTriangle)
$triangleShaderName = if ($triangleShader) { $triangleShader.Name } else { "" }
$trianglePipelineName = if ($trianglePipeline) { $trianglePipeline.Name } else { "" }
$trianglePipelineTopology = if ($trianglePipeline) { $trianglePipeline.Topology } else { "" }
$triangleVertexBufferName = if ($triangleVertexBuffer) { $triangleVertexBuffer.Name } else { "" }
$triangleDrawCount = if ($triangleDrawCalls.Count -gt 0) { [int](($triangleDrawCalls | ForEach-Object { $_.VertexCount } | Measure-Object -Sum).Sum) } elseif ($triangleDraw) { $triangleDraw.Vertices } else { 0 }
$tintEnabled = if ($tintBuffer) { 1 } else { 0 }
$tintBufferName = if ($tintBuffer) { $tintBuffer.Name } else { "" }
$tintColorFloat = "1.000000f,1.000000f,1.000000f,1.000000f"
if ($tintBuffer) { $tintColorFloat = "{0},{1},{2},{3}" -f (Format-FloatLiteral $tintColor.R), (Format-FloatLiteral $tintColor.G), (Format-FloatLiteral $tintColor.B), (Format-FloatLiteral $tintColor.A) }
$animationEnabled = if ($animation) { 1 } else { 0 }
$animationSequenceName = if ($animation) { $animation.Sequence } else { "" }
$animationEveryFrames = if ($animation) { $animation.EveryFrames } else { 0 }
$animationColorData = "{ { 1.000000f, 1.000000f, 1.000000f, 1.000000f } }"
$animationColorCount = 0
if ($animation) {
    $animationRows = @()
    foreach ($key in $animationColors) {
        $c = Parse-HexColorRgb $key.Value
        $animationRows += ("{{ {0}, {1}, {2}, {3} }}" -f (Format-FloatLiteral $c.R), (Format-FloatLiteral $c.G), (Format-FloatLiteral $c.B), (Format-FloatLiteral $c.A))
    }
    $animationColorData = "{ " + ($animationRows -join ", ") + " }"
    $animationColorCount = $animationColors.Count
}
$vertexData = "{}"
if ($RequireTriangle) {
    $vertexRows = @()
    foreach ($vertex in $triangleVertices) {
        $pos = @(Parse-VectorValue $vertex.Position 3 "DX12 vertex position")
        $col = @(Parse-VectorValue $vertex.Color 4 "DX12 vertex color")
        $vertexRows += ("{{ {0}, {1}, {2}, {3}, {4}, {5}, {6} }}" -f (Format-FloatLiteral $pos[0]), (Format-FloatLiteral $pos[1]), (Format-FloatLiteral $pos[2]), (Format-FloatLiteral $col[0]), (Format-FloatLiteral $col[1]), (Format-FloatLiteral $col[2]), (Format-FloatLiteral $col[3]))
    }
    $vertexData = "{ " + ($vertexRows -join ", ") + " }"
}
$drawCallData = "{ { 0u, 0u } }"
$drawCallCount = 0
$m23ObjectModeFlag = if ($m23ObjectMode) { 1 } else { 0 }
$m24SceneRuntimeFlag = if ($m24TransformEnabled -or $m25CameraEnabled -or $m26KeyboardEnabled -or $m27PerspectiveEnabled -or $m28bPeripheralInputEnabled -or $m29FakeLightingEnabled -or $m29cObjectSelectorEnabled) { 1 } else { 0 }
$m25CameraEnabledFlag = if ($m25CameraEnabled) { 1 } else { 0 }
$m26KeyboardEnabledFlag = if ($m26KeyboardEnabled) { 1 } else { 0 }
$m28bPeripheralInputEnabledFlag = if ($m28bPeripheralInputEnabled) { 1 } else { 0 }
$m28bMouseCaptureEnabledFlag = if ($m28bMouseCaptureEnabled) { 1 } else { 0 }
$m29bViewportNavigationEnabled = $m28bMouseCaptureEnabled -and $m28bMouseMoveCount -gt 0 -and $m26KeyboardEnabled -and $m27PerspectiveEnabled
$m29bViewportNavigationEnabledFlag = if ($m29bViewportNavigationEnabled) { 1 } else { 0 }
$m29cObjectSelectorEnabledFlag = if ($m29cObjectSelectorEnabled) { 1 } else { 0 }
$m29FakeLightingEnabledFlag = if ($m29FakeLightingEnabled) { 1 } else { 0 }
$m29LightData = Format-DirectionalLightLiteral $m29LightDirection $m29LightIntensity $m29LightAmbient
$m28cRotation3dEnabled = @($objectTransforms | Where-Object { $_.Property -eq "rotation" -or $_.Property -eq "rotation_x" -or $_.Property -eq "rotation_y" }).Count -gt 0
$m27PerspectiveEnabledFlag = if ($m27PerspectiveEnabled) { 1 } else { 0 }
$m27DepthEnabledFlag = if ($m27DepthEnabled) { 1 } else { 0 }
$m27PerspectiveCameraData = Format-PerspectiveCameraLiteral $m25CameraPosition $m27CameraRotation $m27CameraFovYDegrees $m27CameraNearPlane $m27CameraFarPlane
$m28BoxPrimitiveCount = @($objectPrimitives | Where-Object { $_.Kind -eq "box" }).Count
$m27dTitleBarColor = if ($windowTitleBarColors.ContainsKey($ready.Window)) { $windowTitleBarColors[$ready.Window] } else { "" }
$m27dTitleTextColor = if ($windowTitleTextColors.ContainsKey($ready.Window)) { $windowTitleTextColors[$ready.Window] } else { "" }
$m27dTitleBarEnabled = -not [string]::IsNullOrWhiteSpace($m27dTitleBarColor)
$m27dTitleTextEnabled = -not [string]::IsNullOrWhiteSpace($m27dTitleTextColor)
if ($m27dTitleBarEnabled) { [void](Parse-HexColorRgb $m27dTitleBarColor) }
if ($m27dTitleTextEnabled) { [void](Parse-HexColorRgb $m27dTitleTextColor) }
$m27dTitleBarEnabledFlag = if ($m27dTitleBarEnabled) { 1 } else { 0 }
$m27dTitleTextEnabledFlag = if ($m27dTitleTextEnabled) { 1 } else { 0 }
$m28BoxPrimitiveEnabledFlag = if ($m28BoxPrimitiveEnabled) { 1 } else { 0 }
$m30UiOverlayEnabledFlag = if ($m30UiOverlayEnabled) { 1 } else { 0 }
$m23MultiDrawFlag = 0
if ($RequireTriangle) {
    $drawCallRows = @()
    foreach ($drawCall in $triangleDrawCalls) {
        $transformLiteral = if ([string]$drawCall.TransformIndex -match '^0x|^[0-9]+$') { ([string]$drawCall.TransformIndex) + 'u' } else { ('{0}u' -f [int]$drawCall.TransformIndex) }
        $drawCallRows += ("{{ {0}u, {1}u, {2} }}" -f [int]$drawCall.FirstVertex, [int]$drawCall.VertexCount, $transformLiteral)
    }
    if ($drawCallRows.Count -gt 0) {
        $drawCallData = "{ " + ($drawCallRows -join ", ") + " }"
        $drawCallCount = $drawCallRows.Count
    }
    $m23MultiDrawFlag = if ($drawCallCount -gt 1 -or $m23ObjectMode) { 1 } else { 0 }
}
$manifest = @(
    "M20E1_DX12_CLEAR_MANIFEST",
    "IR|$((Resolve-Path $IrPath).Path)",
    "TARGET|$targetName",
    "SOURCE|$sourcePath",
    "RENDERER|$($ready.Renderer)",
    "WINDOW|$($ready.Window)",
    "TITLE|$title",
    "WIDTH|$width",
    "HEIGHT|$height",
    "COLOR_HEX|$($ready.Value)",
    "COLOR_FLOAT|$floatLine",
    "CLEAR_SOURCE|$($ready.Source)",
    "FRAME_REQUIRED|$frameRequiredFlag",
    "FRAME_MODE|$frameMode",
    "FRAME_SEQUENCE|$frameSequence",
    "TRIANGLE_MODE|$triangleMode",
    "SHADER|$triangleShaderName",
    "VERTEX_SHADER|$resolvedVertexShader",
    "PIXEL_SHADER|$resolvedPixelShader",
    "PIPELINE|$trianglePipelineName",
    "TOPOLOGY|$trianglePipelineTopology",
    "VERTEX_BUFFER|$triangleVertexBufferName",
    "VERTEX_COUNT|$($triangleVertices.Count)",
    "DRAW_VERTICES|$triangleDrawCount",
    "CONSTANT_BUFFER|$tintBufferName",
    "TINT_ENABLED|$([bool]$tintBuffer)",
    "TINT_COLOR_FLOAT|$tintColorFloat",
    "COLOR_ANIMATION|$([bool]$animation)",
    "COLOR_SEQUENCE|$animationSequenceName",
    "COLOR_EVERY_FRAMES|$animationEveryFrames",
    "COLOR_KEY_COUNT|$animationColorCount",
    "M21I_SMOKE_POLISH|True",
    "M21I_RUNTIME_KNOBS|frames=$effectiveFrameCount|fps=$TargetFps|hold_ms=$HoldMilliseconds",
    "M21I_COLOR_TICK|every_frames=$animationEveryFrames|keys=$animationColorCount",
    "M21J_ANIMATION_HARDENING|selected_tint_only|single_pipeline_binding",
    "M22_MINI_SCENE|True",
    "M22_KEEP_OPEN|$([bool]$KeepOpen)",
    "M22_FRAME_MODE|$m22FrameMode",
    "M22_VERTEX_CLUSTER|vertices=$($triangleVertices.Count)|draw=$triangleDrawCount",
    "M23_SCENE_OBJECTS|$($objects.Count)",
    "M23_OBJECT_BINDINGS|$($objectBindings.Count)",
    "M23_DRAW_CALLS|$drawCallCount",
    "M23_OBJECT_MODE|$([bool]$m23ObjectMode)",
    "M23_MULTI_DRAW|$([bool]($m23MultiDrawFlag -eq 1))",
    "M24_TRANSFORM_RUNTIME|$([bool]$m24TransformEnabled)",
    "M24_TRANSFORM_COUNT|$m24TransformCount",
    "M25_ORTHOGRAPHIC_CAMERA|$([bool]$m25CameraEnabled)",
    "M25_CAMERA|$m25CameraName",
    "M25_CAMERA_POSITION|$(($m25CameraPosition | ForEach-Object { Format-FloatLiteral $_ }) -join ',')",
    "M25_CAMERA_ZOOM|$(Format-FloatLiteral $m25CameraZoom)",
    "M26_KEYBOARD_INPUT|$([bool]$m26KeyboardEnabled)",
    "M26_KEY_BINDINGS|$m26KeyBindingCount",
    "M28B_PERIPHERAL_INPUT|$([bool]$m28bPeripheralInputEnabled)",
    "M28B_MOUSE_CAPTURE|$([bool]$m28bMouseCaptureEnabled)",
    "M28B_MOUSE_MOVE_BINDINGS|$m28bMouseMoveCount",
    "M28B_MOUSE_BUTTON_BINDINGS|$m28bMouseButtonCount",
    "M28B_MOUSE_WHEEL_BINDINGS|$m28bMouseWheelCount",
    "M29B_UE_STYLE_VIEWPORT_NAVIGATION|$([bool]$m29bViewportNavigationEnabled)",
    "M29B_CAMERA_RELATIVE_MOVEMENT|$([bool]$m29bViewportNavigationEnabled)",
    "M29B_RMB_HOLD_NAVIGATION|$([bool]$m29bViewportNavigationEnabled)",
    "M29C_OBJECT_SELECTOR|$([bool]$m29cObjectSelectorEnabled)",
    "M29C_SELECTOR|$m29cObjectSelectorName",
    "M29C_SELECT_BINDINGS|$m29cObjectSelectBindingCount",
    "M29C_ROTATE_BINDINGS|$m29cSelectedObjectRotateCount",
    "M30A_UI_OVERLAY|$([bool]$m30UiOverlayEnabled)",
    "M30A_UI_CONTROLS|$m30UiControlCount",
    "M30A_UI_TEXT_BITMAP|True",
    "M30B_UI_LAYOUT_HYGIENE|True",
    "M30B_TEXT_CLIPPING|True",
    "M30B_Z_INDEX_DRAW_ORDER|True",
    "M30C_UI_PARENT_CLIP_BRIDGE|True",
    "M30C_PARENT_RELATIVE_LAYOUT|$([bool]($uiParents.Count -gt 0))",
    "M30C_UI_DOCK_BRIDGE|$([bool]($uiDocks.Count -gt 0))",
    "M30D_UI_CLICK_EVENT_BRIDGE|$([bool]($uiEvents.Count -gt 0))",
    "M30D_UI_EVENT_BODY_ACTIONS|$([bool]($m30dEventBodyActionCount -gt 0))",
    "M31A_UI_CONTROLS_EXPANSION|$([bool]($m31aExpandedControlCount -gt 0))",
    "M31A_UI_HOVER_PRESS_FOCUS_STATES|True",
    "M31C_UI_COMPUTED_LAYOUT_RECTS|True",
    "M31C_UI_PARENT_CONTAINMENT|True",
    "M31C_UI_TEXT_PADDING_DEFAULTS|True",
    "M31C_UI_STYLE_BOX_MODEL|True",
    "M31C_UI_SLIDER_TRACK_RECT|True",
    "M31C_UI_SLIDER_RUNTIME_VISUALS|True",
    "M31C_UI_STABLE_CLIENT_PIXEL_SPACE|True",
    "M32A_DX12_RASTER_FONT_ENGINE|$([bool]($fontResourcePathMap.Count -gt 0))",
    "M32A_DX12_TEXTURE_RESOURCE_COMMAND|$([bool]($textureResourcePathMap.Count -gt 0))",
    "M32A_DX12_FONT_STYLE_COMMANDS|True",
    "M31B_UI_RESOURCE_METADATA_BRIDGE|$([bool]$m31bResourceBridgeEnabled)",
    "M28C_OBJECT_ROTATION_3D|$([bool]$m28cRotation3dEnabled)",
    "M29_FAKE_LIGHTING|$([bool]$m29FakeLightingEnabled)",
    "M29_DIRECTIONAL_LIGHT|$m29LightName",
    "M29_LIGHT_DIRECTION|$(($m29LightDirection | ForEach-Object { Format-FloatLiteral $_ }) -join ',')",
    "M29_LIGHT_INTENSITY|$(Format-FloatLiteral $m29LightIntensity)",
    "M29_LIGHT_AMBIENT|$(Format-FloatLiteral $m29LightAmbient)",
    "M27_DEPTH_BUFFER|$([bool]$m27DepthEnabled)",
    "M27_CAMERA_PROJECTION|$m27CameraProjection",
    "M27_PERSPECTIVE_CAMERA|$([bool]$m27PerspectiveEnabled)",
    "M27_CAMERA_ROTATION|$(($m27CameraRotation | ForEach-Object { Format-FloatLiteral $_ }) -join ',')",
    "M27_CAMERA_FOV|$(Format-FloatLiteral $m27CameraFovYDegrees)",
    "M27_CAMERA_NEAR|$(Format-FloatLiteral $m27CameraNearPlane)",
    "M27_CAMERA_FAR|$(Format-FloatLiteral $m27CameraFarPlane)",
    "M27D_NATIVE_WINDOW_STYLE|$([bool]($m27dTitleBarEnabled -or $m27dTitleTextEnabled))",
    "M27D_TITLE_BAR_COLOR|$m27dTitleBarColor",
    "M27D_TITLE_TEXT_COLOR|$m27dTitleTextColor",
    "M28_BOX_PRIMITIVE|$([bool]$m28BoxPrimitiveEnabled)",
    "M28_BOX_PRIMITIVE_COUNT|$m28BoxPrimitiveCount",
    "HOLD_MS|$HoldMilliseconds",
    "DIAGNOSTICS|$([bool]$Diagnostics)",
    "STANDALONE_EXE|True",
    "SHADER_FALLBACK|exe_dir_shaders",
    "FRAME_LOOP_MODE|$m22FrameMode",
    "FRAME_COUNT|$effectiveFrameCount",
    "TARGET_FPS|$TargetFps",
    "STATUS|ready_for_native_dx12_clear_bridge"
)
if ($RequireTriangle) {
    foreach ($vertex in $triangleVertices) {
        $manifest += "VERTEX_$($vertex.Index)|position=$($vertex.Position)|color=$($vertex.Color)"
    }
    foreach ($object in $objects) {
        $manifest += "OBJECT|name=$($object.Name)"
    }
    foreach ($primitive in $objectPrimitives) {
        $manifest += "OBJECT_PRIMITIVE|object=$($primitive.Object)|kind=$($primitive.Kind)"
    }
    foreach ($binding in $objectBindings) {
        $manifest += "OBJECT_BIND|object=$($binding.Object)|renderer=$($binding.Renderer)|pipeline=$($binding.Pipeline)|buffer=$($binding.Buffer)|vertices=$($binding.Vertices)"
    }
    for ($i = 0; $i -lt $triangleDrawCalls.Count; $i++) {
        $drawCall = $triangleDrawCalls[$i]
        $manifest += "DRAW_CALL_$i|object=$($drawCall.Object)|first=$($drawCall.FirstVertex)|vertices=$($drawCall.VertexCount)|buffer=$($drawCall.Buffer)|pipeline=$($drawCall.Pipeline)|transform=$($drawCall.TransformIndex)"
    }
    for ($i = 0; $i -lt $m24TransformRows.Count; $i++) {
        $manifest += "TRANSFORM_$i|object=$($m24TransformNames[$i])|data=$($m24TransformRows[$i])"
    }
    foreach ($binding in $keyBindings) {
        $manifest += "KEY_BINDING|key=$($binding.Key)|action=$($binding.Action)|target=$($binding.Target)|delta=$($binding.Delta)"
    }
    foreach ($capture in $mouseCaptures) {
        $manifest += "MOUSE_CAPTURE|window=$($capture.Window)"
    }
    foreach ($move in $mouseMoveBindings) {
        $manifest += "MOUSE_MOVE|target=$($move.Target)|sensitivity=$($move.Sensitivity)"
    }
    foreach ($button in $mouseButtonBindings) {
        $manifest += "MOUSE_BUTTON|button=$($button.Button)|action=$($button.Action)|target=$($button.Target)|delta=$($button.Delta)"
    }
    foreach ($wheel in $mouseWheelBindings) {
        $manifest += "MOUSE_WHEEL|action=$($wheel.Action)|target=$($wheel.Target)|delta=$($wheel.Delta)"
    }
    foreach ($selector in $objectSelectors) {
        $manifest += "OBJECT_SELECTOR|name=$($selector.Name)"
    }
    foreach ($selectorUse in $objectSelectorUses) {
        $manifest += "OBJECT_SELECTOR_USE|selector=$($selectorUse.Selector)|renderer=$($selectorUse.Renderer)"
    }
    foreach ($select in $objectSelectionBindings) {
        $manifest += "OBJECT_SELECT_BINDING|button=$($select.Button)|selector=$($select.Selector)"
    }
    foreach ($rotate in $selectedObjectRotateBindings) {
        $manifest += "SELECTED_OBJECT_ROTATE|key=$($rotate.Key)|axis=$($rotate.Axis)|mouse_axis=$($rotate.MouseAxis)|sensitivity=$($rotate.Sensitivity)"
    }
    foreach ($key in $animationColors) {
        $manifest += "COLOR_KEY_$($key.Index)|sequence=$($key.Sequence)|value=$($key.Value)"
    }
}
[System.IO.File]::WriteAllLines($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))

$config = @(
    '#pragma once',
    '// Generated by Tools/Lowering/DX12/lower_m20e1_dx12_clear_from_ir.ps1. Do not hand-edit.',
    ('#define ARQEN_M20E1_RENDERER_NAME "{0}"' -f (Escape-CString $ready.Renderer)),
    ('#define ARQEN_M20E1_WINDOW_NAME "{0}"' -f (Escape-CString $ready.Window)),
    ('#define ARQEN_M20E1_WINDOW_TITLE L"{0}"' -f (Escape-CString $title)),
    ('#define ARQEN_M20E1_WINDOW_WIDTH {0}' -f $width),
    ('#define ARQEN_M20E1_WINDOW_HEIGHT {0}' -f $height),
    ('#define ARQEN_M20E1_CLEAR_HEX "{0}"' -f (Escape-CString $ready.Value)),
    ('#define ARQEN_M20E1_CLEAR_R {0}' -f (Format-FloatLiteral $color.R)),
    ('#define ARQEN_M20E1_CLEAR_G {0}' -f (Format-FloatLiteral $color.G)),
    ('#define ARQEN_M20E1_CLEAR_B {0}' -f (Format-FloatLiteral $color.B)),
    ('#define ARQEN_M20E1_CLEAR_A {0}' -f (Format-FloatLiteral $color.A)),
    ('#define ARQEN_M20E1_CLEAR_SOURCE "{0}"' -f (Escape-CString $ready.Source)),
    ('#define ARQEN_M20H_FRAME_MODE "{0}"' -f (Escape-CString $frameMode)),
    ('#define ARQEN_M20H_FRAME_SEQUENCE "{0}"' -f (Escape-CString $frameSequence)),
    ('#define ARQEN_M21D_TRIANGLE_ENABLED {0}' -f $triangleEnabled),
    ('#define ARQEN_M21D_TRIANGLE_MODE "{0}"' -f (Escape-CString $triangleMode)),
    ('#define ARQEN_M21B_SHADER_NAME "{0}"' -f (Escape-CString $triangleShaderName)),
    ('#define ARQEN_M21B_VERTEX_SHADER_PATH L"{0}"' -f (Escape-WideCString $resolvedVertexShader)),
    ('#define ARQEN_M21B_PIXEL_SHADER_PATH L"{0}"' -f (Escape-WideCString $resolvedPixelShader)),
    ('#define ARQEN_M21B_PIPELINE_NAME "{0}"' -f (Escape-CString $trianglePipelineName)),
    ('#define ARQEN_M21B_PIPELINE_TOPOLOGY "{0}"' -f (Escape-CString $trianglePipelineTopology)),
    ('#define ARQEN_M21C_VERTEX_BUFFER_NAME "{0}"' -f (Escape-CString $triangleVertexBufferName)),
    ('#define ARQEN_M21C_VERTEX_COUNT {0}' -f $triangleVertices.Count),
    ('#define ARQEN_M21C_DRAW_VERTEX_COUNT {0}' -f $triangleDrawCount),
    ('#define ARQEN_M21C_VERTEX_DATA {0}' -f $vertexData),
    ('#define ARQEN_M21G_TINT_ENABLED {0}' -f $tintEnabled),
    ('#define ARQEN_M21G_CONSTANT_BUFFER_NAME "{0}"' -f (Escape-CString $tintBufferName)),
    ('#define ARQEN_M21G_TINT_COLOR {{ {0} }}' -f $tintColorFloat),
    ('#define ARQEN_M21H_COLOR_ANIMATION_ENABLED {0}' -f $animationEnabled),
    ('#define ARQEN_M21H_COLOR_SEQUENCE_NAME "{0}"' -f (Escape-CString $animationSequenceName)),
    ('#define ARQEN_M21H_COLOR_EVERY_FRAMES {0}' -f $animationEveryFrames),
    ('#define ARQEN_M21H_COLOR_COUNT {0}' -f $animationColorCount),
    ('#define ARQEN_M21H_COLOR_DATA {0}' -f $animationColorData),
    '#define ARQEN_M21I_SMOKE_POLISH 1',
    '#define ARQEN_M21I_RUNTIME_KNOBS_ENABLED 1',
    ('#define ARQEN_M21I_FRAME_COUNT {0}' -f $effectiveFrameCount),
    ('#define ARQEN_M21I_TARGET_FPS {0}' -f $TargetFps),
    ('#define ARQEN_M21I_COLOR_KEY_COUNT {0}' -f $animationColorCount),
    '#define ARQEN_M21J_ANIMATION_HARDENING 1',
    '#define ARQEN_M22_MINI_SCENE 1',
    ('#define ARQEN_M22_KEEP_OPEN {0}' -f $keepOpenFlag),
    ('#define ARQEN_M22_FRAME_MODE "{0}"' -f (Escape-CString $m22FrameMode)),
    ('#define ARQEN_M22_VERTEX_CLUSTER_COUNT {0}' -f $triangleVertices.Count),
    '#define ARQEN_M23_OBJECT_METADATA 1',
    ('#define ARQEN_M23_OBJECT_COUNT {0}' -f $objects.Count),
    ('#define ARQEN_M23_OBJECT_MODE {0}' -f $m23ObjectModeFlag),
    ('#define ARQEN_M23_MULTI_DRAW_ENABLED {0}' -f $m23MultiDrawFlag),
    ('#define ARQEN_M23_DRAW_CALL_COUNT {0}' -f $drawCallCount),
    ('#define ARQEN_M23_DRAW_CALL_DATA {0}' -f $drawCallData),
    '#define ARQEN_M24_TRANSFORM_RUNTIME 1',
    ('#define ARQEN_M24_TRANSFORM_RUNTIME_ENABLED {0}' -f $m24SceneRuntimeFlag),
    ('#define ARQEN_M24_OBJECT_TRANSFORM_COUNT {0}' -f $m24TransformCount),
    ('#define ARQEN_M24_OBJECT_TRANSFORM_DATA {0}' -f $m24TransformData),
    '#define ARQEN_M25_ORTHOGRAPHIC_CAMERA 1',
    ('#define ARQEN_M25_CAMERA_ENABLED {0}' -f $m25CameraEnabledFlag),
    ('#define ARQEN_M25_CAMERA_NAME "{0}"' -f (Escape-CString $m25CameraName)),
    ('#define ARQEN_M25_CAMERA_DATA {{ {0}, {1}, {2}, {3} }}' -f (Format-FloatLiteral $m25CameraPosition[0]), (Format-FloatLiteral $m25CameraPosition[1]), (Format-FloatLiteral $m25CameraPosition[2]), (Format-FloatLiteral $m25CameraZoom)),
    '#define ARQEN_M26_KEYBOARD_INPUT 1',
    ('#define ARQEN_M26_KEYBOARD_INPUT_ENABLED {0}' -f $m26KeyboardEnabledFlag),
    ('#define ARQEN_M26_KEY_BINDING_COUNT {0}' -f $m26KeyBindingCount),
    ('#define ARQEN_M26_KEY_BINDING_DATA {0}' -f $m26KeyBindingData),
    '#define ARQEN_M28B_PERIPHERAL_INPUT 1',
    ('#define ARQEN_M28B_PERIPHERAL_INPUT_ENABLED {0}' -f $m28bPeripheralInputEnabledFlag),
    ('#define ARQEN_M28B_MOUSE_CAPTURE_ENABLED {0}' -f $m28bMouseCaptureEnabledFlag),
    ('#define ARQEN_M28B_MOUSE_MOVE_BINDING_COUNT {0}' -f $m28bMouseMoveCount),
    ('#define ARQEN_M28B_MOUSE_MOVE_BINDING_DATA {0}' -f $m28bMouseMoveData),
    ('#define ARQEN_M28B_MOUSE_BUTTON_BINDING_COUNT {0}' -f $m28bMouseButtonCount),
    ('#define ARQEN_M28B_MOUSE_BUTTON_BINDING_DATA {0}' -f $m28bMouseButtonData),
    ('#define ARQEN_M28B_MOUSE_WHEEL_BINDING_COUNT {0}' -f $m28bMouseWheelCount),
    ('#define ARQEN_M28B_MOUSE_WHEEL_BINDING_DATA {0}' -f $m28bMouseWheelData),
    '#define ARQEN_M29B_UE_STYLE_VIEWPORT_NAVIGATION 1',
    ('#define ARQEN_M29B_UE_STYLE_VIEWPORT_NAVIGATION_ENABLED {0}' -f $m29bViewportNavigationEnabledFlag),
    '#define ARQEN_M29B_CAMERA_RELATIVE_MOVEMENT 1',
    ('#define ARQEN_M29B_CAMERA_RELATIVE_MOVEMENT_ENABLED {0}' -f $m29bViewportNavigationEnabledFlag),
    '#define ARQEN_M29C_OBJECT_SELECTOR 1',
    ('#define ARQEN_M29C_OBJECT_SELECTOR_ENABLED {0}' -f $m29cObjectSelectorEnabledFlag),
    ('#define ARQEN_M29C_OBJECT_SELECTOR_NAME "{0}"' -f (Escape-CString $m29cObjectSelectorName)),
    ('#define ARQEN_M29C_OBJECT_SELECT_BUTTON {0}' -f $m29cObjectSelectButton),
    ('#define ARQEN_M29C_OBJECT_SELECT_BINDING_COUNT {0}' -f $m29cObjectSelectBindingCount),
    ('#define ARQEN_M29C_SELECTED_OBJECT_ROTATE_BINDING_COUNT {0}' -f $m29cSelectedObjectRotateCount),
    ('#define ARQEN_M29C_SELECTED_OBJECT_ROTATE_BINDING_DATA {0}' -f $m29cSelectedObjectRotateData),
    '#define ARQEN_M30A_DX12_UI_OVERLAY 1',
    ('#define ARQEN_M30A_UI_OVERLAY_ENABLED {0}' -f $m30UiOverlayEnabledFlag),
    ('#define ARQEN_M30A_UI_CONTROL_COUNT {0}' -f $m30UiControlCount),
    ('#define ARQEN_M30A_UI_CONTROL_DATA {0}' -f $m30UiControlData),
    '#define ARQEN_M30B_UI_LAYOUT_HYGIENE 1',
    '#define ARQEN_M30B_TEXT_CLIPPING 1',
    '#define ARQEN_M30B_BUTTON_TEXT_CENTERING 1',
    '#define ARQEN_M30B_Z_INDEX_DRAW_ORDER 1',
    '#define ARQEN_M30C_UI_PARENT_CLIP_BRIDGE 1',
    '#define ARQEN_M30C_PARENT_RELATIVE_LAYOUT 1',
    '#define ARQEN_M30C_BASIC_PANEL_CLIP 1',
    '#define ARQEN_M30D_UI_CLICK_EVENT_BRIDGE 1',
    '#define ARQEN_M30D_UI_EVENT_BODY_ACTIONS 1',
    '#define ARQEN_M31A_UI_CONTROLS_EXPANSION 1',
    '#define ARQEN_M31A_UI_HOVER_PRESSED_FOCUS_STATES 1',
    '#define ARQEN_M31C_UI_COMPUTED_LAYOUT_RECTS 1',
    '#define ARQEN_M31C_UI_PARENT_CONTAINMENT 1',
    '#define ARQEN_M31C_UI_TEXT_PADDING_DEFAULTS 1',
    '#define ARQEN_M31C_UI_STYLE_BOX_MODEL 1',
    '#define ARQEN_M31C_UI_SLIDER_TRACK_RECT 1',
    '#define ARQEN_M31C_UI_SLIDER_RUNTIME_VISUALS 1',
    '#define ARQEN_M31C_UI_STABLE_CLIENT_PIXEL_SPACE 1',
    '#define ARQEN_M32A_DX12_RASTER_FONT_ENGINE 1',
    '#define ARQEN_M32A_DX12_TEXTURE_RESOURCE_COMMAND 1',
    '#define ARQEN_M32A_DX12_FONT_STYLE_COMMANDS 1',
    '#define ARQEN_M31B_UI_RESOURCE_METADATA_BRIDGE 1',
    '#define ARQEN_M28C_OBJECT_ROTATION_3D 1',
    '#define ARQEN_M29_FAKE_LIGHTING 1',
    ('#define ARQEN_M29_FAKE_LIGHTING_ENABLED {0}' -f $m29FakeLightingEnabledFlag),
    ('#define ARQEN_M29_DIRECTIONAL_LIGHT_NAME "{0}"' -f (Escape-CString $m29LightName)),
    ('#define ARQEN_M29_DIRECTIONAL_LIGHT_DATA {0}' -f $m29LightData),
    '#define ARQEN_M27_DEPTH_BUFFER 1',
    ('#define ARQEN_M27_DEPTH_BUFFER_ENABLED {0}' -f $m27DepthEnabledFlag),
    ('#define ARQEN_M27_CAMERA_PROJECTION "{0}"' -f (Escape-CString $m27CameraProjection)),
    ('#define ARQEN_M27_PERSPECTIVE_CAMERA_ENABLED {0}' -f $m27PerspectiveEnabledFlag),
    ('#define ARQEN_M27_PERSPECTIVE_CAMERA_DATA {0}' -f $m27PerspectiveCameraData),
    '#define ARQEN_M27D_NATIVE_WINDOW_STYLE 1',
    ('#define ARQEN_M27D_TITLE_BAR_ENABLED {0}' -f $m27dTitleBarEnabledFlag),
    ('#define ARQEN_M27D_TITLE_TEXT_ENABLED {0}' -f $m27dTitleTextEnabledFlag),
    ('#define ARQEN_M27D_TITLE_BAR_COLOR "{0}"' -f (Escape-CString $m27dTitleBarColor)),
    ('#define ARQEN_M27D_TITLE_TEXT_COLOR "{0}"' -f (Escape-CString $m27dTitleTextColor)),
    '#define ARQEN_M28_BOX_PRIMITIVE 1',
    ('#define ARQEN_M28_BOX_PRIMITIVE_ENABLED {0}' -f $m28BoxPrimitiveEnabledFlag),
    ('#define ARQEN_M28_BOX_PRIMITIVE_COUNT {0}' -f $m28BoxPrimitiveCount),
    ('#define ARQEN_M20I_HOLD_MS {0}' -f $HoldMilliseconds),
    ('#define ARQEN_M20I_ENABLE_DIAGNOSTICS {0}' -f $diagnosticsFlag),
    '#define ARQEN_M21E_STANDALONE_EXE 1',
    '#define ARQEN_M21E_SHADER_FALLBACK_ENABLED 1',
    '#define ARQEN_M21F_FRAME_LOOP_ENABLED 1',
    ('#define ARQEN_M21F_FRAME_COUNT {0}' -f $effectiveFrameCount),
    ('#define ARQEN_M21F_TARGET_FPS {0}' -f $TargetFps)
)
[System.IO.File]::WriteAllLines($configPath, $config, [System.Text.UTF8Encoding]::new($false))

if (-not $Quiet) {
    Write-Host "PASS|m20e1_dx12_clear_lowering|manifest=$manifestPath|config=$configPath"
}
