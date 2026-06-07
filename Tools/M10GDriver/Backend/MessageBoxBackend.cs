using System;
using System.Collections.Generic;
using System.Text;

static partial class Program
{
    static byte[] BuildMessageBoxPe(string text, string title)
    {
        const int sectionRaw = 0x200;
        const int sectionRva = 0x1000;
        const int sectionSize = 0x4000;
        const int importRva = 0x1300;
        const int userIltRva = 0x1380;
        const int userIatRva = 0x1390;
        const int kernelIltRva = 0x13a0;
        const int kernelIatRva = 0x13b0;
        const int userNameRva = 0x13c0;
        const int kernelNameRva = 0x13d0;
        const int messageBoxNameRva = 0x13f0;
        const int exitProcessNameRva = 0x1410;
        const int messageRva = 0x1800;
        const int titleRva = 0x3000;
        const int maxMessageBytes = 0x400;
        const int maxTitleBytes = 0x100;

        var messageBytes = Encoding.Unicode.GetBytes(text + "\0");
        var titleBytes = Encoding.Unicode.GetBytes(title + "\0");
        if (messageBytes.Length > maxMessageBytes)
            throw new CompileError("BACKEND", "B003", 0, 0, $"visual message text too long for M15B backend: {messageBytes.Length} bytes.");
        if (titleBytes.Length > maxTitleBytes)
            throw new CompileError("BACKEND", "B003", 0, 0, $"visual title too long for M15B backend: {titleBytes.Length} bytes.");

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
        WriteUInt32(pe, opt + 56, 0x5000);
        WriteUInt32(pe, opt + 60, 0x200);
        WriteUInt16(pe, opt + 68, 2);
        WriteUInt64(pe, opt + 72, 0x100000);
        WriteUInt64(pe, opt + 80, 0x1000);
        WriteUInt64(pe, opt + 88, 0x100000);
        WriteUInt64(pe, opt + 96, 0x1000);
        WriteUInt32(pe, opt + 108, 16);
        WriteUInt32(pe, opt + 120, importRva);
        WriteUInt32(pe, opt + 124, 0x300);

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

        Emit(0x48, 0x83, 0xec, 0x28);
        Emit(0x31, 0xC9);
        Lea(new byte[] { 0x48, 0x8D, 0x15 }, messageRva, 7);
        Lea(new byte[] { 0x4C, 0x8D, 0x05 }, titleRva, 7);
        Emit(0x45, 0x31, 0xC9);
        CallIat(userIatRva);
        Emit(0x31, 0xC9);
        CallIat(kernelIatRva);
        code.CopyTo(pe, sectionRaw);

        var importRaw = RvaToRaw(importRva);
        WriteUInt32(pe, importRaw, userIltRva);
        WriteUInt32(pe, importRaw + 12, userNameRva);
        WriteUInt32(pe, importRaw + 16, userIatRva);
        WriteUInt32(pe, importRaw + 20, kernelIltRva);
        WriteUInt32(pe, importRaw + 32, kernelNameRva);
        WriteUInt32(pe, importRaw + 36, kernelIatRva);

        AddImport(pe, userIltRva, userIatRva, 0, messageBoxNameRva, "MessageBoxW");
        AddImport(pe, kernelIltRva, kernelIatRva, 0, exitProcessNameRva, "ExitProcess");
        WriteAscii(pe, RvaToRaw(userNameRva), "user32.dll\0");
        WriteAscii(pe, RvaToRaw(kernelNameRva), "kernel32.dll\0");
        Array.Copy(messageBytes, 0, pe, RvaToRaw(messageRva), messageBytes.Length);
        Array.Copy(titleBytes, 0, pe, RvaToRaw(titleRva), titleBytes.Length);
        return pe;

        static int RvaToRaw(int rva) => sectionRaw + (rva - sectionRva);
    }
}
