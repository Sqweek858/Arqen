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
        foreach (var style in ast.StylePresets)
            yield return StylePresetIrLine(style);
        foreach (var apply in ast.StyleApplications)
            yield return StyleApplyIrLine(apply);
        foreach (var obj in ast.UiObjects)
            yield return UiObjectIrLine(obj);
        foreach (var prop in ast.UiProperties)
            yield return UiPropertyIrLine(prop);
        foreach (var prop in ast.UiLayoutProperties)
            yield return UiLayoutIrLine(prop);
        foreach (var relation in ast.UiParents)
            yield return UiParentIrLine(relation);
        foreach (var dock in ast.UiDocks)
            yield return UiDockIrLine(dock);
        foreach (var ev in ast.UiEvents)
            yield return UiEventIrLine(ev);
        foreach (var binding in ast.UiBindings)
            yield return UiBindingIrLine(binding);
        foreach (var state in ast.UiStates)
            yield return UiStateIrLine(state);
        foreach (var resource in ast.UiResources)
            yield return UiResourceIrLine(resource);
        foreach (var use in ast.UiResourceUses)
            yield return UiResourceUseIrLine(use);
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

    static string StylePresetIrLine(StylePresetProperty style)
        => $"STYLE_PRESET|name={Esc(style.Name)}|property={Esc(style.Property)}|kind={Esc(style.ValueKind)}|value={Esc(style.Value)}|unit={Esc(style.Unit)}";

    static string StyleApplyIrLine(StyleApplication apply)
        => $"STYLE_APPLY|style={Esc(apply.StyleName)}|target={Esc(apply.Target)}|state={Esc(apply.State)}";

    static string UiObjectIrLine(UiObject obj)
        => $"UI_OBJECT|type={Esc(obj.Type)}|name={Esc(obj.Name)}";

    static string UiPropertyIrLine(UiProperty prop)
        => $"UI_SET|target={Esc(prop.Target)}|property={Esc(prop.Property)}|kind={Esc(prop.ValueKind)}|value={Esc(prop.Value)}";

    static string UiLayoutIrLine(UiLayoutProperty prop)
        => $"UI_LAYOUT|target={Esc(prop.Target)}|property={Esc(prop.Property)}|kind={Esc(prop.ValueKind)}|value={Esc(prop.Value)}|unit={Esc(prop.Unit)}";

    static string UiParentIrLine(UiParent relation)
        => $"UI_PARENT|child={Esc(relation.Child)}|parent={Esc(relation.Parent)}";

    static string UiDockIrLine(UiDock dock)
        => $"UI_DOCK|target={Esc(dock.Target)}|side={Esc(dock.Side)}|parent={Esc(dock.Parent)}";

    static string UiEventIrLine(UiEvent ev)
        => $"UI_EVENT|event={Esc(ev.Event)}|target={Esc(ev.Target)}|target_kind={Esc(ev.TargetKind)}|body_lines={ev.BodyLineCount}";

    static string UiBindingIrLine(UiBinding binding)
        => $"UI_BIND|target={Esc(binding.Target)}|property={Esc(binding.Property)}|source={Esc(binding.Source)}|source_type={Esc(binding.SourceType)}";

    static string UiStateIrLine(UiState state)
        => $"UI_STATE|target={Esc(state.Target)}|property={Esc(state.Property)}|kind={Esc(state.ValueKind)}|value={Esc(state.Value)}";

    static string UiResourceIrLine(UiResource resource)
        => $"UI_RESOURCE|type={Esc(resource.Type)}|name={Esc(resource.Name)}|path={Esc(resource.Path)}";

    static string UiResourceUseIrLine(UiResourceUse use)
        => $"UI_RESOURCE_USE|target={Esc(use.Target)}|property={Esc(use.Property)}|resource={Esc(use.ResourceName)}|resource_type={Esc(use.ResourceType)}";

    static string IrConstLine(string id, string type, string value) => $"CONST|id={id}|type={type}|value={Esc(value)}";
    static string IrSymbolLine(string name, string type, string value) => $"SYMBOL|name={Esc(name)}|type={Esc(type)}|value={Esc(value)}";
    static string IrActionLine(string id, string op, string fields) => $"ACTION|id={id}|op={op}|{fields}";
    static string RuntimeIrActionLine(string id, RuntimeAction action)
    {
        var fields = $"path={Esc(action.Path)}|value_kind={Esc(action.ValueKind)}|value={Esc(action.Value)}|target={Esc(action.Target)}";
        return IrActionLine(id, action.Op, fields);
    }
}
