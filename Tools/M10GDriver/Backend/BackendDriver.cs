using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

static partial class Program
{
    static readonly HashSet<string> SupportedBackendActions = new(StringComparer.Ordinal)
    {
        "show_message",
        "print_stdout",
        "print_runtime_slot",
        "file_write",
        "file_append",
        "file_load",
        "command_arg_count",
        "command_arg_index",
        "runtime_int_set",
        "runtime_int_add",
        "runtime_int_sub",
        "runtime_bool_set",
        "runtime_bool_not_set",
        "runtime_bool_toggle",
        "runtime_trap_if_bool_false",
        "runtime_string_set",
        "runtime_string_concat",
        "runtime_string_substring",
        "runtime_int_parse",
        "runtime_if_int",
        "runtime_if_bool",
        "runtime_if_string",
        "runtime_else",
        "runtime_if_end",
        "runtime_while_int",
        "runtime_break",
        "runtime_continue",
        "runtime_while_end",
        "function_call",
        "function_call_assign",
        "function_return",
        "function_return_int",
        "function_return_bool",
        "function_return_string",
        "window_create",
        "window_set_title",
        "window_set_resolution",
        "window_set_resizable",
        "window_style_title_bar_color",
        "window_style_title_text_color",
        "window_show",
        "window_run",
        "window_close",
        "event_window_closed",
        "event_key_pressed",
        "event_end",
        "exit"
    };

    static void ValidateBackendActionCapabilities(IrModel ir)
    {
        foreach (var action in AllActionMaps(ir))
        {
            if (!action.TryGetValue("op", out var op) || string.IsNullOrWhiteSpace(op))
                throw new CompileError("BACKEND", "B001", 0, 0, "Invalid ACTION referenced by ENTRY/FUNCTION.");
            if (!SupportedBackendActions.Contains(op))
                throw new CompileError("BACKEND", "B008", 0, 0, $"Unsupported backend action: {op}.");
        }
    }

    static void BackendFromIr(string repoRoot, string irPath, string outputPath)
    {
        var ir = ParseIr(irPath);

        if (ir.Version != "0")
            throw new CompileError("BACKEND", "B001", 0, 0, "Unsupported ARQIR version.");

        ValidateBackendActionCapabilities(ir);

        if (HasWindowActions(ir))
        {
            if (HasFileIoActions(ir))
                throw new CompileError("BACKEND", "B005", 0, 0, "Mixing file I/O and window commands is not supported.");

            var windowPe = BuildWindowPe(ir);
            var windowTmpPath = outputPath + ".tmp";
            File.WriteAllBytes(windowTmpPath, windowPe);
            File.Move(windowTmpPath, outputPath, true);
            return;
        }

        if (HasFileIoActions(ir))
        {
            var fileIoPe = BuildFileIoPe(ir);
            var fileIoTmpPath = outputPath + ".tmp";
            File.WriteAllBytes(fileIoTmpPath, fileIoPe);
            File.Move(fileIoTmpPath, outputPath, true);
            return;
        }

        if (!ir.Actions.TryGetValue("act_0", out var first) ||
            !first.TryGetValue("op", out var firstOp))
            throw new CompileError("BACKEND", "B001", 0, 0, "Missing supported first action.");

        if (!ir.Actions.TryGetValue("act_1", out var exit) ||
            !exit.TryGetValue("op", out var exitOp) ||
            exitOp != "exit" ||
            !exit.TryGetValue("code", out var codeId) ||
            !ir.Consts.TryGetValue(codeId, out var codeConst) ||
            codeConst.Type != "int" ||
            codeConst.Value != "0")
            throw new CompileError("BACKEND", "B001", 0, 0, "Only exit code 0 is supported by this backend.");

        if (firstOp == "print_stdout")
        {
            if (!first.TryGetValue("text", out var stdoutTextId) ||
                !ir.Consts.TryGetValue(stdoutTextId, out var stdoutTextConst) ||
                stdoutTextConst.Type != "text")
                throw new CompileError("BACKEND", "B001", 0, 0, "Invalid print_stdout constants.");

            var stdoutText = stdoutTextConst.Value;
            if (stdoutText.Length > 0 && !stdoutText.EndsWith('\n'))
                stdoutText += "\n";
            var stdoutPe = BuildStdoutPe(stdoutText);
            var stdoutTmpPath = outputPath + ".tmp";
            File.WriteAllBytes(stdoutTmpPath, stdoutPe);
            File.Move(stdoutTmpPath, outputPath, true);
            return;
        }

        if (firstOp != "show_message")
            throw new CompileError("BACKEND", "B001", 0, 0, $"Unsupported first action: {firstOp}.");

        if (!first.TryGetValue("title", out var titleId) ||
            !first.TryGetValue("text", out var textId) ||
            !ir.Consts.TryGetValue(titleId, out var titleConst) ||
            !ir.Consts.TryGetValue(textId, out var textConst) ||
            titleConst.Type != "text" ||
            textConst.Type != "text")
            throw new CompileError("BACKEND", "B001", 0, 0, "Invalid show_message constants.");

        var pe = BuildMessageBoxPe(textConst.Value, titleConst.Value);

        var tmpPath = outputPath + ".tmp";
        File.WriteAllBytes(tmpPath, pe);
        File.Move(tmpPath, outputPath, true);
    }
}
