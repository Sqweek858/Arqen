using System.Collections.Generic;
using System.Linq;

static partial class Program
{
    static IEnumerable<string> IrLines(AstModel ast, string sourcePath)
    {
        yield return "ARQIR|version=0";
        yield return $"TARGET|kind=program|name={Esc(ast.Program)}";
        yield return $"META|source={Esc(sourcePath.Replace('\\', '/'))}";
        foreach (var style in ast.Styles)
            yield return StyleIrLine(style);
        if (ast.RuntimeActions.Count > 0)
        {
            foreach (var v in ast.Vars)
                yield return IrSymbolLine(v.Name, v.Type, v.Value);
            for (var i = 0; i < ast.RuntimeActions.Count; i++)
                yield return RuntimeIrActionLine($"act_{i}", ast.RuntimeActions[i]);
            yield return IrActionLine($"act_{ast.RuntimeActions.Count}", "exit", "code=i32_0");
            yield return IrConstLine("i32_0", "int", ast.ExitCode.ToString());
            yield return $"ENTRY|actions={string.Join(",", Enumerable.Range(0, ast.RuntimeActions.Count + 1).Select(i => $"act_{i}"))}";
            yield return "END";
            yield break;
        }
        yield return IrConstLine("str_0", "text", ast.Title);
        yield return IrConstLine("str_1", "text", ast.Message);
        yield return IrConstLine("i32_0", "int", ast.ExitCode.ToString());
        if (ast.MessageCommand == "print")
            yield return IrActionLine("act_0", "print_stdout", "text=str_1");
        else
            yield return IrActionLine("act_0", "show_message", "title=str_0|text=str_1");
        yield return IrActionLine("act_1", "exit", "code=i32_0");
        yield return "ENTRY|actions=act_0,act_1";
        yield return "END";
    }

    static string StyleIrLine(StyleProperty style)
        => $"STYLE|target={Esc(style.Target)}|state={Esc(style.State)}|property={Esc(style.Property)}|kind={Esc(style.ValueKind)}|value={Esc(style.Value)}|unit={Esc(style.Unit)}";

    static string IrConstLine(string id, string type, string value) => $"CONST|id={id}|type={type}|value={Esc(value)}";
    static string IrSymbolLine(string name, string type, string value) => $"SYMBOL|name={Esc(name)}|type={Esc(type)}|value={Esc(value)}";
    static string IrActionLine(string id, string op, string fields) => $"ACTION|id={id}|op={op}|{fields}";
    static string RuntimeIrActionLine(string id, RuntimeAction action)
    {
        var fields = $"path={Esc(action.Path)}|value_kind={Esc(action.ValueKind)}|value={Esc(action.Value)}|target={Esc(action.Target)}";
        return IrActionLine(id, action.Op, fields);
    }
}
