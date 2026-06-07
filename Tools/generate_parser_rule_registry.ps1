$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "CommandAutomationCommon.psm1") -Force

$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "parser_rule_registry.txt"
$preferred = @("program", "comments", "let", "define", "rename", "title", "set_title_to", "set_value", "message_text", "show_message", "show_string", "show_value", "print", "file_io", "math_update", "while_compile_time", "function", "exit", "BlendMixToCode", "literals", "plus_expression", "numeric_expression", "logical_condition")
$specs = @(Get-ArqenCommandSpecs)
$byId = @{}
foreach ($spec in $specs) { $byId[$spec.Id] = $spec }
$orderedSpecs = @()
foreach ($id in $preferred) {
    if ($byId.ContainsKey($id)) { $orderedSpecs += $byId[$id] }
}
foreach ($spec in $specs) {
    if ($preferred -notcontains $spec.Id) { $orderedSpecs += $spec }
}

$lines = @()
foreach ($spec in $orderedSpecs) {
    $id = Get-ArqenSpecValue $spec "COMMAND_ID" $spec.Id
    $tokens = Get-ArqenSpecValue $spec "TOKENS" ""
    $ast = Get-ArqenSpecValue $spec "AST_NODE" "none"
    $parts = @($tokens.Split(" ") | Where-Object { $_ -ne "" })
    $starts = @()
    foreach ($part in $parts) {
        if ($part.StartsWith("KEYWORD(")) {
            $starts += $part
            continue
        }
        if ($starts.Count -eq 0) {
            $starts += $part
        }
        break
    }
    $lines += "RULE|$id|starts=$($starts -join ',')|ast=$ast"
}

Set-Content -Path $outPath -Value $lines -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
exit 0
