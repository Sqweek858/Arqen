using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

static partial class Program
{
    static void WritePeHeader(byte[] pe, int sectionSize, int importRva, int importSize, ushort subsystem)
    {
        WriteAscii(pe, 0, "MZ");
        WriteUInt32(pe, 0x3c, 0x80);

        var peOffset = 0x80;
        WriteAscii(pe, peOffset, "PE\0\0");
        var coff = peOffset + 4;
        WriteUInt16(pe, coff, 0x8664);
        WriteUInt16(pe, coff + 2, 1);
        WriteUInt16(pe, coff + 16, 0xF0);
        WriteUInt16(pe, coff + 18, 0x22);

        var opt = coff + 20;
        WriteUInt16(pe, opt, 0x20b);
        pe[opt + 2] = 14;
        WriteUInt32(pe, opt + 4, (uint)sectionSize);
        WriteUInt32(pe, opt + 16, 0x1000);
        WriteUInt32(pe, opt + 20, 0x1000);
        WriteUInt64(pe, opt + 24, 0x140000000);
        WriteUInt32(pe, opt + 32, 0x1000);
        WriteUInt32(pe, opt + 36, 0x200);
        WriteUInt16(pe, opt + 40, 6);
        WriteUInt16(pe, opt + 48, 6);
        WriteUInt32(pe, opt + 56, (uint)(0x1000 + sectionSize));
        WriteUInt32(pe, opt + 60, 0x200);
        WriteUInt16(pe, opt + 68, subsystem);
        WriteUInt64(pe, opt + 72, 0x100000);
        WriteUInt64(pe, opt + 80, 0x1000);
        WriteUInt64(pe, opt + 88, 0x100000);
        WriteUInt64(pe, opt + 96, 0x1000);
        WriteUInt32(pe, opt + 108, 16);
        WriteUInt32(pe, opt + 120, (uint)importRva);
        WriteUInt32(pe, opt + 124, (uint)importSize);

        var section = opt + 0xF0;
        WriteAscii(pe, section, ".text\0\0\0");
        WriteUInt32(pe, section + 8, (uint)sectionSize);
        WriteUInt32(pe, section + 12, 0x1000);
        WriteUInt32(pe, section + 16, (uint)sectionSize);
        WriteUInt32(pe, section + 20, 0x200);
        WriteUInt32(pe, section + 36, 0xE0000020);
    }

    static List<Dictionary<string, string>> OrderedActionMaps(IrModel ir)
        => ir.EntryActions
            .Where(id => ir.Actions.ContainsKey(id))
            .Select(id => ir.Actions[id])
            .ToList();

    static bool HasFileIoActions(IrModel ir)
        => ir.Actions.Values.Any(action =>
            action.TryGetValue("op", out var op) &&
            op is "file_write" or "file_append" or "file_load" or "print_runtime_slot" or "command_arg_count" or "command_arg_index");

    static bool HasWindowActions(IrModel ir)
        => ir.Actions.Values.Any(action =>
            action.TryGetValue("op", out var op) &&
            (op.StartsWith("window_", StringComparison.Ordinal) || op.StartsWith("event_", StringComparison.Ordinal)));

    static byte[] BuildStdoutPe(string text)
    {
        const int sectionRaw = 0x200;
        const int sectionRva = 0x1000;
        const int sectionSize = 0x1000;
        const int messageRva = 0x1500;
        const int writtenRva = 0x1f00;
        const int importRva = 0x1300;
        const int iltRva = 0x1340;
        const int iatRva = 0x1360;
        const int dllNameRva = 0x1380;
        const int maxMessageBytes = 0x900;

        var messageBytes = Encoding.UTF8.GetBytes(text);
        if (messageBytes.Length > maxMessageBytes)
            throw new CompileError("BACKEND", "B004", 0, 0, $"stdout text too long for M15 stdout backend: {messageBytes.Length} bytes.");

        var pe = new byte[sectionRaw + sectionSize];
        WriteAscii(pe, 0, "MZ");
        WriteUInt32(pe, 0x3c, 0x80);

        var peOffset = 0x80;
        WriteAscii(pe, peOffset, "PE\0\0");
        var coff = peOffset + 4;
        WriteUInt16(pe, coff, 0x8664);
        WriteUInt16(pe, coff + 2, 1);
        WriteUInt16(pe, coff + 16, 0xF0);
        WriteUInt16(pe, coff + 18, 0x22);

        var opt = coff + 20;
        WriteUInt16(pe, opt, 0x20b);
        pe[opt + 2] = 14;
        WriteUInt32(pe, opt + 4, sectionSize);
        WriteUInt32(pe, opt + 16, sectionRva);
        WriteUInt32(pe, opt + 20, sectionRva);
        WriteUInt64(pe, opt + 24, 0x140000000);
        WriteUInt32(pe, opt + 32, 0x1000);
        WriteUInt32(pe, opt + 36, 0x200);
        WriteUInt16(pe, opt + 40, 6);
        WriteUInt16(pe, opt + 48, 6);
        WriteUInt32(pe, opt + 56, 0x2000);
        WriteUInt32(pe, opt + 60, 0x200);
        WriteUInt16(pe, opt + 68, 3);
        WriteUInt64(pe, opt + 72, 0x100000);
        WriteUInt64(pe, opt + 80, 0x1000);
        WriteUInt64(pe, opt + 88, 0x100000);
        WriteUInt64(pe, opt + 96, 0x1000);
        WriteUInt32(pe, opt + 108, 16);
        WriteUInt32(pe, opt + 120, importRva);
        WriteUInt32(pe, opt + 124, 0x100);

        var section = opt + 0xF0;
        WriteAscii(pe, section, ".text\0\0\0");
        WriteUInt32(pe, section + 8, sectionSize);
        WriteUInt32(pe, section + 12, sectionRva);
        WriteUInt32(pe, section + 16, sectionSize);
        WriteUInt32(pe, section + 20, sectionRaw);
        WriteUInt32(pe, section + 36, 0xE0000020);

        var code = new List<byte>();
        void Emit(params byte[] bytes) => code.AddRange(bytes);
        void EmitUInt32(uint value) => code.AddRange(BitConverter.GetBytes(value));
        void CallIat(int rva)
        {
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

        Emit(0x48, 0x83, 0xec, 0x38);
        Emit(0xB9, 0xF5, 0xFF, 0xFF, 0xFF);
        CallIat(iatRva);
        Emit(0x48, 0x89, 0xC1);
        Lea(new byte[] { 0x48, 0x8D, 0x15 }, messageRva, 7);
        Emit(0x41, 0xB8);
        EmitUInt32((uint)messageBytes.Length);
        Lea(new byte[] { 0x4C, 0x8D, 0x0D }, writtenRva, 7);
        Emit(0x48, 0xC7, 0x44, 0x24, 0x20, 0, 0, 0, 0);
        CallIat(iatRva + 8);
        Emit(0x31, 0xC9);
        CallIat(iatRva + 16);
        code.CopyTo(pe, sectionRaw);

        var importRaw = RvaToRaw(importRva);
        WriteUInt32(pe, importRaw, iltRva);
        WriteUInt32(pe, importRaw + 12, dllNameRva);
        WriteUInt32(pe, importRaw + 16, iatRva);

        AddImport(pe, iltRva, iatRva, 0, 0x13a0, "GetStdHandle");
        AddImport(pe, iltRva, iatRva, 1, 0x13c0, "WriteFile");
        AddImport(pe, iltRva, iatRva, 2, 0x13d8, "ExitProcess");
        WriteAscii(pe, RvaToRaw(dllNameRva), "kernel32.dll\0");
        Array.Copy(messageBytes, 0, pe, RvaToRaw(messageRva), messageBytes.Length);
        return pe;

        static int RvaToRaw(int rva) => sectionRaw + (rva - sectionRva);
    }

    static void AddImport(byte[] pe, int iltRva, int iatRva, int index, int nameRva, string name)
    {
        WriteUInt64(pe, RvaToRawLocal(iltRva) + index * 8, (ulong)nameRva);
        WriteUInt64(pe, RvaToRawLocal(iatRva) + index * 8, (ulong)nameRva);
        var raw = RvaToRawLocal(nameRva);
        WriteUInt16(pe, raw, 0);
        WriteAscii(pe, raw + 2, name + "\0");

        static int RvaToRawLocal(int rva) => 0x200 + (rva - 0x1000);
    }

    static void WriteUInt16(byte[] bytes, int offset, ushort value)
        => BitConverter.GetBytes(value).CopyTo(bytes, offset);

    static void WriteUInt32(byte[] bytes, int offset, uint value)
        => BitConverter.GetBytes(value).CopyTo(bytes, offset);

    static void WriteUInt64(byte[] bytes, int offset, ulong value)
        => BitConverter.GetBytes(value).CopyTo(bytes, offset);

    static void WriteAscii(byte[] bytes, int offset, string value)
    {
        var encoded = Encoding.ASCII.GetBytes(value);
        Array.Copy(encoded, 0, bytes, offset, encoded.Length);
    }

    static void PatchUtf16(byte[] pe, int offset, int maxBytes, string value)
    {
        var bytes = Encoding.Unicode.GetBytes(value + "\0");
        if (bytes.Length > maxBytes)
            throw new CompileError("BACKEND", "B001", 0, 0, $"String too long for PE template buffer: {value}");
        Array.Clear(pe, offset, maxBytes);
        Array.Copy(bytes, 0, pe, offset, bytes.Length);
    }
}
