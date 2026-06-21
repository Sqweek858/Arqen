$ErrorActionPreference = "Stop"
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
Import-Module (Join-Path $RepoRoot "Tools\Common\CommandAutomationCommon.psm1") -Force

$root = Get-ArqenRepoRoot
$generated = Get-ArqenGeneratedDir
$outPath = Join-Path $generated "parser_statement_map.txt"
$testRoot = Join-Path $root "Tests\CommandTests"
$expectedIrRoot = Join-Path $root "Tests\ExpectedIR"

$statementRows = @(
    @{ Rule = "program_start"; Command = "program"; Keywords = "program" },
    @{ Rule = "program_end"; Command = "program"; Keywords = "end,program" },
    @{ Rule = "let_statement"; Command = "let"; Keywords = "let,be" },
    @{ Rule = "define_statement"; Command = "define"; Keywords = "define,called,be"; TestFolder = "canonical_define" },
    @{ Rule = "command_args_statement"; Command = "command_args"; Keywords = "define,called,be,command,arg,count"; TestFolder = "command_args" },
    @{ Rule = "rename_statement"; Command = "rename"; Keywords = "rename,to"; TestFolder = "rename" },
    @{ Rule = "title_statement"; Command = "title"; Keywords = "title"; TestFolder = "title" },
    @{ Rule = "set_title_statement"; Command = "set_title_to"; Keywords = "set,title,to" },
    @{ Rule = "set_value_statement"; Command = "set_value"; Keywords = "set,to"; TestFolder = "set_value" },
    @{ Rule = "message_text_statement"; Command = "message_text"; Keywords = "message,text" },
    @{ Rule = "show_message_statement"; Command = "show_message"; Keywords = "show,message" },
    @{ Rule = "show_string_statement"; Command = "show_string"; Keywords = "show,string"; TestFolder = "canonical_show" },
    @{ Rule = "show_value_statement"; Command = "show_value"; Keywords = "show"; TestFolder = "canonical_show" },
    @{ Rule = "print_statement"; Command = "print"; Keywords = "print" },
    @{ Rule = "file_io_statement"; Command = "file_io"; Keywords = "write,file,with,add,to,file,load,file,to"; TestFolder = "file_io" },
    @{ Rule = "style_statement"; Command = "style"; Keywords = "with,style,for,when,define,called,use,end,style"; TestFolder = "style" },
    @{ Rule = "ui_object_statement"; Command = "ui_objects"; Keywords = "define,shape,text,button,slider,input,field,checkbox,dropdown,called,set,content,range,value,placeholder,checked,of,to,add,string"; TestFolder = "ui_objects" },
    @{ Rule = "ui_layout_statement"; Command = "ui_layout"; Keywords = "parent,to,with,layout,for,end,dock,of,x,y,width,height,anchor,offset,margin,padding,mode,direction,gap,columns,rows"; TestFolder = "ui_layout" },
    @{ Rule = "ui_final_statement"; Command = "ui_final"; Keywords = "when,clicked,hovered,pressed,released,focused,unfocused,changed,value,text,dragged,dropped,loaded,resized,link,set,enabled,visible,selected,visibility,state,define,texture,font,sound,called,from,file"; TestFolder = "ui_final" },
    @{ Rule = "dx12_renderer_statement"; Command = "dx12"; Keywords = "define,dx12,renderer,called,parent,to,window,with,style,for,background,color,begin,frame,clear,end,present,shader,vertex,source,file,pixel,pipeline,topology,triangle,list,use,buffer,position,draw,vertices,constant,tint,sequence,animate,using,every,frames"; TestFolder = "dx12" },
    @{ Rule = "math_update_statement"; Command = "math_update"; Keywords = "add,remove,multiply,divide"; TestFolder = "math_update" },
    @{ Rule = "while_statement"; Command = "while_compile_time"; Keywords = "while"; TestFolder = "while_compile_time" },
    @{ Rule = "function_statement"; Command = "function"; Keywords = "define,function,call"; TestFolder = "function" },
    @{ Rule = "exit_statement"; Command = "exit"; Keywords = "exit" },
    @{ Rule = "blend_mix_to_code_statement"; Command = "blend_mix_to_code"; Keywords = "blend,mix,to,code" },
    @{ Rule = "if_statement"; Command = "if_compile_time"; Keywords = "if" },
    @{ Rule = "else_statement"; Command = "if_compile_time"; Keywords = "else" },
    @{ Rule = "end_if_statement"; Command = "if_compile_time"; Keywords = "end,if" }
)

$specs = @{}
foreach ($spec in Get-ArqenCommandSpecs) {
    $id = Get-ArqenSpecValue $spec "COMMAND_ID" $spec.Id
    $specs[$id] = $spec
}

$lines = @()
foreach ($row in $statementRows) {
    $commandId = $row.Command
    $spec = if ($specs.ContainsKey($commandId)) { $specs[$commandId] } else { $null }
    $status = if ($null -ne $spec) { Get-ArqenSpecValue $spec "STATUS" "stable" } else { "missing" }
    $specPath = if ($null -ne $spec) { ConvertTo-ArqenRelativePath $spec.Path } else { "none" }
    $folderName = if ($row.ContainsKey("TestFolder")) { $row.TestFolder } else { $commandId }
    $testDir = Join-Path $testRoot $folderName
    $hasTests = Test-Path $testDir
    $validCount = if ($hasTests) { @(Get-ChildItem $testDir -Filter "valid_*.arq" -File -ErrorAction SilentlyContinue).Count } else { 0 }
    $invalidCount = if ($hasTests) { @(Get-ChildItem $testDir -Filter "invalid_*.arq" -File -ErrorAction SilentlyContinue).Count } else { 0 }
    $expectedIr = $false
    if (Test-Path $expectedIrRoot) {
        $expectedIr = @(Get-ChildItem $expectedIrRoot -Filter "*.expected.ir" -File -Recurse | Where-Object {
            (Get-Content $_.FullName -Raw).Contains("COMMAND_ID|$commandId") -or
            (Get-Content $_.FullName -Raw).Contains("RULE_ID|$($row.Rule)")
        }).Count -gt 0
    }

    $lines += "RULE_ID|$($row.Rule)|COMMAND_ID|$commandId|KEYWORDS|$($row.Keywords)|STATUS|$status|SOURCE_SPEC|$specPath|HAS_TESTS|$($hasTests.ToString().ToLowerInvariant())|HAS_VALID_SAMPLE|$(($validCount -gt 0).ToString().ToLowerInvariant())|HAS_INVALID_SAMPLE|$(($invalidCount -gt 0).ToString().ToLowerInvariant())|EXPECTED_IR_AVAILABLE|$($expectedIr.ToString().ToLowerInvariant())"
}

Set-Content -Path $outPath -Value $lines -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
exit 0
