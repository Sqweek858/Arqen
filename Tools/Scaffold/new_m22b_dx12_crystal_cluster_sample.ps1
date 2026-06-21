param(
    [string]$RepoRoot = "",
    [string]$OutPath = "",
    [string]$ProgramName = "Dx12CrystalSceneGeneratedM22B",
    [string]$WindowTitle = "Arqen M22 Generated Crystal Scene",
    [int]$ShardCount = 9,
    [int]$Seed = 2209,
    [string]$BackgroundColor = "#081018"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}
if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $RepoRoot "Samples\DX12\dx12_crystal_scene_generated_m22b.arq"
}
if ($ShardCount -lt 1 -or $ShardCount -gt 64) { throw "ShardCount must be between 1 and 64." }
if ($BackgroundColor -notmatch '^#[0-9A-Fa-f]{6}$') { throw "BackgroundColor must be #RRGGBB." }

function Format-Float {
    param([double]$Value)
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:0.000}", $Value)
}

$rng = [System.Random]::new($Seed)
$vertices = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $ShardCount; $i++) {
    $angle = (2.0 * [Math]::PI * $i / [Math]::Max(1, $ShardCount)) + 0.13
    $radius = 0.18 + 0.55 * ((($i % 4) + 1) / 4.0)
    $cx = [Math]::Cos($angle) * $radius * 0.95
    $cy = [Math]::Sin($angle) * $radius * 0.65
    $h = 0.18 + 0.05 * (($i * 7) % 5)
    $w = 0.04 + 0.018 * (($i * 5) % 4)
    $rot = $angle + ([Math]::PI / 2.0) + (($rng.NextDouble() * 0.56) - 0.28)
    $cr = [Math]::Cos($rot)
    $sr = [Math]::Sin($rot)
    $local = @(@(0.0,$h), @($w,0.0), @(0.0,-$h), @(-$w,0.0))
    $pts = @()
    foreach ($p in $local) {
        $x = [double]$p[0]
        $y = [double]$p[1]
        $pts += ,@(($cx + $x*$cr - $y*$sr), ($cy + $x*$sr + $y*$cr), 0.0)
    }
    $center = @($cx,$cy,0.0)
    $edgeR = 0.2 + 0.06 * ($i % 3)
    $triPairs = @(@(0,1), @(1,2), @(2,3), @(3,0))
    foreach ($pair in $triPairs) {
        $a = [int]$pair[0]
        $b = [int]$pair[1]
        $rows = @(
            @($pts[$a], @(1.0,1.0,1.0,1.0)),
            @($pts[$b], @($edgeR,0.75,1.0,1.0)),
            @($center, @(0.82,0.95,1.0,1.0))
        )
        foreach ($row in $rows) {
            $pos = $row[0]
            $col = $row[1]
            $vertices.Add(("    vertex position [{0}, {1}, {2}] color [{3}, {4}, {5}, {6}]" -f (Format-Float $pos[0]), (Format-Float $pos[1]), (Format-Float $pos[2]), (Format-Float $col[0]), (Format-Float $col[1]), (Format-Float $col[2]), (Format-Float $col[3]))) | Out-Null
        }
    }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("program `"$ProgramName`"") | Out-Null
$lines.Add("set title to string `"$WindowTitle`"") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("// M22B generated crystal cluster. Existing DX12 syntax, bigger generated vertex buffer, animated tint.") | Out-Null
$lines.Add("define window called `"MainWindow`"") | Out-Null
$lines.Add("set title of `"MainWindow`" to string `"$WindowTitle`"") | Out-Null
$lines.Add("set resolution of `"MainWindow`" to 1280 x 720") | Out-Null
$lines.Add("show window `"MainWindow`"") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("define dx12 renderer called `"MainRenderer`"") | Out-Null
$lines.Add("parent renderer `"MainRenderer`" to window `"MainWindow`"") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("with style for `"MainRenderer`"") | Out-Null
$lines.Add("    background color: color `"$BackgroundColor`"") | Out-Null
$lines.Add("end style") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("define shader called `"TriangleShader`"") | Out-Null
$lines.Add("    vertex source file `"Samples/DX12/Shaders/triangle_vs.hlsl`"") | Out-Null
$lines.Add("    pixel source file `"Samples/DX12/Shaders/triangle_tint_ps.hlsl`"") | Out-Null
$lines.Add("end shader") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("define dx12 pipeline called `"TrianglePipeline`"") | Out-Null
$lines.Add("    renderer: `"MainRenderer`"") | Out-Null
$lines.Add("    shader: `"TriangleShader`"") | Out-Null
$lines.Add("    topology: triangle list") | Out-Null
$lines.Add("end pipeline") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("use pipeline `"TrianglePipeline`" for renderer `"MainRenderer`"") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("define vertex buffer called `"TriangleVertices`"") | Out-Null
foreach ($v in $vertices) { $lines.Add($v) | Out-Null }
$lines.Add("end vertex buffer") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("use vertex buffer `"TriangleVertices`" for renderer `"MainRenderer`"") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("define constant buffer called `"TriangleParams`"") | Out-Null
$lines.Add("    color tint: color `"#38FFC0`"") | Out-Null
$lines.Add("end constant buffer") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("use constant buffer `"TriangleParams`" for pipeline `"TrianglePipeline`"") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("define color sequence called `"CrystalPulse`"") | Out-Null
foreach ($color in @("#38FFC0", "#7C4DFF", "#FF4FD8", "#40A0FF", "#F7FF7A")) { $lines.Add("    color `"$color`"") | Out-Null }
$lines.Add("end color sequence") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("animate color `"TriangleParams.tint`"") | Out-Null
$lines.Add("    using sequence `"CrystalPulse`"") | Out-Null
$lines.Add("    every 10 frames") | Out-Null
$lines.Add("end animate") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("begin frame of `"MainRenderer`"") | Out-Null
$lines.Add("clear renderer `"MainRenderer`"") | Out-Null
$lines.Add("draw $($vertices.Count) vertices with renderer `"MainRenderer`"") | Out-Null
$lines.Add("end frame of `"MainRenderer`"") | Out-Null
$lines.Add("present frame of `"MainRenderer`"") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("run window `"MainWindow`"") | Out-Null
$lines.Add("end program `"$ProgramName`"") | Out-Null

New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($OutPath))) | Out-Null
[System.IO.File]::WriteAllLines($OutPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "PASS|m22b_crystal_cluster_sample_generated|path=$OutPath|shards=$ShardCount|vertices=$($vertices.Count)"
