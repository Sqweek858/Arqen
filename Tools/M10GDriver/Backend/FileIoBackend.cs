using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Globalization;

static partial class Program
{
    static byte[] BuildFileIoPe(IrModel ir)
    {
        const int sectionRaw = 0x200;
        const int sectionRva = 0x1000;
        const int minimumSectionSize = 0x100000;
        const int defaultSlotLenStartRva = 0xE0000;
        const int defaultRuntimeSlotBytes = 0x1000;
        static string ReturnSlotForType(string type) => type switch
        {
            "int" => "__arqen_return_int",
            "bool" => "__arqen_return_bool",
            "string" => "__arqen_return_string",
            _ => throw new CompileError("BACKEND", "B001", 0, 0, $"Unsupported function return type: {type}.")
        };

        var rawActions = OrderedActionMaps(ir);
        var actions = CoalesceConsecutiveFileAppends(rawActions);
        var functionActions = ir.Functions.ToDictionary(
            kvp => kvp.Key,
            kvp => CoalesceConsecutiveFileAppends(OrderedActionMaps(ir, kvp.Value)),
            StringComparer.Ordinal);
        var allActions = actions.Concat(functionActions.Values.SelectMany(v => v)).ToList();
        var estimatedCodeBytes = EstimateGeneratedCodeBytes(allActions);
        var importRva = Align(sectionRva + estimatedCodeBytes + 0x1000, 0x1000);
        var iltRva = importRva + 0x100;
        var iatRva = importRva + 0x180;
        var kernelDllNameRva = importRva + 0x280;
        var dataStartRva = Align(importRva + 0x1000, 0x1000);
        if (actions.Count == 0 || actions[^1].GetValueOrDefault("op") != "exit")
            throw new CompileError("BACKEND", "B001", 0, 0, "File I/O backend requires final exit action.");

        static List<Dictionary<string, string>> CoalesceConsecutiveFileAppends(List<Dictionary<string, string>> input)
        {
            var output = new List<Dictionary<string, string>>();
            var pendingParts = new List<Dictionary<string, string>>();
            string? pendingPath = null;

            void FlushPending()
            {
                if (pendingParts.Count == 0 || string.IsNullOrWhiteSpace(pendingPath)) return;

                if (pendingParts.All(p => p.GetValueOrDefault("value_kind") == "static"))
                {
                    var merged = new Dictionary<string, string>(pendingParts[0], StringComparer.Ordinal);
                    var sb = new StringBuilder();
                    foreach (var part in pendingParts) sb.Append(part.GetValueOrDefault("value") ?? "");
                    merged["value"] = sb.ToString();
                    output.Add(merged);
                }
                else
                {
                    var grouped = new Dictionary<string, string>(StringComparer.Ordinal)
                    {
                        ["op"] = "file_append_group",
                        ["path"] = pendingPath,
                        ["part_count"] = pendingParts.Count.ToString(CultureInfo.InvariantCulture)
                    };

                    for (var i = 0; i < pendingParts.Count; i++)
                    {
                        var part = pendingParts[i];
                        grouped[$"part_{i}_kind"] = part.GetValueOrDefault("value_kind") ?? "static";
                        grouped[$"part_{i}_value"] = part.GetValueOrDefault("value") ?? "";
                    }

                    output.Add(grouped);
                }

                pendingParts.Clear();
                pendingPath = null;
            }

            foreach (var action in input)
            {
                var clone = new Dictionary<string, string>(action, StringComparer.Ordinal);
                if (clone.GetValueOrDefault("op") == "file_append")
                {
                    var path = clone.GetValueOrDefault("path") ?? "";
                    if (pendingParts.Count > 0 && pendingPath != path) FlushPending();
                    pendingPath = path;
                    pendingParts.Add(clone);
                    continue;
                }

                FlushPending();
                output.Add(clone);
            }

            FlushPending();
            return output;
        }

        static int AppendPartCount(Dictionary<string, string> action)
        {
            return action.GetValueOrDefault("op") == "file_append_group"
                ? int.Parse(action.GetValueOrDefault("part_count") ?? "0", CultureInfo.InvariantCulture)
                : 1;
        }

        static string AppendPartKind(Dictionary<string, string> action, int index)
        {
            return action.GetValueOrDefault("op") == "file_append_group"
                ? action.GetValueOrDefault($"part_{index}_kind") ?? "static"
                : action.GetValueOrDefault("value_kind") ?? "static";
        }

        static string AppendPartValue(Dictionary<string, string> action, int index)
        {
            return action.GetValueOrDefault("op") == "file_append_group"
                ? action.GetValueOrDefault($"part_{index}_value") ?? ""
                : action.GetValueOrDefault("value") ?? "";
        }

        static IEnumerable<string> ActionSlotNames(Dictionary<string, string> action)
        {
            var op = action.GetValueOrDefault("op");
            if (op is "function_return_int" or "function_return_bool" or "function_return_string")
            {
                var type = op["function_return_".Length..];
                yield return ReturnSlotForType(type);
                if (action.GetValueOrDefault("value_kind") == "slot")
                    yield return action.GetValueOrDefault("value") ?? "";
                yield break;
            }
            if (op == "function_call_assign")
            {
                yield return action.GetValueOrDefault("target") ?? "";
                yield return ReturnSlotForType(action.GetValueOrDefault("path") ?? "");
                yield break;
            }
            if (op == "file_append_group")
            {
                for (var i = 0; i < AppendPartCount(action); i++)
                {
                    if (AppendPartKind(action, i) == "slot") yield return AppendPartValue(action, i);
                }
                yield break;
            }

            if (op is "runtime_string_concat" or "runtime_string_substring")
            {
                var encoded = DecodeRuntimeOperand(action.GetValueOrDefault("path") ?? "static:");
                if (encoded.Kind == "slot") yield return encoded.Value;
            }

            if (action.GetValueOrDefault("value_kind") == "slot")
                yield return action.GetValueOrDefault("value") ?? "";
            if (op is "file_load" or "print_runtime_slot" or "command_arg_count" or "command_arg_index" or "runtime_int_set" or "runtime_int_add" or "runtime_int_sub" or "runtime_int_parse" or "runtime_if_int" or "runtime_while_int" or "runtime_bool_set" or "runtime_bool_not_set" or "runtime_bool_toggle" or "runtime_trap_if_bool_false" or "runtime_string_set" or "runtime_string_concat" or "runtime_string_substring" or "runtime_if_bool" or "runtime_if_string")
                yield return action.GetValueOrDefault("target") ?? "";
        }

        var slotNames = allActions
            .SelectMany(ActionSlotNames)
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Distinct(StringComparer.Ordinal)
            .ToList();

        var slotSizes = EstimateRuntimeSlotSizes(allActions, slotNames, defaultRuntimeSlotBytes);
        var estimatedDataBytes = EstimateStaticDataBytes(allActions, ir);
        var estimatedDataEndRva = dataStartRva + estimatedDataBytes;
        var slotLenStartRva = Align(Math.Max(defaultSlotLenStartRva, estimatedDataEndRva + 0x1000), 0x1000);
        var bytesWrittenRva = slotLenStartRva - 8;
        var slotStartRva = Align(slotLenStartRva + Math.Max(1, slotNames.Count) * 8 + 0x1000, 0x1000);
        var slotLayoutBytes = slotNames.Sum(name => Align(slotSizes[name], 0x1000));
        var requiredSlotEndRva = slotStartRva + slotLayoutBytes;
        var sectionSize = Align(Math.Max(minimumSectionSize, requiredSlotEndRva + 0x1000 - sectionRva), 0x1000);

        var pe = new byte[sectionRaw + sectionSize];
        WritePeHeader(pe, sectionSize, importRva, 0x600, subsystem: 3);

        var slots = new Dictionary<string, (int BufferRva, int LenRva, int SizeBytes)>(StringComparer.Ordinal);
        var slotCursorRva = slotStartRva;
        for (var i = 0; i < slotNames.Count; i++)
        {
            var slotSize = Align(slotSizes[slotNames[i]], 0x1000);
            slots[slotNames[i]] = (slotCursorRva, slotLenStartRva + i * 8, slotSize);
            slotCursorRva += slotSize;
        }

        var mappedEndRva = sectionRva + sectionSize;
        var requiredSlotLenEndRva = slotLenStartRva + Math.Max(1, slotNames.Count) * 8;
        if (requiredSlotEndRva > mappedEndRva || requiredSlotLenEndRva > mappedEndRva)
            throw new CompileError("BACKEND", "B001", 0, 0, $"File I/O backend PE section does not map runtime slots: required end RVA 0x{Math.Max(requiredSlotEndRva, requiredSlotLenEndRva):X}, mapped end RVA 0x{mappedEndRva:X}.");

        var dataCursor = dataStartRva;
        var pathRvas = new Dictionary<string, int>(StringComparer.Ordinal);
        var valueRvas = new Dictionary<string, (int Rva, int Length)>(StringComparer.Ordinal);
        var newlineRva = AddUtf8("\n");

        foreach (var action in allActions)
        {
            var op = action.GetValueOrDefault("op");
            if (op is "file_write" or "file_append" or "file_append_group" or "file_load")
                GetPath(action.GetValueOrDefault("path") ?? "");
            if (op == "file_append_group")
            {
                for (var i = 0; i < AppendPartCount(action); i++)
                {
                    if (AppendPartKind(action, i) == "static")
                        GetValue(AppendPartValue(action, i));
                }
            }
            else if (action.GetValueOrDefault("value_kind") == "static")
            {
                GetValue(action.GetValueOrDefault("value") ?? "");
            }
            if (op == "print_stdout")
                GetValue(GetPrintStdoutText(action, ir));
            if ((op is "runtime_int_set" or "runtime_int_add" or "runtime_int_sub" or "runtime_int_parse" or "runtime_if_int" or "runtime_while_int" or "runtime_bool_set" or "runtime_bool_not_set" or "runtime_string_set" or "runtime_string_concat" or "runtime_string_substring" or "runtime_if_bool" or "runtime_if_string" or "function_return_int" or "function_return_bool" or "function_return_string") && action.GetValueOrDefault("value_kind") == "static")
                GetValue(action.GetValueOrDefault("value") ?? "");
            if (op is "runtime_string_concat" or "runtime_string_substring")
            {
                var encoded = DecodeRuntimeOperand(action.GetValueOrDefault("path") ?? "static:");
                if (encoded.Kind == "static") GetValue(encoded.Value);
            }
        }

        var importNameCursor = kernelDllNameRva + 0x40;
        var kernelImports = new[] { "CreateFileW", "WriteFile", "ReadFile", "CloseHandle", "SetFilePointer", "GetStdHandle", "GetCommandLineW", "ExitProcess" };
        for (var i = 0; i < kernelImports.Length; i++)
        {
            AddImport(pe, iltRva, iatRva, i, importNameCursor, kernelImports[i]);
            importNameCursor += 0x20;
        }
        WriteAscii(pe, RvaToRaw(kernelDllNameRva), "kernel32.dll\0");
        var importRaw = RvaToRaw(importRva);
        WriteUInt32(pe, importRaw, unchecked((uint)iltRva));
        WriteUInt32(pe, importRaw + 12, unchecked((uint)kernelDllNameRva));
        WriteUInt32(pe, importRaw + 16, unchecked((uint)iatRva));

        var code = new List<byte>();
        var failJumps = new List<int>();
        void Emit(params byte[] bytes) => code.AddRange(bytes);
        void EmitUInt32(uint value) => code.AddRange(BitConverter.GetBytes(value));
        void CallIat(int index)
        {
            var rva = iatRva + index * 8;
            var nextRva = sectionRva + code.Count + 6;
            Emit(0xff, 0x15);
            EmitUInt32(unchecked((uint)(rva - nextRva)));
        }
        void Lea(byte[] prefix, int targetRva, int instructionLength)
        {
            var nextRva = sectionRva + code.Count + instructionLength;
            Emit(prefix);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }
        void MovR8dFromMem(int targetRva)
        {
            var nextRva = sectionRva + code.Count + 7;
            Emit(0x44, 0x8B, 0x05);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }
        void StoreR8dToMem(int targetRva)
        {
            var nextRva = sectionRva + code.Count + 7;
            Emit(0x44, 0x89, 0x05);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }
        void StoreDwordMem(int targetRva, uint value)
        {
            var nextRva = sectionRva + code.Count + 10;
            Emit(0xC7, 0x05);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
            EmitUInt32(value);
        }
        void StoreByteFromAl(int targetRva)
        {
            var nextRva = sectionRva + code.Count + 6;
            Emit(0x88, 0x05);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }
        void StoreByteFromBl(int targetRva)
        {
            var nextRva = sectionRva + code.Count + 6;
            Emit(0x88, 0x1D);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }
        void StoreByteFromDl(int targetRva)
        {
            var nextRva = sectionRva + code.Count + 6;
            Emit(0x88, 0x15);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }
        int EmitNearJump2(byte op1, byte op2)
        {
            Emit(op1, op2);
            var pos = code.Count;
            EmitUInt32(0);
            return pos;
        }
        int EmitShortJump(byte op)
        {
            Emit(op);
            var pos = code.Count;
            Emit(0);
            return pos;
        }
        int EmitNearJump(byte op)
        {
            Emit(op);
            var pos = code.Count;
            EmitUInt32(0);
            return pos;
        }
        void PatchRel32(int offsetPos, int targetRva)
        {
            var nextRva = sectionRva + offsetPos + 4;
            var bytes = BitConverter.GetBytes(targetRva - nextRva);
            for (var i = 0; i < 4; i++)
                code[offsetPos + i] = bytes[i];
        }
        void PatchShort(int offsetPos, int targetRva)
        {
            var nextRva = sectionRva + offsetPos + 1;
            var rel = targetRva - nextRva;
            if (rel < sbyte.MinValue || rel > sbyte.MaxValue)
                throw new CompileError("BACKEND", "B001", 0, 0, "Internal jump too far.");
            code[offsetPos] = unchecked((byte)(sbyte)rel);
        }
        void JeFail()
        {
            Emit(0x0F, 0x84);
            failJumps.Add(code.Count);
            EmitUInt32(0);
        }
        void CheckRaxInvalidHandle()
        {
            Emit(0x48, 0x83, 0xF8, 0xFF);
            JeFail();
        }
        void CheckEaxZero()
        {
            Emit(0x85, 0xC0);
            JeFail();
        }
        void CheckRaxZero()
        {
            Emit(0x48, 0x85, 0xC0);
            JeFail();
        }
        void StoreStack32(byte offset, uint value)
        {
            Emit(0x48, 0xC7, 0x44, 0x24, offset);
            EmitUInt32(value);
        }
        void OpenFile(string path, uint access, uint disposition)
        {
            Lea(new byte[] { 0x48, 0x8D, 0x0D }, GetPath(path), 7);
            Emit(0xBA); EmitUInt32(access);
            Emit(0x45, 0x31, 0xC0);
            Emit(0x45, 0x31, 0xC9);
            StoreStack32(0x20, disposition);
            StoreStack32(0x28, 0x80);
            StoreStack32(0x30, 0);
            CallIat(0);
            CheckRaxInvalidHandle();
            Emit(0x48, 0x89, 0xC3);
        }
        void WriteHandleFromStatic(string value)
        {
            var data = GetValue(value);
            Emit(0x48, 0x89, 0xD9);
            Lea(new byte[] { 0x48, 0x8D, 0x15 }, data.Rva, 7);
            Emit(0x41, 0xB8); EmitUInt32((uint)data.Length);
            Lea(new byte[] { 0x4C, 0x8D, 0x0D }, bytesWrittenRva, 7);
            StoreStack32(0x20, 0);
            CallIat(1);
            CheckEaxZero();
        }
        void WriteHandleFromSlot(string slot)
        {
            var s = slots[slot];
            Emit(0x48, 0x89, 0xD9);
            Lea(new byte[] { 0x48, 0x8D, 0x15 }, s.BufferRva, 7);
            MovR8dFromMem(s.LenRva);
            Lea(new byte[] { 0x4C, 0x8D, 0x0D }, bytesWrittenRva, 7);
            StoreStack32(0x20, 0);
            CallIat(1);
            CheckEaxZero();
        }
        void SkipCommandLineSpaces()
        {
            var loopRva = sectionRva + code.Count;
            Emit(0x66, 0x83, 0x3E, 0x20);
            var done = EmitNearJump2(0x0F, 0x85);
            Emit(0x48, 0x83, 0xC6, 0x02);
            var back = EmitNearJump(0xE9);
            var doneRva = sectionRva + code.Count;
            PatchRel32(done, doneRva);
            PatchRel32(back, loopRva);
        }
        void SkipCommandLineArg()
        {
            SkipCommandLineSpaces();
            Emit(0x66, 0x83, 0x3E, 0x00);
            var doneAtZero = EmitNearJump2(0x0F, 0x84);
            Emit(0x66, 0x83, 0x3E, 0x22);
            var unquoted = EmitNearJump2(0x0F, 0x85);
            Emit(0x48, 0x83, 0xC6, 0x02);
            var quotedLoopRva = sectionRva + code.Count;
            Emit(0x66, 0x83, 0x3E, 0x00);
            var quotedDoneZero = EmitNearJump2(0x0F, 0x84);
            Emit(0x66, 0x83, 0x3E, 0x22);
            var quotedEnd = EmitNearJump2(0x0F, 0x84);
            Emit(0x48, 0x83, 0xC6, 0x02);
            var quotedBack = EmitNearJump(0xE9);
            var quotedEndRva = sectionRva + code.Count;
            Emit(0x48, 0x83, 0xC6, 0x02);
            var quotedDoneJump = EmitNearJump(0xE9);
            var unquotedRva = sectionRva + code.Count;
            var unquotedLoopRva = sectionRva + code.Count;
            Emit(0x66, 0x83, 0x3E, 0x00);
            var unquotedDoneZero = EmitNearJump2(0x0F, 0x84);
            Emit(0x66, 0x83, 0x3E, 0x20);
            var unquotedDoneSpace = EmitNearJump2(0x0F, 0x84);
            Emit(0x48, 0x83, 0xC6, 0x02);
            var unquotedBack = EmitNearJump(0xE9);
            var doneRva = sectionRva + code.Count;
            PatchRel32(doneAtZero, doneRva);
            PatchRel32(unquoted, unquotedRva);
            PatchRel32(quotedDoneZero, doneRva);
            PatchRel32(quotedEnd, quotedEndRva);
            PatchRel32(quotedBack, quotedLoopRva);
            PatchRel32(quotedDoneJump, doneRva);
            PatchRel32(unquotedDoneZero, doneRva);
            PatchRel32(unquotedDoneSpace, doneRva);
            PatchRel32(unquotedBack, unquotedLoopRva);
        }
        void InitCommandLine()
        {
            CallIat(6);
            CheckRaxZero();
            Emit(0x48, 0x89, 0xC6);
            SkipCommandLineArg();
        }
        void StoreRuntimeArgCount(string target)
        {
            var slot = slots[target];
            InitCommandLine();
            Emit(0x45, 0x31, 0xC9);
            var loopRva = sectionRva + code.Count;
            SkipCommandLineSpaces();
            Emit(0x66, 0x83, 0x3E, 0x00);
            var doneCount = EmitNearJump2(0x0F, 0x84);
            Emit(0x41, 0xFF, 0xC1);
            SkipCommandLineArg();
            var back = EmitNearJump(0xE9);
            var doneCountRva = sectionRva + code.Count;
            PatchRel32(doneCount, doneCountRva);
            PatchRel32(back, loopRva);

            // Convert R9D (argument count) to decimal ASCII in the runtime slot.
            // The previous M15-era path only supported one/two digits, which made
            // stress_args_1024+ look haunted for no good reason.
            Emit(0x44, 0x89, 0xC8); // mov eax, r9d
            Emit(0x85, 0xC0);       // test eax, eax
            var nonZero = EmitNearJump2(0x0F, 0x85);
            StoreDwordMem(slot.BufferRva, 0x30);
            StoreDwordMem(slot.LenRva, 1);
            var doneZero = EmitNearJump(0xE9);

            var nonZeroRva = sectionRva + code.Count;
            PatchRel32(nonZero, nonZeroRva);
            Lea(new byte[] { 0x48, 0x8D, 0x0D }, slot.BufferRva + 15, 7); // rcx = scratch end
            Emit(0x45, 0x31, 0xD2); // xor r10d, r10d
            var digitLoopRva = sectionRva + code.Count;
            Emit(0x31, 0xD2);       // xor edx, edx
            Emit(0xBB); EmitUInt32(10); // mov ebx, 10
            Emit(0xF7, 0xF3);       // div ebx
            Emit(0x80, 0xC2, 0x30); // add dl, '0'
            Emit(0x48, 0xFF, 0xC9); // dec rcx
            Emit(0x88, 0x11);       // mov [rcx], dl
            Emit(0x41, 0xFF, 0xC2); // inc r10d
            Emit(0x85, 0xC0);       // test eax, eax
            var moreDigits = EmitNearJump2(0x0F, 0x85);
            PatchRel32(moreDigits, digitLoopRva);

            Emit(0x48, 0x89, 0xCE); // mov rsi, rcx
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, slot.BufferRva, 7); // rdi = slot buffer
            Emit(0x44, 0x89, 0xD1); // mov ecx, r10d
            Emit(0xF3, 0xA4);       // rep movsb
            Emit(0x45, 0x89, 0xD0); // mov r8d, r10d
            StoreR8dToMem(slot.LenRva);

            var doneRva = sectionRva + code.Count;
            PatchRel32(doneZero, doneRva);
        }
        void StoreRuntimeArgValue(int index, string target)
        {
            var slot = slots[target];
            InitCommandLine();
            Emit(0x45, 0x31, 0xC9);
            var findLoopRva = sectionRva + code.Count;
            SkipCommandLineSpaces();
            Emit(0x66, 0x83, 0x3E, 0x00);
            var outOfRange = EmitNearJump2(0x0F, 0x84);
            Emit(0x41, 0x81, 0xF9);
            EmitUInt32(unchecked((uint)index));
            var found = EmitNearJump2(0x0F, 0x84);
            SkipCommandLineArg();
            Emit(0x41, 0xFF, 0xC1);
            var findBack = EmitNearJump(0xE9);
            var foundRva = sectionRva + code.Count;
            PatchRel32(found, foundRva);
            Emit(0x66, 0x83, 0x3E, 0x22);
            var unquotedCopy = EmitNearJump2(0x0F, 0x85);
            Emit(0x48, 0x83, 0xC6, 0x02);
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, slot.BufferRva, 7);
            Emit(0x45, 0x31, 0xC0);
            var quotedLoopRva = sectionRva + code.Count;
            Emit(0x41, 0x81, 0xF8);
            EmitUInt32(unchecked((uint)(slot.SizeBytes - 1)));
            var quotedDoneByCap = EmitNearJump2(0x0F, 0x8D);
            Emit(0x66, 0x42, 0x8B, 0x04, 0x46);
            Emit(0x66, 0x85, 0xC0);
            var quotedDoneByNull = EmitNearJump2(0x0F, 0x84);
            Emit(0x66, 0x83, 0xF8, 0x22);
            var quotedDoneByQuote = EmitNearJump2(0x0F, 0x84);
            Emit(0x42, 0x88, 0x04, 0x07);
            Emit(0x41, 0xFF, 0xC0);
            var quotedBack = EmitNearJump(0xE9);
            var unquotedCopyRva = sectionRva + code.Count;
            PatchRel32(unquotedCopy, unquotedCopyRva);
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, slot.BufferRva, 7);
            Emit(0x45, 0x31, 0xC0);
            var unquotedLoopRva = sectionRva + code.Count;
            Emit(0x41, 0x81, 0xF8);
            EmitUInt32(unchecked((uint)(slot.SizeBytes - 1)));
            var unquotedDoneByCap = EmitNearJump2(0x0F, 0x8D);
            Emit(0x66, 0x42, 0x8B, 0x04, 0x46);
            Emit(0x66, 0x85, 0xC0);
            var unquotedDoneByNull = EmitNearJump2(0x0F, 0x84);
            Emit(0x66, 0x83, 0xF8, 0x20);
            var unquotedDoneBySpace = EmitNearJump2(0x0F, 0x84);
            Emit(0x42, 0x88, 0x04, 0x07);
            Emit(0x41, 0xFF, 0xC0);
            var unquotedBack = EmitNearJump(0xE9);
            var doneRva = sectionRva + code.Count;
            StoreR8dToMem(slot.LenRva);
            var afterDone = EmitShortJump(0xEB);
            var emptyRva = sectionRva + code.Count;
            StoreDwordMem(slot.LenRva, 0);
            var afterEmptyRva = sectionRva + code.Count;
            PatchRel32(findBack, findLoopRva);
            PatchRel32(outOfRange, emptyRva);
            failJumps.Add(quotedDoneByCap);
            PatchRel32(quotedDoneByNull, doneRva);
            PatchRel32(quotedDoneByQuote, doneRva);
            PatchRel32(quotedBack, quotedLoopRva);
            failJumps.Add(unquotedDoneByCap);
            PatchRel32(unquotedDoneByNull, doneRva);
            PatchRel32(unquotedDoneBySpace, doneRva);
            PatchRel32(unquotedBack, unquotedLoopRva);
            PatchShort(afterDone, afterEmptyRva);
        }
        void CloseRbx()
        {
            Emit(0x48, 0x89, 0xD9);
            CallIat(3);
        }
        static (string Kind, string Value) DecodeRuntimeOperand(string encoded)
        {
            var idx = encoded.IndexOf(':');
            if (idx < 0) return ("static", encoded);
            return (encoded[..idx], encoded[(idx + 1)..]);
        }

        static (int Start, int Length) ParseRuntimeRange(string encoded)
        {
            var idx = encoded.IndexOf(':');
            if (idx < 0) return (0, 0);
            var start = int.Parse(encoded[..idx], CultureInfo.InvariantCulture);
            var length = int.Parse(encoded[(idx + 1)..], CultureInfo.InvariantCulture);
            return (start, length);
        }

        void CopyStaticToSlot(string value, string target)
        {
            var data = GetValue(value);
            var slot = slots[target];
            if (data.Length >= slot.SizeBytes)
                throw new CompileError("BACKEND", "B001", 0, 0, $"Runtime value for slot '{target}' exceeds slot capacity.");
            Lea(new byte[] { 0x48, 0x8D, 0x35 }, data.Rva, 7);      // rsi = source
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, slot.BufferRva, 7); // rdi = target
            Emit(0xB9); EmitUInt32(unchecked((uint)data.Length));    // ecx = byte count
            Emit(0xF3, 0xA4);                                        // rep movsb
            StoreDwordMem(slot.LenRva, unchecked((uint)data.Length));
        }
        void CopySlotIntToSlot(string source, string target)
        {
            ParseSlotIntToEax(source);
            StoreEaxAsDecimalToSlot(target);
        }

        void CopySlotBytesToSlot(string source, string target)
        {
            if (source == target)
                return;

            var src = slots[source];
            var dst = slots[target];
            var nextLenRva = sectionRva + code.Count + 6;
            Emit(0x8B, 0x0D);
            EmitUInt32(unchecked((uint)(src.LenRva - nextLenRva))); // ecx = source length
            Emit(0x81, 0xF9); EmitUInt32(unchecked((uint)dst.SizeBytes)); // cmp ecx, target capacity
            failJumps.Add(EmitNearJump2(0x0F, 0x8D)); // source length >= capacity => fail
            Emit(0x41, 0x89, 0xC8); // mov r8d, ecx
            Lea(new byte[] { 0x48, 0x8D, 0x35 }, src.BufferRva, 7);
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, dst.BufferRva, 7);
            Emit(0xF3, 0xA4); // rep movsb
            StoreR8dToMem(dst.LenRva);
        }

        void AppendStaticToSlot(string value, string target)
        {
            var data = GetValue(value);
            AppendBytesToSlot("static", data.Rva, data.Length, target);
        }

        void AppendSlotToSlot(string source, string target)
        {
            var src = slots[source];
            AppendBytesToSlot("slot", src.BufferRva, src.LenRva, target);
        }

        void AppendBytesToSlot(string sourceKind, int sourceRva, int sourceLengthOrLenRva, string target)
        {
            var dst = slots[target];
            var nextDstLenRva = sectionRva + code.Count + 7;
            Emit(0x44, 0x8B, 0x05);
            EmitUInt32(unchecked((uint)(dst.LenRva - nextDstLenRva))); // r8d = target length

            if (sourceKind == "static")
            {
                Emit(0xB9); EmitUInt32(unchecked((uint)sourceLengthOrLenRva)); // ecx = source length
                Lea(new byte[] { 0x48, 0x8D, 0x35 }, sourceRva, 7); // rsi = source
            }
            else
            {
                var nextSrcLenRva = sectionRva + code.Count + 6;
                Emit(0x8B, 0x0D);
                EmitUInt32(unchecked((uint)(sourceLengthOrLenRva - nextSrcLenRva))); // ecx = source length
                Lea(new byte[] { 0x48, 0x8D, 0x35 }, sourceRva, 7); // rsi = source
            }

            Emit(0x41, 0x89, 0xC9); // mov r9d, ecx (preserve source length; rep movsb consumes rcx)
            Emit(0x44, 0x89, 0xC0); // mov eax, r8d
            Emit(0x01, 0xC8);       // add eax, ecx
            Emit(0x3D); EmitUInt32(unchecked((uint)dst.SizeBytes)); // cmp eax, target capacity
            failJumps.Add(EmitNearJump2(0x0F, 0x8D)); // new length >= capacity => fail
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, dst.BufferRva, 7); // rdi = target base
            Emit(0x4C, 0x01, 0xC7); // add rdi, r8
            Emit(0xF3, 0xA4);       // rep movsb
            Emit(0x44, 0x89, 0xC0); // mov eax, r8d
            Emit(0x44, 0x01, 0xC8); // add eax, r9d
            Emit(0x41, 0x89, 0xC0); // mov r8d, eax
            StoreR8dToMem(dst.LenRva);
        }

        void CopyOperandToSlot(string kind, string value, string target)
        {
            if (kind == "slot") CopySlotBytesToSlot(value, target);
            else CopyStaticToSlot(value, target);
        }

        void EmitRuntimeStringConcat(Dictionary<string, string> action)
        {
            var left = DecodeRuntimeOperand(action.GetValueOrDefault("path") ?? "static:");
            var target = action["target"];
            CopyOperandToSlot(left.Kind, left.Value, target);
            if (action.GetValueOrDefault("value_kind") == "slot") AppendSlotToSlot(action.GetValueOrDefault("value") ?? "", target);
            else AppendStaticToSlot(action.GetValueOrDefault("value") ?? "", target);
        }

        void EmitRuntimeStringSubstring(Dictionary<string, string> action)
        {
            var source = DecodeRuntimeOperand(action.GetValueOrDefault("path") ?? "static:");
            var (start, requestedLength) = ParseRuntimeRange(action.GetValueOrDefault("value") ?? "0:0");
            var target = slots[action["target"]];
            int sourceBufferRva;
            int sourceLength;
            int sourceLenRva;
            var sourceIsStatic = source.Kind != "slot";
            if (sourceIsStatic)
            {
                var data = GetValue(source.Value);
                sourceBufferRva = data.Rva;
                sourceLength = data.Length;
                sourceLenRva = 0;
            }
            else
            {
                var src = slots[source.Value];
                sourceBufferRva = src.BufferRva;
                sourceLength = 0;
                sourceLenRva = src.LenRva;
            }

            if (requestedLength >= target.SizeBytes)
                throw new CompileError("BACKEND", "B001", 0, 0, $"substring target '{action["target"]}' is too small for requested length {requestedLength}.");

            if (sourceIsStatic)
                Emit(0xB8);
            else
            {
                var nextLenRva = sectionRva + code.Count + 6;
                Emit(0x8B, 0x05);
                EmitUInt32(unchecked((uint)(sourceLenRva - nextLenRva))); // eax = source length
            }
            if (sourceIsStatic) EmitUInt32(unchecked((uint)sourceLength));
            Emit(0x3D); EmitUInt32(unchecked((uint)start)); // cmp eax, start
            var hasRange = EmitNearJump2(0x0F, 0x8F); // source length > start
            StoreDwordMem(target.LenRva, 0);
            var doneEmpty = EmitNearJump(0xE9);
            var hasRangeRva = sectionRva + code.Count;
            PatchRel32(hasRange, hasRangeRva);
            Emit(0x2D); EmitUInt32(unchecked((uint)start)); // eax = available
            Emit(0x3D); EmitUInt32(unchecked((uint)requestedLength)); // cmp eax, requested
            var useAvailable = EmitNearJump2(0x0F, 0x8C); // available < requested
            Emit(0xB9); EmitUInt32(unchecked((uint)requestedLength)); // ecx = requested
            var copy = EmitNearJump(0xE9);
            var useAvailableRva = sectionRva + code.Count;
            PatchRel32(useAvailable, useAvailableRva);
            Emit(0x89, 0xC1); // mov ecx, eax
            var copyRva = sectionRva + code.Count;
            PatchRel32(copy, copyRva);
            Emit(0x41, 0x89, 0xC8); // mov r8d, ecx
            Lea(new byte[] { 0x48, 0x8D, 0x35 }, sourceBufferRva + start, 7);
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, target.BufferRva, 7);
            Emit(0xF3, 0xA4);
            StoreR8dToMem(target.LenRva);
            var doneRva = sectionRva + code.Count;
            PatchRel32(doneEmpty, doneRva);
        }

        void EmitRuntimeIntParse(Dictionary<string, string> action)
        {
            if (action.GetValueOrDefault("value_kind") == "slot")
            {
                ParseSlotIntToEax(action.GetValueOrDefault("value") ?? "");
                StoreEaxAsDecimalToSlot(action["target"]);
                return;
            }

            var raw = action.GetValueOrDefault("value") ?? "0";
            if (!int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed)) parsed = 0;
            CopyStaticToSlot(parsed.ToString(CultureInfo.InvariantCulture), action["target"]);
        }

        void ParseSlotIntToEax(string target)
        {
            var slot = slots[target];
            Emit(0x31, 0xC0); // xor eax, eax
            var nextLenRva = sectionRva + code.Count + 6;
            Emit(0x8B, 0x0D);
            EmitUInt32(unchecked((uint)(slot.LenRva - nextLenRva))); // ecx = length
            Lea(new byte[] { 0x48, 0x8D, 0x35 }, slot.BufferRva, 7); // rsi = buffer
            Emit(0x83, 0xF9, 0x00); // cmp ecx, 0
            var empty = EmitNearJump2(0x0F, 0x84);
            Emit(0x45, 0x31, 0xC9); // xor r9d, r9d (negative flag)
            Emit(0x80, 0x3E, 0x2D); // cmp byte [rsi], '-'
            var digits = EmitNearJump2(0x0F, 0x85);
            Emit(0x41, 0xB9); EmitUInt32(1); // mov r9d, 1
            Emit(0x48, 0xFF, 0xC6); // inc rsi
            Emit(0xFF, 0xC9); // dec ecx
            var digitsRva = sectionRva + code.Count;
            PatchRel32(digits, digitsRva);
            var loopRva = sectionRva + code.Count;
            Emit(0x83, 0xF9, 0x00); // cmp ecx, 0
            var doneDigits = EmitNearJump2(0x0F, 0x84);
            Emit(0x0F, 0xB6, 0x16); // movzx edx, byte ptr [rsi]
            Emit(0x83, 0xEA, 0x30); // sub edx, '0'
            Emit(0x6B, 0xC0, 0x0A); // imul eax, eax, 10
            Emit(0x01, 0xD0); // add eax, edx
            Emit(0x48, 0xFF, 0xC6); // inc rsi
            Emit(0xFF, 0xC9); // dec ecx
            var back = EmitNearJump(0xE9);
            var doneDigitsRva = sectionRva + code.Count;
            PatchRel32(doneDigits, doneDigitsRva);
            Emit(0x45, 0x85, 0xC9); // test r9d, r9d
            var donePositive = EmitNearJump2(0x0F, 0x84);
            Emit(0xF7, 0xD8); // neg eax
            var doneRva = sectionRva + code.Count;
            PatchRel32(empty, doneRva);
            PatchRel32(back, loopRva);
            PatchRel32(donePositive, doneRva);
        }

        void StoreEaxAsDecimalToSlot(string target)
        {
            var slot = slots[target];
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, slot.BufferRva + 15, 7); // rdi = scratch end
            Emit(0x45, 0x31, 0xD2); // xor r10d, r10d (length)
            Emit(0x45, 0x31, 0xC9); // xor r9d, r9d (negative flag)
            Emit(0x85, 0xC0); // test eax, eax
            var nonNegative = EmitNearJump2(0x0F, 0x8D);
            Emit(0x41, 0xB9); EmitUInt32(1); // mov r9d, 1
            Emit(0xF7, 0xD8); // neg eax
            var nonNegativeRva = sectionRva + code.Count;
            PatchRel32(nonNegative, nonNegativeRva);
            Emit(0x85, 0xC0); // test eax, eax
            var nonZero = EmitNearJump2(0x0F, 0x85);
            Emit(0x48, 0xFF, 0xCF); // dec rdi
            Emit(0xC6, 0x07, 0x30); // mov byte [rdi], '0'
            Emit(0x41, 0xFF, 0xC2); // inc r10d
            var afterZero = EmitNearJump(0xE9);
            var nonZeroRva = sectionRva + code.Count;
            PatchRel32(nonZero, nonZeroRva);
            var digitLoopRva = sectionRva + code.Count;
            Emit(0x31, 0xD2); // xor edx, edx
            Emit(0xBB); EmitUInt32(10); // mov ebx, 10
            Emit(0xF7, 0xF3); // div ebx
            Emit(0x80, 0xC2, 0x30); // add dl, '0'
            Emit(0x48, 0xFF, 0xCF); // dec rdi
            Emit(0x88, 0x17); // mov [rdi], dl
            Emit(0x41, 0xFF, 0xC2); // inc r10d
            Emit(0x85, 0xC0); // test eax, eax
            var moreDigits = EmitNearJump2(0x0F, 0x85);
            PatchRel32(moreDigits, digitLoopRva);
            var afterDigitsRva = sectionRva + code.Count;
            PatchRel32(afterZero, afterDigitsRva);
            Emit(0x45, 0x85, 0xC9); // test r9d, r9d
            var copy = EmitNearJump2(0x0F, 0x84);
            Emit(0x48, 0xFF, 0xCF); // dec rdi
            Emit(0xC6, 0x07, 0x2D); // mov byte [rdi], '-'
            Emit(0x41, 0xFF, 0xC2); // inc r10d
            var copyRva = sectionRva + code.Count;
            PatchRel32(copy, copyRva);
            Emit(0x48, 0x89, 0xFE); // mov rsi, rdi
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, slot.BufferRva, 7); // rdi = slot buffer
            Emit(0x44, 0x89, 0xD1); // mov ecx, r10d
            Emit(0xF3, 0xA4); // rep movsb
            Emit(0x45, 0x89, 0xD0); // mov r8d, r10d
            StoreR8dToMem(slot.LenRva);
        }

        int ParseI32Immediate(string raw, string context)
        {
            if (!int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value))
                throw new CompileError("BACKEND", "B001", 0, 0, $"{context} requires an i32 literal: {raw}.");
            return value;
        }

        void EmitRuntimeIntAdd(string target, int delta)
        {
            ParseSlotIntToEax(target);
            Emit(0x05); EmitUInt32(unchecked((uint)delta)); // add eax, imm32
            StoreEaxAsDecimalToSlot(target);
        }

        void EmitRuntimeIntSub(string target, int delta)
        {
            ParseSlotIntToEax(target);
            Emit(0x2D); EmitUInt32(unchecked((uint)delta)); // sub eax, imm32
            StoreEaxAsDecimalToSlot(target);
        }

        void EmitRuntimeIntAddSlot(string target, string source)
        {
            ParseSlotIntToEax(target);
            Emit(0x41, 0x89, 0xC3); // mov r11d, eax
            ParseSlotIntToEax(source);
            Emit(0x44, 0x01, 0xD8); // add eax, r11d
            StoreEaxAsDecimalToSlot(target);
        }

        void EmitRuntimeIntSubSlot(string target, string source)
        {
            ParseSlotIntToEax(target);
            Emit(0x41, 0x89, 0xC3); // mov r11d, eax
            ParseSlotIntToEax(source);
            Emit(0x41, 0x29, 0xC3); // sub r11d, eax
            Emit(0x41, 0x8B, 0xC3); // mov eax, r11d
            StoreEaxAsDecimalToSlot(target);
        }

        void EmitRuntimeComparisonFalseJump(string op, List<int> falseJumps)
        {
            if (op == "eq") { falseJumps.Add(EmitNearJump2(0x0F, 0x85)); return; } // jne false
            if (op == "ne") { falseJumps.Add(EmitNearJump2(0x0F, 0x84)); return; } // je false
            if (op == "lt") { falseJumps.Add(EmitNearJump2(0x0F, 0x8D)); return; } // jge false
            if (op == "gt") { falseJumps.Add(EmitNearJump2(0x0F, 0x8E)); return; } // jle false

            throw new CompileError("BACKEND", "B001", 0, 0, $"Unsupported runtime int comparison op: {op}.");
        }

        void EmitRuntimeTextComparisonFalseJump(string left, string rightKind, string right, string op, List<int> falseJumps)
        {
            if (op is not ("eq" or "ne" or "eq_ci" or "ne_ci" or "contains"))
                throw new CompileError("BACKEND", "B001", 0, 0, $"Unsupported runtime text comparison op: {op}.");

            if (op == "contains")
            {
                if (rightKind == "slot") EmitSlotContainsSlotFalseJump(left, right, falseJumps);
                else EmitSlotContainsStaticFalseJump(left, right, falseJumps);
                return;
            }

            if (op is "eq_ci" or "ne_ci")
            {
                if (rightKind == "slot") EmitCompareSlotTextToSlotAsciiFold(left, right, op, falseJumps);
                else EmitCompareSlotTextToStaticAsciiFold(left, right, op, falseJumps);
                return;
            }

            if (rightKind == "slot")
            {
                EmitCompareSlotTextToSlot(left, right, op, falseJumps);
                return;
            }

            EmitCompareSlotTextToStatic(left, right, op, falseJumps);
        }

        void EmitAsciiLowerAl()
        {
            Emit(0x3C, 0x41); // cmp al, 'A'
            var below = EmitNearJump2(0x0F, 0x8C);
            Emit(0x3C, 0x5A); // cmp al, 'Z'
            var above = EmitNearJump2(0x0F, 0x8F);
            Emit(0x04, 0x20); // add al, 32
            var doneRva = sectionRva + code.Count;
            PatchRel32(below, doneRva);
            PatchRel32(above, doneRva);
        }

        void EmitAsciiLowerDl()
        {
            Emit(0x80, 0xFA, 0x41); // cmp dl, 'A'
            var below = EmitNearJump2(0x0F, 0x8C);
            Emit(0x80, 0xFA, 0x5A); // cmp dl, 'Z'
            var above = EmitNearJump2(0x0F, 0x8F);
            Emit(0x80, 0xC2, 0x20); // add dl, 32
            var doneRva = sectionRva + code.Count;
            PatchRel32(below, doneRva);
            PatchRel32(above, doneRva);
        }

        void EmitAsciiFoldedCompareLoop(List<int> mismatchJumps)
        {
            var loopRva = sectionRva + code.Count;
            Emit(0x83, 0xF9, 0x00); // cmp ecx, 0
            var done = EmitNearJump2(0x0F, 0x84);
            Emit(0x8A, 0x06);       // mov al, [rsi]
            Emit(0x8A, 0x17);       // mov dl, [rdi]
            EmitAsciiLowerAl();
            EmitAsciiLowerDl();
            Emit(0x38, 0xD0);       // cmp al, dl
            mismatchJumps.Add(EmitNearJump2(0x0F, 0x85));
            Emit(0x48, 0xFF, 0xC6); // inc rsi
            Emit(0x48, 0xFF, 0xC7); // inc rdi
            Emit(0xFF, 0xC9);       // dec ecx
            var back = EmitNearJump(0xE9);
            var doneRva = sectionRva + code.Count;
            PatchRel32(back, loopRva);
            PatchRel32(done, doneRva);
        }

        void EmitCompareSlotTextToStaticAsciiFold(string left, string expected, string op, List<int> falseJumps)
        {
            var slot = slots[left];
            var data = GetValue(expected);
            var nextLenRva = sectionRva + code.Count + 6;
            Emit(0x8B, 0x0D); EmitUInt32(unchecked((uint)(slot.LenRva - nextLenRva))); // ecx = slot length
            Emit(0x81, 0xF9); EmitUInt32(unchecked((uint)data.Length)); // cmp ecx, expected length
            if (op == "eq_ci") falseJumps.Add(EmitNearJump2(0x0F, 0x85));
            else
            {
                var mismatchTrue = EmitNearJump2(0x0F, 0x85);
                var localMismatch = new List<int>();
                Lea(new byte[] { 0x48, 0x8D, 0x35 }, slot.BufferRva, 7);
                Lea(new byte[] { 0x48, 0x8D, 0x3D }, data.Rva, 7);
                EmitAsciiFoldedCompareLoop(localMismatch);
                falseJumps.Add(EmitNearJump(0xE9));
                var trueRva = sectionRva + code.Count;
                PatchRel32(mismatchTrue, trueRva);
                PatchAll(localMismatch, trueRva);
                return;
            }
            Lea(new byte[] { 0x48, 0x8D, 0x35 }, slot.BufferRva, 7);
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, data.Rva, 7);
            EmitAsciiFoldedCompareLoop(falseJumps);
        }

        void EmitCompareSlotTextToSlotAsciiFold(string left, string right, string op, List<int> falseJumps)
        {
            var leftSlot = slots[left];
            var rightSlot = slots[right];
            var nextLeftLenRva = sectionRva + code.Count + 6;
            Emit(0x8B, 0x0D); EmitUInt32(unchecked((uint)(leftSlot.LenRva - nextLeftLenRva))); // ecx = left length
            var nextRightLenRva = sectionRva + code.Count + 6;
            Emit(0x8B, 0x05); EmitUInt32(unchecked((uint)(rightSlot.LenRva - nextRightLenRva))); // eax = right length
            Emit(0x39, 0xC1); // cmp ecx, eax
            if (op == "eq_ci") falseJumps.Add(EmitNearJump2(0x0F, 0x85));
            else
            {
                var mismatchTrue = EmitNearJump2(0x0F, 0x85);
                var localMismatch = new List<int>();
                Lea(new byte[] { 0x48, 0x8D, 0x35 }, leftSlot.BufferRva, 7);
                Lea(new byte[] { 0x48, 0x8D, 0x3D }, rightSlot.BufferRva, 7);
                EmitAsciiFoldedCompareLoop(localMismatch);
                falseJumps.Add(EmitNearJump(0xE9));
                var trueRva = sectionRva + code.Count;
                PatchRel32(mismatchTrue, trueRva);
                PatchAll(localMismatch, trueRva);
                return;
            }
            Lea(new byte[] { 0x48, 0x8D, 0x35 }, leftSlot.BufferRva, 7);
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, rightSlot.BufferRva, 7);
            EmitAsciiFoldedCompareLoop(falseJumps);
        }

        void EmitSlotContainsStaticFalseJump(string left, string needle, List<int> falseJumps)
        {
            var leftSlot = slots[left];
            var data = GetValue(needle);
            EmitSlotContainsBytesFalseJump(leftSlot.BufferRva, leftSlot.LenRva, data.Rva, data.Length, falseJumps);
        }

        void EmitSlotContainsSlotFalseJump(string left, string right, List<int> falseJumps)
        {
            var leftSlot = slots[left];
            var rightSlot = slots[right];
            EmitSlotContainsBytesFalseJump(leftSlot.BufferRva, leftSlot.LenRva, rightSlot.BufferRva, rightSlot.LenRva, falseJumps);
        }

        void EmitSlotContainsBytesFalseJump(int hayBufferRva, int hayLenRva, int needleBufferRva, int needleLenOrRva, List<int> falseJumps)
        {
            var needleIsLenRva = needleLenOrRva > 0x1000;
            var nextHayLenRva = sectionRva + code.Count + 6;
            Emit(0x8B, 0x15); EmitUInt32(unchecked((uint)(hayLenRva - nextHayLenRva))); // edx = hay length
            if (needleIsLenRva)
            {
                var nextNeedleLenRva = sectionRva + code.Count + 6;
                Emit(0x8B, 0x0D); EmitUInt32(unchecked((uint)(needleLenOrRva - nextNeedleLenRva))); // ecx = needle length
            }
            else
            {
                Emit(0xB9); EmitUInt32(unchecked((uint)needleLenOrRva)); // ecx = needle length
            }
            Emit(0x83, 0xF9, 0x00); // cmp ecx, 0
            var emptyNeedleTrue = EmitNearJump2(0x0F, 0x84);
            Emit(0x39, 0xCA); // cmp edx, ecx
            falseJumps.Add(EmitNearJump2(0x0F, 0x8C)); // hay < needle => false
            Emit(0x41, 0x89, 0xD0); // mov r8d, edx
            Emit(0x41, 0x29, 0xC8); // sub r8d, ecx (max start count)
            Emit(0x45, 0x31, 0xC9); // xor r9d, r9d (start index)
            var outerRva = sectionRva + code.Count;
            Emit(0x45, 0x39, 0xC1); // cmp r9d, r8d
            var exhausted = EmitNearJump2(0x0F, 0x8F);
            Lea(new byte[] { 0x48, 0x8D, 0x35 }, hayBufferRva, 7); // rsi = hay base
            Emit(0x4C, 0x01, 0xCE); // add rsi, r9
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, needleBufferRva, 7); // rdi = needle base
            Emit(0x41, 0x89, 0xCA); // mov r10d, ecx (needle len)
            var innerRva = sectionRva + code.Count;
            Emit(0x41, 0x83, 0xFA, 0x00); // cmp r10d, 0
            var found = EmitNearJump2(0x0F, 0x84);
            Emit(0x8A, 0x06); // mov al, [rsi]
            Emit(0x8A, 0x1F); // mov bl, [rdi]
            Emit(0x38, 0xD8); // cmp al, bl
            var mismatch = EmitNearJump2(0x0F, 0x85);
            Emit(0x48, 0xFF, 0xC6); // inc rsi
            Emit(0x48, 0xFF, 0xC7); // inc rdi
            Emit(0x41, 0xFF, 0xCA); // dec r10d
            var innerBack = EmitNearJump(0xE9);
            var mismatchRva = sectionRva + code.Count;
            PatchRel32(mismatch, mismatchRva);
            Emit(0x41, 0xFF, 0xC1); // inc r9d
            var outerBack = EmitNearJump(0xE9);
            var foundRva = sectionRva + code.Count;
            PatchRel32(found, foundRva);
            PatchRel32(emptyNeedleTrue, foundRva);
            var trueJump = EmitNearJump(0xE9);
            PatchRel32(innerBack, innerRva);
            PatchRel32(outerBack, outerRva);
            var exhaustedRva = sectionRva + code.Count;
            PatchRel32(exhausted, exhaustedRva);
            falseJumps.Add(EmitNearJump(0xE9));
            var trueRva = sectionRva + code.Count;
            PatchRel32(trueJump, trueRva);
        }

        void EmitCompareSlotTextToStatic(string left, string expected, string op, List<int> falseJumps)
        {
            var slot = slots[left];
            var data = GetValue(expected);

            var nextLenRva = sectionRva + code.Count + 6;
            Emit(0x8B, 0x0D);
            EmitUInt32(unchecked((uint)(slot.LenRva - nextLenRva))); // ecx = slot length
            Emit(0x81, 0xF9); EmitUInt32(unchecked((uint)data.Length)); // cmp ecx, expected length

            if (op == "eq")
            {
                falseJumps.Add(EmitNearJump2(0x0F, 0x85)); // length mismatch => false
                Lea(new byte[] { 0x48, 0x8D, 0x35 }, slot.BufferRva, 7);
                Lea(new byte[] { 0x48, 0x8D, 0x3D }, data.Rva, 7);
                Emit(0xF3, 0xA6); // repe cmpsb
                falseJumps.Add(EmitNearJump2(0x0F, 0x85)); // bytes mismatch => false
                return;
            }

            var lengthMismatchTrue = EmitNearJump2(0x0F, 0x85);
            Lea(new byte[] { 0x48, 0x8D, 0x35 }, slot.BufferRva, 7);
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, data.Rva, 7);
            Emit(0xF3, 0xA6); // repe cmpsb
            var bytesMismatchTrue = EmitNearJump2(0x0F, 0x85);
            falseJumps.Add(EmitNearJump(0xE9)); // equal => false for !=
            var trueRva = sectionRva + code.Count;
            PatchRel32(lengthMismatchTrue, trueRva);
            PatchRel32(bytesMismatchTrue, trueRva);
        }

        void EmitCompareSlotTextToSlot(string left, string right, string op, List<int> falseJumps)
        {
            var leftSlot = slots[left];
            var rightSlot = slots[right];

            var nextLeftLenRva = sectionRva + code.Count + 6;
            Emit(0x8B, 0x0D);
            EmitUInt32(unchecked((uint)(leftSlot.LenRva - nextLeftLenRva))); // ecx = left length
            var nextRightLenRva = sectionRva + code.Count + 6;
            Emit(0x8B, 0x05);
            EmitUInt32(unchecked((uint)(rightSlot.LenRva - nextRightLenRva))); // eax = right length
            Emit(0x39, 0xC1); // cmp ecx, eax

            if (op == "eq")
            {
                falseJumps.Add(EmitNearJump2(0x0F, 0x85)); // length mismatch => false
                Lea(new byte[] { 0x48, 0x8D, 0x35 }, leftSlot.BufferRva, 7);
                Lea(new byte[] { 0x48, 0x8D, 0x3D }, rightSlot.BufferRva, 7);
                Emit(0xF3, 0xA6); // repe cmpsb
                falseJumps.Add(EmitNearJump2(0x0F, 0x85)); // bytes mismatch => false
                return;
            }

            var lengthMismatchTrue = EmitNearJump2(0x0F, 0x85);
            Lea(new byte[] { 0x48, 0x8D, 0x35 }, leftSlot.BufferRva, 7);
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, rightSlot.BufferRva, 7);
            Emit(0xF3, 0xA6); // repe cmpsb
            var bytesMismatchTrue = EmitNearJump2(0x0F, 0x85);
            falseJumps.Add(EmitNearJump(0xE9)); // equal => false for !=
            var trueRva = sectionRva + code.Count;
            PatchRel32(lengthMismatchTrue, trueRva);
            PatchRel32(bytesMismatchTrue, trueRva);
        }

        void EmitRuntimeBoolNotSet(string target, string valueKind, string value)
        {
            if (valueKind == "static")
            {
                CopyStaticToSlot(value == "true" ? "false" : "true", target);
                return;
            }

            var falseJumps = new List<int>();
            EmitRuntimeTextComparisonFalseJump(value, "static", "true", "eq", falseJumps);
            CopyStaticToSlot("false", target);
            var endJump = EmitNearJump(0xE9);
            var falseRva = sectionRva + code.Count;
            PatchAll(falseJumps, falseRva);
            CopyStaticToSlot("true", target);
            var endRva = sectionRva + code.Count;
            PatchRel32(endJump, endRva);
        }

        void EmitCompareSlotToStatic(string target, string expected, string op, List<int> falseJumps)
        {
            var immediate = ParseI32Immediate(expected, "runtime int comparison");
            ParseSlotIntToEax(target);
            Emit(0x3D); EmitUInt32(unchecked((uint)immediate)); // cmp eax, imm32
            EmitRuntimeComparisonFalseJump(op, falseJumps);
        }

        void EmitCompareSlotToSlot(string left, string right, string op, List<int> falseJumps)
        {
            ParseSlotIntToEax(left);
            Emit(0x41, 0x89, 0xC3); // mov r11d, eax
            ParseSlotIntToEax(right);
            Emit(0x41, 0x39, 0xC3); // cmp r11d, eax
            EmitRuntimeComparisonFalseJump(op, falseJumps);
        }

        (string Kind, string Op) RuntimeCondition(Dictionary<string, string> action)
        {
            var kind = action.GetValueOrDefault("value_kind") ?? "static";
            var op = action.GetValueOrDefault("path") ?? "";
            if (string.IsNullOrWhiteSpace(op))
            {
                if (kind.Contains(":", StringComparison.Ordinal))
                {
                    var pieces = kind.Split(':', 2);
                    kind = pieces[0];
                    op = pieces[1];
                }
                else if (kind is "eq" or "ne" or "lt" or "gt")
                {
                    op = kind;
                    kind = "static";
                }
                else
                {
                    op = "eq";
                }
            }
            return (kind, op);
        }
        void PatchAll(IEnumerable<int> jumps, int targetRva)
        {
            foreach (var jump in jumps)
                PatchRel32(jump, targetRva);
        }

        var functionCallPatches = new Dictionary<string, List<int>>(StringComparer.Ordinal);

        void EmitFunctionCall(string target)
        {
            if (string.IsNullOrWhiteSpace(target))
                throw new CompileError("BACKEND", "B001", 0, 0, "function_call requires a target function.");
            Emit(0xE8);
            var relPos = code.Count;
            EmitUInt32(0);
            if (!functionCallPatches.TryGetValue(target, out var patches))
            {
                patches = new List<int>();
                functionCallPatches[target] = patches;
            }
            patches.Add(relPos);
        }

        void EmitFunctionReturnValue(Dictionary<string, string> action, string returnType, List<int>? functionReturnJumps, string streamName)
        {
            if (functionReturnJumps == null)
                throw new CompileError("BACKEND", "B001", 0, 0, $"function_return_{returnType} outside function action stream {streamName}.");

            var returnSlot = ReturnSlotForType(returnType);
            var kind = action.GetValueOrDefault("value_kind") ?? "static";
            var value = action.GetValueOrDefault("value") ?? "";

            if (returnType == "int")
            {
                if (kind == "slot") CopySlotIntToSlot(value, returnSlot);
                else CopyStaticToSlot(value, returnSlot);
            }
            else
            {
                if (kind == "slot") CopySlotBytesToSlot(value, returnSlot);
                else CopyStaticToSlot(value, returnSlot);
            }

            functionReturnJumps.Add(EmitNearJump(0xE9));
        }

        void EmitFunctionCallAssign(Dictionary<string, string> action)
        {
            var returnType = action.GetValueOrDefault("path") ?? "";
            var functionName = action.GetValueOrDefault("value") ?? "";
            var target = action.GetValueOrDefault("target") ?? "";
            EmitFunctionCall(functionName);
            var returnSlot = ReturnSlotForType(returnType);
            if (returnType == "int") CopySlotIntToSlot(returnSlot, target);
            else CopySlotBytesToSlot(returnSlot, target);
        }

        void EmitActionStream(List<Dictionary<string, string>> streamActions, string streamName, List<int>? functionReturnJumps = null)
        {
            var runtimeIfStack = new Stack<(List<int> FalseJumps, int? EndJump)>();
            var runtimeWhileStack = new Stack<(int StartRva, List<int> FalseJumps, List<int> BreakJumps)>();

            foreach (var action in streamActions)
            {
                var op = action.GetValueOrDefault("op");
                if (op == "file_write")
                {
                    OpenFile(action["path"], 0x40000000, 2);
                    if (action.GetValueOrDefault("value_kind") == "slot")
                        WriteHandleFromSlot(action["value"]);
                    else
                        WriteHandleFromStatic(action.GetValueOrDefault("value") ?? "");
                    CloseRbx();
                }
                else if (op == "file_append")
                {
                    OpenFile(action["path"], 0x40000000, 4);
                    Emit(0x48, 0x89, 0xD9);
                    Emit(0x31, 0xD2);
                    Emit(0x45, 0x31, 0xC0);
                    Emit(0x41, 0xB9, 0x02, 0x00, 0x00, 0x00);
                    CallIat(4);
                    if (action.GetValueOrDefault("value_kind") == "slot")
                        WriteHandleFromSlot(action["value"]);
                    else
                        WriteHandleFromStatic(action.GetValueOrDefault("value") ?? "");
                    CloseRbx();
                }
                else if (op == "file_append_group")
                {
                    OpenFile(action["path"], 0x40000000, 4);
                    Emit(0x48, 0x89, 0xD9);
                    Emit(0x31, 0xD2);
                    Emit(0x45, 0x31, 0xC0);
                    Emit(0x41, 0xB9, 0x02, 0x00, 0x00, 0x00);
                    CallIat(4);
                    for (var i = 0; i < AppendPartCount(action); i++)
                    {
                        if (AppendPartKind(action, i) == "slot")
                            WriteHandleFromSlot(AppendPartValue(action, i));
                        else
                            WriteHandleFromStatic(AppendPartValue(action, i));
                    }
                    CloseRbx();
                }
                else if (op == "file_load")
                {
                    var slot = slots[action["target"]];
                    OpenFile(action["path"], 0x80000000, 3);
                    Emit(0x48, 0x89, 0xD9);
                    Lea(new byte[] { 0x48, 0x8D, 0x15 }, slot.BufferRva, 7);
                    Emit(0x41, 0xB8); EmitUInt32(unchecked((uint)slot.SizeBytes));
                    Lea(new byte[] { 0x4C, 0x8D, 0x0D }, slot.LenRva, 7);
                    StoreStack32(0x20, 0);
                    CallIat(2);
                    CheckEaxZero();
                    var nextRva = sectionRva + code.Count + 10;
                    Emit(0x81, 0x3D);
                    EmitUInt32(unchecked((uint)(slot.LenRva - nextRva)));
                    EmitUInt32(unchecked((uint)slot.SizeBytes));
                    JeFail();
                    CloseRbx();
                }
                else if (op == "print_runtime_slot")
                {
                    var slot = slots[action["target"]];
                    Emit(0xB9, 0xF5, 0xFF, 0xFF, 0xFF);
                    CallIat(5);
                    CheckRaxInvalidHandle();
                    Emit(0x48, 0x89, 0xC3);
                    WriteHandleFromSlot(action["target"]);
                    WriteHandleFromStatic("\n");
                }
                else if (op == "print_stdout")
                {
                    var text = GetPrintStdoutText(action, ir);
                    Emit(0xB9, 0xF5, 0xFF, 0xFF, 0xFF);
                    CallIat(5);
                    CheckRaxInvalidHandle();
                    Emit(0x48, 0x89, 0xC3);
                    WriteHandleFromStatic(text);
                }
                else if (op == "command_arg_count")
                {
                    StoreRuntimeArgCount(action["target"]);
                }
                else if (op == "command_arg_index")
                {
                    StoreRuntimeArgValue(int.Parse(action["value"], CultureInfo.InvariantCulture), action["target"]);
                }
                else if (op == "runtime_int_set")
                {
                    if (action.GetValueOrDefault("value_kind") == "slot")
                        CopySlotIntToSlot(action.GetValueOrDefault("value") ?? "", action["target"]);
                    else
                        CopyStaticToSlot(action.GetValueOrDefault("value") ?? "0", action["target"]);
                }
                else if (op == "runtime_int_add")
                {
                    if (action.GetValueOrDefault("value_kind") == "slot")
                        EmitRuntimeIntAddSlot(action["target"], action.GetValueOrDefault("value") ?? "");
                    else
                        EmitRuntimeIntAdd(action["target"], ParseI32Immediate(action.GetValueOrDefault("value") ?? "0", "runtime int add"));
                }
                else if (op == "runtime_int_sub")
                {
                    if (action.GetValueOrDefault("value_kind") == "slot")
                        EmitRuntimeIntSubSlot(action["target"], action.GetValueOrDefault("value") ?? "");
                    else
                        EmitRuntimeIntSub(action["target"], ParseI32Immediate(action.GetValueOrDefault("value") ?? "0", "runtime int sub"));
                }
                else if (op == "runtime_bool_set" || op == "runtime_string_set")
                {
                    if (action.GetValueOrDefault("value_kind") == "slot")
                        CopySlotBytesToSlot(action.GetValueOrDefault("value") ?? "", action["target"]);
                    else
                        CopyStaticToSlot(action.GetValueOrDefault("value") ?? "", action["target"]);
                }
                else if (op == "runtime_string_concat")
                {
                    EmitRuntimeStringConcat(action);
                }
                else if (op == "runtime_string_substring")
                {
                    EmitRuntimeStringSubstring(action);
                }
                else if (op == "runtime_int_parse")
                {
                    EmitRuntimeIntParse(action);
                }
                else if (op == "runtime_bool_not_set")
                {
                    EmitRuntimeBoolNotSet(action["target"], action.GetValueOrDefault("value_kind") ?? "static", action.GetValueOrDefault("value") ?? "false");
                }
                else if (op == "runtime_bool_toggle")
                {
                    EmitRuntimeBoolNotSet(action["target"], "slot", action["target"]);
                }
                else if (op == "runtime_trap_if_bool_false")
                {
                    EmitRuntimeTextComparisonFalseJump(action["target"], "static", "true", "eq", failJumps);
                }
                else if (op == "runtime_if_int")
                {
                    var falseJumps = new List<int>();
                    var condition = RuntimeCondition(action);
                    if (condition.Kind == "slot")
                        EmitCompareSlotToSlot(action["target"], action.GetValueOrDefault("value") ?? "", condition.Op, falseJumps);
                    else
                        EmitCompareSlotToStatic(action["target"], action.GetValueOrDefault("value") ?? "0", condition.Op, falseJumps);
                    runtimeIfStack.Push((falseJumps, null));
                }
                else if (op == "runtime_if_bool")
                {
                    var falseJumps = new List<int>();
                    var condition = RuntimeCondition(action);
                    EmitRuntimeTextComparisonFalseJump(action["target"], condition.Kind, action.GetValueOrDefault("value") ?? "false", condition.Op, falseJumps);
                    runtimeIfStack.Push((falseJumps, null));
                }
                else if (op == "runtime_if_string")
                {
                    var falseJumps = new List<int>();
                    var condition = RuntimeCondition(action);
                    EmitRuntimeTextComparisonFalseJump(action["target"], condition.Kind, action.GetValueOrDefault("value") ?? "", condition.Op, falseJumps);
                    runtimeIfStack.Push((falseJumps, null));
                }
                else if (op == "runtime_else")
                {
                    if (runtimeIfStack.Count == 0)
                        throw new CompileError("BACKEND", "B001", 0, 0, $"runtime_else without matching runtime_if in {streamName}.");
                    var frame = runtimeIfStack.Pop();
                    var endJump = EmitNearJump(0xE9);
                    var elseRva = sectionRva + code.Count;
                    PatchAll(frame.FalseJumps, elseRva);
                    runtimeIfStack.Push((new List<int>(), endJump));
                }
                else if (op == "runtime_if_end")
                {
                    if (runtimeIfStack.Count == 0)
                        throw new CompileError("BACKEND", "B001", 0, 0, $"runtime_if_end without matching runtime_if in {streamName}.");
                    var frame = runtimeIfStack.Pop();
                    var endRva = sectionRva + code.Count;
                    PatchAll(frame.FalseJumps, endRva);
                    if (frame.EndJump is int endJump)
                        PatchRel32(endJump, endRva);
                }
                else if (op == "runtime_while_int")
                {
                    var startRva = sectionRva + code.Count;
                    var falseJumps = new List<int>();
                    var condition = RuntimeCondition(action);
                    if (condition.Kind == "slot")
                        EmitCompareSlotToSlot(action["target"], action.GetValueOrDefault("value") ?? "", condition.Op, falseJumps);
                    else
                        EmitCompareSlotToStatic(action["target"], action.GetValueOrDefault("value") ?? "0", condition.Op, falseJumps);
                    runtimeWhileStack.Push((startRva, falseJumps, new List<int>()));
                }
                else if (op == "runtime_break")
                {
                    if (runtimeWhileStack.Count == 0)
                        throw new CompileError("BACKEND", "B001", 0, 0, $"runtime_break without matching runtime_while_int in {streamName}.");
                    runtimeWhileStack.Peek().BreakJumps.Add(EmitNearJump(0xE9));
                }
                else if (op == "runtime_continue")
                {
                    if (runtimeWhileStack.Count == 0)
                        throw new CompileError("BACKEND", "B001", 0, 0, $"runtime_continue without matching runtime_while_int in {streamName}.");
                    var jump = EmitNearJump(0xE9);
                    PatchRel32(jump, runtimeWhileStack.Peek().StartRva);
                }
                else if (op == "runtime_while_end")
                {
                    if (runtimeWhileStack.Count == 0)
                        throw new CompileError("BACKEND", "B001", 0, 0, $"runtime_while_end without matching runtime_while_int in {streamName}.");
                    var frame = runtimeWhileStack.Pop();
                    var back = EmitNearJump(0xE9);
                    PatchRel32(back, frame.StartRva);
                    var endRva = sectionRva + code.Count;
                    PatchAll(frame.FalseJumps, endRva);
                    PatchAll(frame.BreakJumps, endRva);
                }
                else if (op == "function_call")
                {
                    EmitFunctionCall(action.GetValueOrDefault("target") ?? "");
                }
                else if (op == "function_return")
                {
                    if (functionReturnJumps == null)
                        throw new CompileError("BACKEND", "B001", 0, 0, $"function_return outside function action stream {streamName}.");
                    functionReturnJumps.Add(EmitNearJump(0xE9));
                }
                else if (op is "function_return_int" or "function_return_bool" or "function_return_string")
                {
                    EmitFunctionReturnValue(action, op["function_return_".Length..], functionReturnJumps, streamName);
                }
                else if (op == "function_call_assign")
                {
                    EmitFunctionCallAssign(action);
                }
                else if (op == "exit")
                {
                    // Emitted once at the end of the entry stream.
                }
                else
                {
                    throw new CompileError("BACKEND", "B001", 0, 0, $"Unsupported file I/O backend action: {op}.");
                }
            }

            if (runtimeIfStack.Count != 0)
                throw new CompileError("BACKEND", "B001", 0, 0, $"Unclosed runtime if block in backend action stream {streamName}.");
            if (runtimeWhileStack.Count != 0)
                throw new CompileError("BACKEND", "B001", 0, 0, $"Unclosed runtime while block in backend action stream {streamName}.");
        }

        Emit(0x48, 0x83, 0xEC, 0x58);
        EmitActionStream(actions, "entry");
        Emit(0x31, 0xC9);
        CallIat(7);

        var functionEntryRvas = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var fn in functionActions)
        {
            functionEntryRvas[fn.Key] = sectionRva + code.Count;
            // A real function is also a caller for any runtime action that reaches WinAPI.
            // Allocate the same stack frame as the entry stream so function-local calls
            // get fresh shadow space instead of scribbling over this function's return address.
            Emit(0x48, 0x83, 0xEC, 0x58);
            var returnJumps = new List<int>();
            EmitActionStream(fn.Value, "function " + fn.Key, returnJumps);
            var functionEpilogueRva = sectionRva + code.Count;
            PatchAll(returnJumps, functionEpilogueRva);
            Emit(0x48, 0x83, 0xC4, 0x58);
            Emit(0xC3);
        }

        foreach (var patch in functionCallPatches)
        {
            if (!functionEntryRvas.TryGetValue(patch.Key, out var targetRva))
                throw new CompileError("BACKEND", "B001", 0, 0, $"function_call references missing function {patch.Key}.");
            foreach (var relPos in patch.Value)
                PatchRel32(relPos, targetRva);
        }

        var failRva = sectionRva + code.Count;
        Emit(0xB9, 0x01, 0x00, 0x00, 0x00);
        CallIat(7);
        var codeBytes = code.ToArray();
        if (sectionRva + codeBytes.Length > importRva)
            throw new CompileError("BACKEND", "B001", 0, 0, $"File I/O backend code section overlaps import table: code end RVA 0x{sectionRva + codeBytes.Length:X}, import RVA 0x{importRva:X}.");
        foreach (var offsetPos in failJumps)
        {
            var nextRva = sectionRva + offsetPos + 4;
            var rel = failRva - nextRva;
            BitConverter.GetBytes(rel).CopyTo(codeBytes, offsetPos);
        }
        codeBytes.CopyTo(pe, sectionRaw);
        return pe;

        static string GetPrintStdoutText(Dictionary<string, string> action, IrModel model)
        {
            string text;
            if (action.TryGetValue("text", out var textId) && !string.IsNullOrWhiteSpace(textId))
            {
                if (!model.Consts.TryGetValue(textId, out var textConst) || textConst.Type != "text")
                    throw new CompileError("BACKEND", "B001", 0, 0, $"Invalid print_stdout text constant: {textId}.");
                text = textConst.Value;
            }
            else if (action.GetValueOrDefault("value_kind") == "static")
            {
                text = action.GetValueOrDefault("value") ?? "";
            }
            else
            {
                throw new CompileError("BACKEND", "B001", 0, 0, "print_stdout requires either a text constant or a static runtime value.");
            }

            if (text.Length > 0 && !text.EndsWith('\n'))
                text += "\n";
            return text;
        }

        int GetPath(string path)
        {
            if (!pathRvas.TryGetValue(path, out var rva))
            {
                rva = AddUtf16(path);
                pathRvas[path] = rva;
            }
            return rva;
        }

        (int Rva, int Length) GetValue(string value)
        {
            if (!valueRvas.TryGetValue(value, out var info))
            {
                var rva = AddUtf8(value);
                info = (rva, Encoding.UTF8.GetByteCount(value));
                valueRvas[value] = info;
            }
            return info;
        }

        static int EstimateGeneratedCodeBytes(List<Dictionary<string, string>> actions)
        {
            long bytes = 0x4000;
            foreach (var action in actions)
            {
                bytes += action.GetValueOrDefault("op") switch
                {
                    "command_arg_index" => 640,
                    "command_arg_count" => 512,
                    "file_write" => 192,
                    "file_append" => 192,
                    "file_append_group" => 256 + AppendPartCount(action) * 96,
                    "file_load" => 224,
                    "print_runtime_slot" => 128,
                    "print_stdout" => 128,
                    "runtime_int_set" => 96,
                    "runtime_int_add" => 192,
                    "runtime_int_sub" => 192,
                    "runtime_bool_set" => 96,
                    "runtime_bool_not_set" => 256,
                    "runtime_bool_toggle" => 256,
                    "runtime_trap_if_bool_false" => 96,
                    "runtime_string_set" => 96,
                    "runtime_string_concat" => 384,
                    "runtime_string_substring" => 384,
                    "runtime_int_parse" => 192,
                    "runtime_if_int" => 192,
                    "runtime_if_bool" => 224,
                    "runtime_if_string" => 224,
                    "runtime_else" => 32,
                    "runtime_if_end" => 32,
                    "runtime_while_int" => 224,
                    "runtime_break" => 32,
                    "runtime_continue" => 32,
                    "runtime_while_end" => 32,
                    "function_call" => 32,
                    "function_call_assign" => 160,
                    "function_return" => 32,
                    "function_return_int" => 128,
                    "function_return_bool" => 128,
                    "function_return_string" => 128,
                    "exit" => 32,
                    _ => 192
                };
            }
            return (int)Math.Min(int.MaxValue / 2, ((bytes + 0xFFF) / 0x1000) * 0x1000);
        }

        static Dictionary<string, int> EstimateRuntimeSlotSizes(List<Dictionary<string, string>> actions, List<string> slotNames, int defaultSlotBytes)
        {
            var slotSizes = slotNames.ToDictionary(name => name, _ => defaultSlotBytes, StringComparer.Ordinal);

            for (var pass = 0; pass < 8; pass++)
            {
                var changed = false;
                var fileSizes = new Dictionary<string, long>(StringComparer.Ordinal);

                long ValueSize(Dictionary<string, string> action)
                {
                    if (action.GetValueOrDefault("value_kind") == "slot")
                    {
                        var slotName = action.GetValueOrDefault("value") ?? "";
                        return slotSizes.TryGetValue(slotName, out var slotSize) ? slotSize : defaultSlotBytes;
                    }
                    return Encoding.UTF8.GetByteCount(action.GetValueOrDefault("value") ?? "");
                }

                long OperandSize(string kind, string value)
                {
                    if (kind == "slot")
                        return slotSizes.TryGetValue(value, out var slotSize) ? slotSize : defaultSlotBytes;
                    return Encoding.UTF8.GetByteCount(value);
                }

                long AppendPartSize(Dictionary<string, string> action, int index)
                {
                    if (AppendPartKind(action, index) == "slot")
                    {
                        var slotName = AppendPartValue(action, index);
                        return slotSizes.TryGetValue(slotName, out var slotSize) ? slotSize : defaultSlotBytes;
                    }
                    return Encoding.UTF8.GetByteCount(AppendPartValue(action, index));
                }

                void NeedSlot(string name, long size)
                {
                    if (string.IsNullOrWhiteSpace(name)) return;
                    var wanted = (int)Math.Min(int.MaxValue / 2, Math.Max(defaultSlotBytes, ((size + 0xFFF) / 0x1000) * 0x1000));
                    if (!slotSizes.TryGetValue(name, out var current) || wanted > current)
                    {
                        slotSizes[name] = wanted;
                        changed = true;
                    }
                }

                foreach (var action in actions)
                {
                    var op = action.GetValueOrDefault("op");
                    if (op == "runtime_string_set")
                        NeedSlot(action.GetValueOrDefault("target") ?? "", ValueSize(action) + 1);
                    else if (op == "runtime_string_concat")
                    {
                        var left = DecodeRuntimeOperand(action.GetValueOrDefault("path") ?? "static:");
                        NeedSlot(action.GetValueOrDefault("target") ?? "", OperandSize(left.Kind, left.Value) + ValueSize(action) + 1);
                    }
                    else if (op == "runtime_string_substring")
                    {
                        var (_, length) = ParseRuntimeRange(action.GetValueOrDefault("value") ?? "0:0");
                        NeedSlot(action.GetValueOrDefault("target") ?? "", length + 1);
                    }
                    else if (op == "function_return_string")
                        NeedSlot(ReturnSlotForType("string"), ValueSize(action) + 1);
                    else if (op == "function_return_int")
                        NeedSlot(ReturnSlotForType("int"), defaultSlotBytes);
                    else if (op == "function_return_bool")
                        NeedSlot(ReturnSlotForType("bool"), defaultSlotBytes);
                    else if (op == "function_call_assign")
                    {
                        NeedSlot(action.GetValueOrDefault("target") ?? "", defaultSlotBytes);
                        NeedSlot(ReturnSlotForType(action.GetValueOrDefault("path") ?? ""), defaultSlotBytes);
                    }
                    else if (op == "command_arg_count" || op == "command_arg_index" || op == "runtime_int_set" || op == "runtime_int_add" || op == "runtime_int_sub" || op == "runtime_int_parse" || op == "runtime_if_int" || op == "runtime_while_int" || op == "runtime_bool_set" || op == "runtime_bool_not_set" || op == "runtime_bool_toggle" || op == "runtime_trap_if_bool_false" || op == "runtime_if_bool" || op == "runtime_if_string")
                        NeedSlot(action.GetValueOrDefault("target") ?? "", defaultSlotBytes);
                    else if (op == "file_write")
                        fileSizes[action.GetValueOrDefault("path") ?? ""] = ValueSize(action);
                    else if (op == "file_append")
                    {
                        var path = action.GetValueOrDefault("path") ?? "";
                        fileSizes.TryGetValue(path, out var current);
                        fileSizes[path] = current + ValueSize(action);
                    }
                    else if (op == "file_append_group")
                    {
                        var path = action.GetValueOrDefault("path") ?? "";
                        fileSizes.TryGetValue(path, out var current);
                        for (var i = 0; i < AppendPartCount(action); i++) current += AppendPartSize(action, i);
                        fileSizes[path] = current;
                    }
                    else if (op == "file_load")
                    {
                        var path = action.GetValueOrDefault("path") ?? "";
                        fileSizes.TryGetValue(path, out var fileSize);
                        NeedSlot(action.GetValueOrDefault("target") ?? "", fileSize + 1);
                    }
                }

                if (!changed) break;
            }

            return slotSizes;
        }

        static int EstimateStaticDataBytes(List<Dictionary<string, string>> actions, IrModel ir)
        {
            var bytes = 0;
            var utf8Values = new HashSet<string>(StringComparer.Ordinal) { "\n" };
            var utf16Paths = new HashSet<string>(StringComparer.Ordinal);

            foreach (var action in actions)
            {
                var op = action.GetValueOrDefault("op");
                if (op is "file_write" or "file_append" or "file_append_group" or "file_load")
                    utf16Paths.Add(action.GetValueOrDefault("path") ?? "");
                if (op == "file_append_group")
                {
                    for (var i = 0; i < AppendPartCount(action); i++)
                    {
                        if (AppendPartKind(action, i) == "static")
                            utf8Values.Add(AppendPartValue(action, i));
                    }
                }
                else if (action.GetValueOrDefault("value_kind") == "static")
                {
                    utf8Values.Add(action.GetValueOrDefault("value") ?? "");
                }
                if (op == "print_stdout")
                    utf8Values.Add(GetPrintStdoutText(action, ir));
                if ((op is "runtime_int_set" or "runtime_int_add" or "runtime_int_sub" or "runtime_int_parse" or "runtime_if_int" or "runtime_while_int" or "runtime_bool_set" or "runtime_bool_not_set" or "runtime_string_set" or "runtime_string_concat" or "runtime_string_substring" or "runtime_if_bool" or "runtime_if_string" or "function_return_int" or "function_return_bool" or "function_return_string") && action.GetValueOrDefault("value_kind") == "static")
                    utf8Values.Add(action.GetValueOrDefault("value") ?? "");
                if (op is "runtime_string_concat" or "runtime_string_substring")
                {
                    var encoded = DecodeRuntimeOperand(action.GetValueOrDefault("path") ?? "static:");
                    if (encoded.Kind == "static") utf8Values.Add(encoded.Value);
                }
                if (op is "runtime_bool_not_set" or "runtime_bool_toggle" or "runtime_trap_if_bool_false")
                {
                    utf8Values.Add("true");
                    utf8Values.Add("false");
                }
            }

            foreach (var value in utf8Values)
                bytes += Align(Encoding.UTF8.GetByteCount(value) + 1, 8);
            foreach (var path in utf16Paths)
                bytes += Align(Encoding.Unicode.GetByteCount(path + "\0"), 8);
            return bytes;
        }

        int AddUtf8(string value)
        {
            var bytes = Encoding.UTF8.GetBytes(value);
            var rva = dataCursor;
            dataCursor += Align(bytes.Length + 1, 8);
            if (dataCursor > slotLenStartRva)
                throw new CompileError("BACKEND", "B001", 0, 0, $"File I/O backend data section overlaps runtime slot metadata: data end RVA 0x{dataCursor:X}, slot metadata RVA 0x{slotLenStartRva:X}.");
            Array.Copy(bytes, 0, pe, RvaToRaw(rva), bytes.Length);
            return rva;
        }

        int AddUtf16(string value)
        {
            var bytes = Encoding.Unicode.GetBytes(value + "\0");
            var rva = dataCursor;
            dataCursor += Align(bytes.Length, 8);
            if (dataCursor > slotLenStartRva)
                throw new CompileError("BACKEND", "B001", 0, 0, $"File I/O backend data section overlaps runtime slot metadata: data end RVA 0x{dataCursor:X}, slot metadata RVA 0x{slotLenStartRva:X}.");
            Array.Copy(bytes, 0, pe, RvaToRaw(rva), bytes.Length);
            return rva;
        }

        static int Align(int value, int align) => (value + align - 1) & ~(align - 1);
        static int RvaToRaw(int rva) => sectionRaw + (rva - sectionRva);
    }
}
