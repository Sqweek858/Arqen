
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
$m23MultiDrawFlag = 0
if ($RequireTriangle) {
    $drawCallRows = @()
    foreach ($drawCall in $triangleDrawCalls) {
        $drawCallRows += ("{{ {0}u, {1}u, {2}u }}" -f [int]$drawCall.FirstVertex, [int]$drawCall.VertexCount, [int]$drawCall.TransformIndex)
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
    '// Generated by Tools/lower_m20e1_dx12_clear_from_ir.ps1. Do not hand-edit.',
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
