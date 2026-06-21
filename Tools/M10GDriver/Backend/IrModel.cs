using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

static partial class Program
{
    record IrConst(string Type, string Value);
    record IrModel(string Version, string Source, Dictionary<string, IrConst> Consts, Dictionary<string, Dictionary<string, string>> Actions, Dictionary<string, List<string>> Functions, List<string> EntryActions);

    static IrModel ParseIr(string irPath)
    {
        if (!File.Exists(irPath))
            throw new CompileError("BACKEND", "B001", 0, 0, "IR file not found.");

        string? version = null;
        var source = "";
        var consts = new Dictionary<string, IrConst>(StringComparer.Ordinal);
        var actions = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
        var functions = new Dictionary<string, List<string>>(StringComparer.Ordinal);
        List<string>? entryActions = null;
        var sawTarget = false;
        var sawEnd = false;
        var lineNumber = 0;

        foreach (var raw in File.ReadAllLines(irPath, Encoding.UTF8))
        {
            lineNumber++;
            if (string.IsNullOrWhiteSpace(raw))
                continue;
            if (sawEnd)
                throw new CompileError("BACKEND", "B001", 0, 0, $"Unexpected IR content after END at line {lineNumber}.");

            var parts = SplitStable(raw);
            var op = parts[0];
            var fields = KeyValues(parts.Skip(1));

            switch (op)
            {
                case "ARQIR":
                    if (version != null)
                        throw new CompileError("BACKEND", "B001", 0, 0, "Duplicate ARQIR header in IR.");
                    if (!fields.TryGetValue("version", out version) || string.IsNullOrWhiteSpace(version))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed ARQIR header in IR.");
                    break;
                case "TARGET":
                    if (sawTarget)
                        throw new CompileError("BACKEND", "B001", 0, 0, "Duplicate TARGET in IR.");
                    if (!fields.TryGetValue("kind", out var kind) || kind != "program" ||
                        !fields.TryGetValue("name", out var targetName) || string.IsNullOrWhiteSpace(targetName))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed TARGET in IR.");
                    sawTarget = true;
                    break;
                case "META":
                    fields.TryGetValue("source", out source);
                    break;
                case "SYMBOL":
                    if (!fields.ContainsKey("name") || !fields.ContainsKey("type") || !fields.ContainsKey("value"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed SYMBOL in IR.");
                    break;
                case "STYLE":
                    if (!fields.ContainsKey("target") || !fields.ContainsKey("state") || !fields.ContainsKey("property") || !fields.ContainsKey("kind") || !fields.ContainsKey("value"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed STYLE metadata in IR.");
                    break;
                case "STYLE_PRESET":
                    if (!fields.ContainsKey("name") || !fields.ContainsKey("property") || !fields.ContainsKey("kind") || !fields.ContainsKey("value"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed STYLE_PRESET metadata in IR.");
                    break;
                case "STYLE_APPLY":
                    if (!fields.ContainsKey("style") || !fields.ContainsKey("target") || !fields.ContainsKey("state"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed STYLE_APPLY metadata in IR.");
                    break;
                case "UI_OBJECT":
                    if (!fields.ContainsKey("type") || !fields.ContainsKey("name"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed UI_OBJECT metadata in IR.");
                    break;
                case "UI_SET":
                    if (!fields.ContainsKey("target") || !fields.ContainsKey("property") || !fields.ContainsKey("kind") || !fields.ContainsKey("value"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed UI_SET metadata in IR.");
                    break;
                case "UI_LAYOUT":
                    if (!fields.ContainsKey("target") || !fields.ContainsKey("property") || !fields.ContainsKey("kind") || !fields.ContainsKey("value"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed UI_LAYOUT metadata in IR.");
                    break;
                case "UI_PARENT":
                    if (!fields.ContainsKey("child") || !fields.ContainsKey("parent"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed UI_PARENT metadata in IR.");
                    break;
                case "UI_DOCK":
                    if (!fields.ContainsKey("target") || !fields.ContainsKey("side") || !fields.ContainsKey("parent"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed UI_DOCK metadata in IR.");
                    break;
                case "UI_EVENT":
                    if (!fields.ContainsKey("event") || !fields.ContainsKey("target") || !fields.ContainsKey("target_kind") || !fields.ContainsKey("body_lines"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed UI_EVENT metadata in IR.");
                    break;
                case "UI_BIND":
                    if (!fields.ContainsKey("target") || !fields.ContainsKey("property") || !fields.ContainsKey("source") || !fields.ContainsKey("source_type"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed UI_BIND metadata in IR.");
                    break;
                case "UI_STATE":
                    if (!fields.ContainsKey("target") || !fields.ContainsKey("property") || !fields.ContainsKey("kind") || !fields.ContainsKey("value"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed UI_STATE metadata in IR.");
                    break;
                case "UI_RESOURCE":
                    if (!fields.ContainsKey("type") || !fields.ContainsKey("name") || !fields.ContainsKey("path"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed UI_RESOURCE metadata in IR.");
                    break;
                case "UI_RESOURCE_USE":
                    if (!fields.ContainsKey("target") || !fields.ContainsKey("property") || !fields.ContainsKey("resource") || !fields.ContainsKey("resource_type"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed UI_RESOURCE_USE metadata in IR.");
                    break;
                case "DX12_RENDERER":
                    if (!fields.ContainsKey("name"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_RENDERER metadata in IR.");
                    break;
                case "DX12_PARENT":
                    if (!fields.ContainsKey("renderer") || !fields.ContainsKey("window"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_PARENT metadata in IR.");
                    break;
                case "DX12_CLEAR_STYLE":
                    if (!fields.ContainsKey("renderer") || !fields.ContainsKey("state") || !fields.ContainsKey("kind") || !fields.ContainsKey("value") || !fields.ContainsKey("source"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_CLEAR_STYLE metadata in IR.");
                    break;
                case "DX12_CLEAR_READY":
                    if (!fields.ContainsKey("renderer") || !fields.ContainsKey("window") || !fields.ContainsKey("kind") || !fields.ContainsKey("value") || !fields.ContainsKey("source"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_CLEAR_READY metadata in IR.");
                    break;
                case "DX12_FRAME":
                    if (!fields.ContainsKey("command") || !fields.ContainsKey("renderer"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_FRAME metadata in IR.");
                    break;
                case "DX12_SHADER":
                    if (!fields.ContainsKey("name") || !fields.ContainsKey("vertex") || !fields.ContainsKey("pixel"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_SHADER metadata in IR.");
                    break;
                case "DX12_PIPELINE":
                    if (!fields.ContainsKey("name") || !fields.ContainsKey("renderer") || !fields.ContainsKey("shader") || !fields.ContainsKey("topology"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_PIPELINE metadata in IR.");
                    break;
                case "DX12_PIPELINE_BIND":
                    if (!fields.ContainsKey("pipeline") || !fields.ContainsKey("renderer"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_PIPELINE_BIND metadata in IR.");
                    break;
                case "DX12_VERTEX_BUFFER":
                    if (!fields.ContainsKey("name"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_VERTEX_BUFFER metadata in IR.");
                    break;
                case "DX12_VERTEX":
                    if (!fields.ContainsKey("buffer") || !fields.ContainsKey("index") || !fields.ContainsKey("position") || !fields.ContainsKey("color"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_VERTEX metadata in IR.");
                    break;
                case "DX12_VERTEX_BUFFER_BIND":
                    if (!fields.ContainsKey("buffer") || !fields.ContainsKey("renderer"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_VERTEX_BUFFER_BIND metadata in IR.");
                    break;
                case "DX12_DRAW":
                    if (!fields.ContainsKey("renderer") || !fields.ContainsKey("vertices") || !fields.ContainsKey("buffer") || !fields.ContainsKey("pipeline"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_DRAW metadata in IR.");
                    break;
                case "DX12_OBJECT":
                    if (!fields.ContainsKey("name"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_OBJECT metadata in IR.");
                    break;
                case "DX12_OBJECT_BIND":
                    if (!fields.ContainsKey("object") || !fields.ContainsKey("renderer") || !fields.ContainsKey("pipeline") || !fields.ContainsKey("buffer") || !fields.ContainsKey("vertices"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_OBJECT_BIND metadata in IR.");
                    break;
                case "DX12_DRAW_OBJECT":
                    if (!fields.ContainsKey("object") || !fields.ContainsKey("renderer") || !fields.ContainsKey("vertices") || !fields.ContainsKey("buffer") || !fields.ContainsKey("pipeline"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_DRAW_OBJECT metadata in IR.");
                    break;
                case "DX12_OBJECT_TRANSFORM":
                    if (!fields.ContainsKey("object") || !fields.ContainsKey("property") || !fields.ContainsKey("value"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_OBJECT_TRANSFORM metadata in IR.");
                    break;
                case "DX12_OBJECT_PRIMITIVE":
                    if (!fields.ContainsKey("object") || !fields.ContainsKey("kind"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_OBJECT_PRIMITIVE metadata in IR.");
                    break;
                case "DX12_CAMERA":
                    if (!fields.ContainsKey("name"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_CAMERA metadata in IR.");
                    break;
                case "DX12_CAMERA_USE":
                    if (!fields.ContainsKey("camera") || !fields.ContainsKey("renderer"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_CAMERA_USE metadata in IR.");
                    break;
                case "DX12_CAMERA_PROJECTION":
                    if (!fields.ContainsKey("camera") || !fields.ContainsKey("projection"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_CAMERA_PROJECTION metadata in IR.");
                    break;
                case "DX12_CAMERA_TRANSFORM":
                    if (!fields.ContainsKey("camera") || !fields.ContainsKey("property") || !fields.ContainsKey("value"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_CAMERA_TRANSFORM metadata in IR.");
                    break;
                case "DX12_KEY_BINDING":
                    if (!fields.ContainsKey("key") || !fields.ContainsKey("action") || !fields.ContainsKey("target") || !fields.ContainsKey("delta"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_KEY_BINDING metadata in IR.");
                    break;
                case "DX12_MOUSE_CAPTURE":
                    if (!fields.ContainsKey("window"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_MOUSE_CAPTURE metadata in IR.");
                    break;
                case "DX12_MOUSE_MOVE":
                    if (!fields.ContainsKey("target") || !fields.ContainsKey("sensitivity"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_MOUSE_MOVE metadata in IR.");
                    break;
                case "DX12_MOUSE_BUTTON":
                    if (!fields.ContainsKey("button") || !fields.ContainsKey("action") || !fields.ContainsKey("target") || !fields.ContainsKey("delta"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_MOUSE_BUTTON metadata in IR.");
                    break;
                case "DX12_MOUSE_WHEEL":
                    if (!fields.ContainsKey("action") || !fields.ContainsKey("target") || !fields.ContainsKey("delta"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_MOUSE_WHEEL metadata in IR.");
                    break;
                case "DX12_OBJECT_SELECTOR":
                    if (!fields.ContainsKey("name"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_OBJECT_SELECTOR metadata in IR.");
                    break;
                case "DX12_OBJECT_SELECTOR_USE":
                    if (!fields.ContainsKey("selector") || !fields.ContainsKey("renderer"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_OBJECT_SELECTOR_USE metadata in IR.");
                    break;
                case "DX12_OBJECT_SELECT_BINDING":
                    if (!fields.ContainsKey("button") || !fields.ContainsKey("selector"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_OBJECT_SELECT_BINDING metadata in IR.");
                    break;
                case "DX12_SELECTED_OBJECT_ROTATE":
                    if (!fields.ContainsKey("key") || !fields.ContainsKey("axis") || !fields.ContainsKey("mouse_axis") || !fields.ContainsKey("sensitivity"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_SELECTED_OBJECT_ROTATE metadata in IR.");
                    break;
                case "DX12_DIRECTIONAL_LIGHT":
                    if (!fields.ContainsKey("name"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_DIRECTIONAL_LIGHT metadata in IR.");
                    break;
                case "DX12_LIGHT_USE":
                    if (!fields.ContainsKey("light") || !fields.ContainsKey("renderer"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_LIGHT_USE metadata in IR.");
                    break;
                case "DX12_LIGHT_PROPERTY":
                    if (!fields.ContainsKey("light") || !fields.ContainsKey("property") || !fields.ContainsKey("value"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_LIGHT_PROPERTY metadata in IR.");
                    break;
                case "DX12_CONSTANT_BUFFER":
                    if (!fields.ContainsKey("name") || !fields.ContainsKey("field") || !fields.ContainsKey("type") || !fields.ContainsKey("value"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_CONSTANT_BUFFER metadata in IR.");
                    break;
                case "DX12_CONSTANT_BUFFER_BIND":
                    if (!fields.ContainsKey("buffer") || !fields.ContainsKey("pipeline"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_CONSTANT_BUFFER_BIND metadata in IR.");
                    break;
                case "DX12_COLOR_SEQUENCE":
                    if (!fields.ContainsKey("name"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_COLOR_SEQUENCE metadata in IR.");
                    break;
                case "DX12_COLOR_KEY":
                    if (!fields.ContainsKey("sequence") || !fields.ContainsKey("index") || !fields.ContainsKey("value"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_COLOR_KEY metadata in IR.");
                    break;
                case "DX12_ANIMATE_COLOR":
                    if (!fields.ContainsKey("target") || !fields.ContainsKey("buffer") || !fields.ContainsKey("field") || !fields.ContainsKey("sequence") || !fields.ContainsKey("every_frames"))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed DX12_ANIMATE_COLOR metadata in IR.");
                    break;
                case "CONST":
                    if (!fields.TryGetValue("id", out var id) || string.IsNullOrWhiteSpace(id) ||
                        !fields.TryGetValue("type", out var type) || string.IsNullOrWhiteSpace(type) ||
                        !fields.TryGetValue("value", out var value))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed CONST in IR.");
                    if (consts.ContainsKey(id))
                        throw new CompileError("BACKEND", "B001", 0, 0, $"Duplicate CONST id in IR: {id}.");
                    consts[id] = new IrConst(type, value);
                    break;
                case "ACTION":
                    if (!fields.TryGetValue("id", out var actionId) || string.IsNullOrWhiteSpace(actionId) ||
                        !fields.TryGetValue("op", out var actionOp) || string.IsNullOrWhiteSpace(actionOp))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed ACTION in IR.");
                    if (actions.ContainsKey(actionId))
                        throw new CompileError("BACKEND", "B001", 0, 0, $"Duplicate ACTION id in IR: {actionId}.");
                    actions[actionId] = fields;
                    break;
                case "FUNCTION":
                    if (!fields.TryGetValue("name", out var functionName) || string.IsNullOrWhiteSpace(functionName) ||
                        !fields.TryGetValue("actions", out var functionActionsRaw))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed FUNCTION in IR.");
                    if (functions.ContainsKey(functionName))
                        throw new CompileError("BACKEND", "B001", 0, 0, $"Duplicate FUNCTION in IR: {functionName}.");
                    functions[functionName] = functionActionsRaw.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();
                    break;
                case "ENTRY":
                    if (entryActions != null)
                        throw new CompileError("BACKEND", "B001", 0, 0, "Duplicate ENTRY in IR.");
                    if (!fields.TryGetValue("actions", out var entryRaw) || string.IsNullOrWhiteSpace(entryRaw))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed ENTRY in IR.");
                    entryActions = entryRaw.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();
                    if (entryActions.Count == 0)
                        throw new CompileError("BACKEND", "B001", 0, 0, "ENTRY in IR has no actions.");
                    break;
                case "END":
                    sawEnd = true;
                    break;
                default:
                    throw new CompileError("BACKEND", "B001", 0, 0, $"Unknown IR line kind: {op}.");
            }
        }

        if (version == null || !sawTarget || entryActions == null || !sawEnd)
            throw new CompileError("BACKEND", "B001", 0, 0, "Invalid ARQIR file.");

        foreach (var actionId in entryActions)
            if (!actions.ContainsKey(actionId))
                throw new CompileError("BACKEND", "B001", 0, 0, $"ENTRY references missing ACTION id: {actionId}.");

        foreach (var fn in functions)
            foreach (var actionId in fn.Value)
                if (!actions.ContainsKey(actionId))
                    throw new CompileError("BACKEND", "B001", 0, 0, $"FUNCTION {fn.Key} references missing ACTION id: {actionId}.");

        return new IrModel(version, source ?? "", consts, actions, functions, entryActions);
    }

    static Dictionary<string, string> KeyValues(IEnumerable<string> parts)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var part in parts)
        {
            var at = part.IndexOf('=');
            if (at <= 0)
                continue;
            result[part[..at]] = part[(at + 1)..];
        }
        return result;
    }

    static string SourceFromIr(string irPath)
    {
        try
        {
            return ParseIr(irPath).Source;
        }
        catch
        {
            return "";
        }
    }

    static (string Backend, string Actions) BackendManifestInfo(string irPath)
    {
        var ir = ParseIr(irPath);
        if (HasFileIoActions(ir))
            return ("WindowsX64PE_FileIoBackend", string.Join(",", AllActionMaps(ir).Select(a => a["op"]).Distinct(StringComparer.Ordinal)));
        if (ir.Actions.TryGetValue("act_0", out var first) &&
            first.TryGetValue("op", out var op) &&
            op == "print_stdout")
            return ("WindowsX64PE_StdoutBackend", "print_stdout,exit");
        return ("WindowsX64PE_MessageBoxBackend", "show_message,exit");
    }

    static void WriteManifest(string manifestPath, string artifactPath, string sourcePath, string irPath, string backend, string target, string status, string actions)
    {
        var lines = new[]
        {
            $"ARTIFACT|{Esc(artifactPath.Replace('\\', '/'))}",
            $"SOURCE|{Esc(sourcePath.Replace('\\', '/'))}",
            $"IR|{Esc(irPath.Replace('\\', '/'))}",
            $"BACKEND|{backend}",
            $"TARGET|{target}",
            $"STATUS|{status}",
            $"ACTIONS|{actions}",
            "EXIT_CODE|0",
            $"CREATED_AT|{DateTimeOffset.Now:O}"
        };
        File.WriteAllLines(manifestPath, lines, Encoding.UTF8);
    }

    static List<string> SplitStable(string line)
    {
        var parts = new List<string>();
        var sb = new StringBuilder();
        var escaped = false;
        foreach (var ch in line)
        {
            if (escaped)
            {
                sb.Append('\\');
                sb.Append(ch);
                escaped = false;
                continue;
            }
            if (ch == '\\')
            {
                escaped = true;
                continue;
            }
            if (ch == '|')
            {
                parts.Add(Unesc(sb.ToString()));
                sb.Clear();
                continue;
            }
            sb.Append(ch);
        }
        if (escaped)
            sb.Append('\\');
        parts.Add(Unesc(sb.ToString()));
        return parts;
    }
}
