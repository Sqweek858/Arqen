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
        const int sectionSize = 0x100000;
        const int importRva = 0x40000;
        const int iltRva = 0x40100;
        const int iatRva = 0x40180;
        const int kernelDllNameRva = 0x40280;
        const int dataStartRva = 0x41000;
        const int slotLenStartRva = 0xE0000;
        const int slotStartRva = 0xE1000;
        const int runtimeSlotBytes = 0x1000;
        const int bytesWrittenRva = slotLenStartRva - 8;

        var actions = OrderedActionMaps(ir);
        if (actions.Count == 0 || actions[^1].GetValueOrDefault("op") != "exit")
            throw new CompileError("BACKEND", "B001", 0, 0, "File I/O backend requires final exit action.");

        var pe = new byte[sectionRaw + sectionSize];
        WritePeHeader(pe, sectionSize, importRva, 0x600, subsystem: 3);

        var slotNames = actions
            .Where(a => a.GetValueOrDefault("value_kind") == "slot" || a.GetValueOrDefault("op") == "file_load" || a.GetValueOrDefault("op") == "print_runtime_slot" || a.GetValueOrDefault("op") == "command_arg_count" || a.GetValueOrDefault("op") == "command_arg_index")
            .Select(a => a.GetValueOrDefault("target") != "" ? a.GetValueOrDefault("target")! : a.GetValueOrDefault("value")!)
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Distinct(StringComparer.Ordinal)
            .ToList();
        var slots = new Dictionary<string, (int BufferRva, int LenRva)>(StringComparer.Ordinal);
        var maxRuntimeSlots = (sectionRva + sectionSize - slotStartRva) / runtimeSlotBytes;
        if (slotNames.Count > maxRuntimeSlots)
            throw new CompileError("BACKEND", "B001", 0, 0, $"Too many runtime string slots for file I/O backend: {slotNames.Count} > {maxRuntimeSlots}.");
        for (var i = 0; i < slotNames.Count; i++)
            slots[slotNames[i]] = (slotStartRva + i * runtimeSlotBytes, slotLenStartRva + i * 8);

        var dataCursor = dataStartRva;
        var pathRvas = new Dictionary<string, int>(StringComparer.Ordinal);
        var valueRvas = new Dictionary<string, (int Rva, int Length)>(StringComparer.Ordinal);
        var newlineRva = AddUtf8("\n");

        foreach (var action in actions)
        {
            var op = action.GetValueOrDefault("op");
            if (op is "file_write" or "file_append" or "file_load")
                GetPath(action.GetValueOrDefault("path") ?? "");
            if (action.GetValueOrDefault("value_kind") == "static")
                GetValue(action.GetValueOrDefault("value") ?? "");
            if (op == "print_stdout")
            {
                var textId = action["text"];
                var text = ir.Consts[textId].Value;
                if (text.Length > 0 && !text.EndsWith('\n')) text += "\n";
                var messageBytes = Encoding.UTF8.GetBytes(text);
                if (messageBytes.Length > 0x900)
                    throw new CompileError("BACKEND", "B004", 0, 0, $"stdout text too long for M15 stdout backend: {messageBytes.Length} bytes.");
                GetValue(text);
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
        WriteUInt32(pe, importRaw, iltRva);
        WriteUInt32(pe, importRaw + 12, kernelDllNameRva);
        WriteUInt32(pe, importRaw + 16, iatRva);

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
            Emit(0x44, 0x89, 0xC8);

            Emit(0x89, 0xC3);
            Emit(0x83, 0xF8, 0x0A);
            var oneDigit = EmitNearJump2(0x0F, 0x8C);
            Emit(0x31, 0xD2);
            Emit(0xB9, 0x0A, 0x00, 0x00, 0x00);
            Emit(0xF7, 0xF1);
            Emit(0x04, 0x30);
            StoreByteFromAl(slot.BufferRva);
            Emit(0x80, 0xC2, 0x30);
            StoreByteFromDl(slot.BufferRva + 1);
            StoreDwordMem(slot.LenRva, 2);
            var done = EmitShortJump(0xEB);
            var oneDigitRva = sectionRva + code.Count;
            Emit(0x80, 0xC3, 0x30);
            StoreByteFromBl(slot.BufferRva);
            StoreDwordMem(slot.LenRva, 1);
            var doneRva = sectionRva + code.Count;
            PatchRel32(oneDigit, oneDigitRva);
            PatchShort(done, doneRva);
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
            Emit(0x41, 0x83, 0xF9, unchecked((byte)index));
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
            EmitUInt32(runtimeSlotBytes - 1);
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
            EmitUInt32(runtimeSlotBytes - 1);
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

        Emit(0x48, 0x83, 0xEC, 0x58);
        foreach (var action in actions)
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
            else if (op == "file_load")
            {
                var slot = slots[action["target"]];
                OpenFile(action["path"], 0x80000000, 3);
                Emit(0x48, 0x89, 0xD9);
                Lea(new byte[] { 0x48, 0x8D, 0x15 }, slot.BufferRva, 7);
                Emit(0x41, 0xB8); EmitUInt32(runtimeSlotBytes);
                Lea(new byte[] { 0x4C, 0x8D, 0x0D }, slot.LenRva, 7);
                StoreStack32(0x20, 0);
                CallIat(2);
                CheckEaxZero();
                var nextRva = sectionRva + code.Count + 10;
                Emit(0x81, 0x3D);
                EmitUInt32(unchecked((uint)(slot.LenRva - nextRva)));
                EmitUInt32(runtimeSlotBytes);
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
                var textId = action["text"];
                var text = ir.Consts[textId].Value;
                if (text.Length > 0 && !text.EndsWith('\n')) text += "\n";
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
            else if (op == "exit")
            {
                // Emitted once at the end.
            }
            else
            {
                throw new CompileError("BACKEND", "B001", 0, 0, $"Unsupported file I/O backend action: {op}.");
            }
        }

        Emit(0x31, 0xC9);
        CallIat(7);
        var failRva = sectionRva + code.Count;
        Emit(0xB9, 0x01, 0x00, 0x00, 0x00);
        CallIat(7);
        foreach (var offsetPos in failJumps)
        {
            var nextRva = sectionRva + offsetPos + 4;
            var rel = failRva - nextRva;
            BitConverter.GetBytes(rel).CopyTo(code.ToArray(), offsetPos);
        }
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
