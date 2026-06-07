using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

static partial class Program
{
    record IrConst(string Type, string Value);
    record IrModel(string Version, string Source, Dictionary<string, IrConst> Consts, Dictionary<string, Dictionary<string, string>> Actions);

    static IrModel ParseIr(string irPath)
    {
        if (!File.Exists(irPath))
            throw new CompileError("BACKEND", "B001", 0, 0, "IR file not found.");

        string? version = null;
        var source = "";
        var consts = new Dictionary<string, IrConst>(StringComparer.Ordinal);
        var actions = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
        var sawEnd = false;

        foreach (var raw in File.ReadAllLines(irPath, Encoding.UTF8))
        {
            if (string.IsNullOrWhiteSpace(raw))
                continue;

            var parts = SplitStable(raw);
            var op = parts[0];
            var fields = KeyValues(parts.Skip(1));

            switch (op)
            {
                case "ARQIR":
                    fields.TryGetValue("version", out version);
                    break;
                case "META":
                    fields.TryGetValue("source", out source);
                    break;
                case "CONST":
                    if (!fields.TryGetValue("id", out var id) ||
                        !fields.TryGetValue("type", out var type) ||
                        !fields.TryGetValue("value", out var value))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed CONST in IR.");
                    consts[id] = new IrConst(type, value);
                    break;
                case "ACTION":
                    if (!fields.TryGetValue("id", out var actionId))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed ACTION in IR.");
                    actions[actionId] = fields;
                    break;
                case "END":
                    sawEnd = true;
                    break;
            }
        }

        if (version == null || !sawEnd)
            throw new CompileError("BACKEND", "B001", 0, 0, "Invalid ARQIR file.");

        return new IrModel(version, source ?? "", consts, actions);
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
            return ("WindowsX64PE_FileIoBackend", string.Join(",", OrderedActionMaps(ir).Select(a => a["op"])));
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
