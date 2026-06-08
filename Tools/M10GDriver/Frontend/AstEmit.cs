using System.Collections.Generic;

static partial class Program
{
    static IEnumerable<string> AstLines(AstModel ast)
    {
        yield return $"PROGRAM|{Esc(ast.Program)}";
        foreach (var v in ast.Vars)
            yield return $"LET|{Esc(v.Name)}|{Esc(v.Type)}|{Esc(v.Value)}";
        foreach (var line in ast.Flow)
            yield return line;
        foreach (var line in AstStyleLines(ast))
            yield return line;
        foreach (var line in AstTitleLines(ast))
            yield return line;
        foreach (var line in AstMessageLines(ast))
            yield return line;
        foreach (var action in ast.RuntimeActions)
            yield return RuntimeAstLine(action);
        foreach (var line in AstFinalLines(ast))
            yield return line;
        yield return "SEMANTIC|OK";
    }


    static IEnumerable<string> AstStyleLines(AstModel ast)
    {
        foreach (var style in ast.Styles)
            yield return $"STYLE|target={Esc(style.Target)}|state={Esc(style.State)}|property={Esc(style.Property)}|kind={Esc(style.ValueKind)}|value={Esc(style.Value)}|unit={Esc(style.Unit)}|source={Esc(style.Source)}";
    }

    static IEnumerable<string> AstTitleLines(AstModel ast)
    {
        if (ast.TitleCommand == "set_title_to")
            yield return $"SET_TITLE|{Esc(ast.Title)}";
        yield return $"TITLE|{Esc(ast.Title)}";
        yield return $"TITLE_EXPR|{Esc(ast.TitleExpr)}";
    }

    static IEnumerable<string> AstMessageLines(AstModel ast)
    {
        if (ast.MessageCommand == "show_message")
            yield return $"SHOW_MESSAGE|{Esc(ast.Message)}";
        yield return $"MESSAGE|{Esc(ast.Message)}";
        yield return $"MESSAGE_EXPR|{Esc(ast.MessageExpr)}";
    }

    static string RuntimeAstLine(RuntimeAction action)
        => $"RUNTIME_ACTION|op={Esc(action.Op)}|path={Esc(action.Path)}|value_kind={Esc(action.ValueKind)}|value={Esc(action.Value)}|target={Esc(action.Target)}";

    static IEnumerable<string> AstFinalLines(AstModel ast)
    {
        if (ast.FinalCommand == "blend_mix_to_code")
            yield return $"BLEND_MIX_TO_CODE|{ast.ExitCode}";
        else
            yield return $"EXIT|{ast.ExitCode}";
    }
}
