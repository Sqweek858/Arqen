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
        foreach (var line in AstStylePresetLines(ast))
            yield return line;
        foreach (var line in AstStyleApplicationLines(ast))
            yield return line;
        foreach (var line in AstUiObjectLines(ast))
            yield return line;
        foreach (var line in AstUiPropertyLines(ast))
            yield return line;
        foreach (var line in AstUiLayoutLines(ast))
            yield return line;
        foreach (var line in AstUiParentLines(ast))
            yield return line;
        foreach (var line in AstUiDockLines(ast))
            yield return line;
        foreach (var line in AstUiFinalLines(ast))
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

    static IEnumerable<string> AstStylePresetLines(AstModel ast)
    {
        foreach (var style in ast.StylePresets)
            yield return $"STYLE_PRESET|name={Esc(style.Name)}|property={Esc(style.Property)}|kind={Esc(style.ValueKind)}|value={Esc(style.Value)}|unit={Esc(style.Unit)}|source={Esc(style.Source)}";
    }

    static IEnumerable<string> AstStyleApplicationLines(AstModel ast)
    {
        foreach (var apply in ast.StyleApplications)
            yield return $"STYLE_APPLY|style={Esc(apply.StyleName)}|target={Esc(apply.Target)}|state={Esc(apply.State)}";
    }

    static IEnumerable<string> AstUiObjectLines(AstModel ast)
    {
        foreach (var obj in ast.UiObjects)
            yield return $"UI_OBJECT|type={Esc(obj.Type)}|name={Esc(obj.Name)}";
    }

    static IEnumerable<string> AstUiPropertyLines(AstModel ast)
    {
        foreach (var prop in ast.UiProperties)
            yield return $"UI_SET|target={Esc(prop.Target)}|property={Esc(prop.Property)}|kind={Esc(prop.ValueKind)}|value={Esc(prop.Value)}|source={Esc(prop.Source)}";
    }

    static IEnumerable<string> AstUiLayoutLines(AstModel ast)
    {
        foreach (var prop in ast.UiLayoutProperties)
            yield return $"UI_LAYOUT|target={Esc(prop.Target)}|property={Esc(prop.Property)}|kind={Esc(prop.ValueKind)}|value={Esc(prop.Value)}|unit={Esc(prop.Unit)}|source={Esc(prop.Source)}";
    }

    static IEnumerable<string> AstUiParentLines(AstModel ast)
    {
        foreach (var relation in ast.UiParents)
            yield return $"UI_PARENT|child={Esc(relation.Child)}|parent={Esc(relation.Parent)}";
    }

    static IEnumerable<string> AstUiDockLines(AstModel ast)
    {
        foreach (var dock in ast.UiDocks)
            yield return $"UI_DOCK|target={Esc(dock.Target)}|side={Esc(dock.Side)}|parent={Esc(dock.Parent)}";
    }

    static IEnumerable<string> AstUiFinalLines(AstModel ast)
    {
        foreach (var ev in ast.UiEvents)
            yield return $"UI_EVENT|event={Esc(ev.Event)}|target={Esc(ev.Target)}|target_kind={Esc(ev.TargetKind)}|body_lines={ev.BodyLineCount}";
        foreach (var binding in ast.UiBindings)
            yield return $"UI_BIND|target={Esc(binding.Target)}|property={Esc(binding.Property)}|source={Esc(binding.Source)}|source_type={Esc(binding.SourceType)}";
        foreach (var state in ast.UiStates)
            yield return $"UI_STATE|target={Esc(state.Target)}|property={Esc(state.Property)}|kind={Esc(state.ValueKind)}|value={Esc(state.Value)}";
        foreach (var resource in ast.UiResources)
            yield return $"UI_RESOURCE|type={Esc(resource.Type)}|name={Esc(resource.Name)}|path={Esc(resource.Path)}";
        foreach (var use in ast.UiResourceUses)
            yield return $"UI_RESOURCE_USE|target={Esc(use.Target)}|property={Esc(use.Property)}|resource={Esc(use.ResourceName)}|resource_type={Esc(use.ResourceType)}";
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
