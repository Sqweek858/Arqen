$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
Import-Module (Join-Path $RepoRoot "Tools\Common\CommandAutomationCommon.psm1") -Force

$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "keyword_registry.txt"
$found = New-Object System.Collections.Generic.HashSet[string]

foreach ($spec in Get-ArqenCommandSpecs) {
    $tokens = Get-ArqenSpecValue $spec "TOKENS" ""
    foreach ($keyword in Get-ArqenKeywordTokens $tokens) {
        $found.Add($keyword) | Out-Null
    }
}

$preferred = @("program", "end", "let", "define", "local", "const", "called", "be", "rename", "title", "set", "to", "message", "text", "show", "print", "string", "int", "float", "double", "bool", "var", "command", "arg", "count", "write", "file", "with", "style", "for", "when", "shape", "button", "slider", "input", "field", "checkbox", "dropdown", "content", "range", "value", "placeholder", "type", "display", "color", "opacity", "visibility", "clip", "children", "font", "weight", "size", "px", "ms", "sec", "background", "foreground", "accent", "border", "outline", "corner", "radius", "padding", "margin", "align", "vertical", "line", "height", "letter", "spacing", "wrap", "shadow", "blur", "spread", "offset", "cursor", "transition", "duration", "easing", "mode", "z", "index", "hovered", "pressed", "disabled", "focused", "unfocused", "active", "selected", "checked", "loading", "load", "add", "remove", "from", "multiply", "by", "divide", "runtime", "array", "size", "equals", "contains", "ignoring", "case", "substring", "length", "parse", "toggle", "while", "function", "call", "return", "fill", "copy", "record", "field", "exit", "blend", "mix", "code", "if", "else", "is", "not", "and", "or", "true", "false")
$ordered = @()
foreach ($keyword in $preferred) {
    if ($found.Contains($keyword)) {
        $ordered += $keyword
    }
}
foreach ($keyword in ($found | Sort-Object)) {
    if ($ordered -notcontains $keyword) {
        $ordered += $keyword
    }
}

$lines = $ordered | ForEach-Object { "KEYWORD|$_" }
Set-Content -Path $outPath -Value $lines -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
exit 0
