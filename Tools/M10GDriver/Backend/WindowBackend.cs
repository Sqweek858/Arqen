using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

static partial class Program
{
    static byte[] BuildWindowPe(IrModel ir)
    {
        const int sectionRaw = 0x200;
        const int sectionRva = 0x1000;
        const int sectionSize = 0x5000;
        const int importRva = 0x1800;
        const int kernelIltRva = 0x1840;
        const int userIltRva = 0x1860;
        const int kernelIatRva = 0x18C0;
        const int userIatRva = 0x18E0;
        const int kernelDllNameRva = 0x1940;
        const int userDllNameRva = 0x1960;
        const int importNameCursorStart = 0x1980;
        const int dataStartRva = 0x2000;

        var actions = OrderedActionMaps(ir);
        if (actions.Count == 0 || actions[^1].GetValueOrDefault("op") != "exit")
            throw new CompileError("BACKEND", "B001", 0, 0, "Window backend requires final exit action.");

        if (actions.Any(a => a.GetValueOrDefault("op") == "print_stdout"))
            throw new CompileError("BACKEND", "B006", 0, 0, "Mixing window commands with print_stdout is not supported in M15F.");

        var pe = new byte[sectionRaw + sectionSize];
        WritePeHeader(pe, sectionSize, importRva, 0x600, subsystem: 2); // Windows GUI

        var dataCursor = dataStartRva;

        int AddUtf16(string text)
        {
            var bytes = Encoding.Unicode.GetBytes(text + "\0");
            var rva = dataCursor;
            Array.Copy(bytes, 0, pe, RvaToRaw(rva), bytes.Length);
            dataCursor += bytes.Length;
            return rva;
        }

        var classNameRva = AddUtf16("ArqenWindow");

        string windowTitle = "Arqen Window";
        int width = 1280;
        int height = 720;
        bool resizable = true;
        bool hasShow = false;
        bool hasRun = false;

        var closedHandlers = new Dictionary<string, List<Dictionary<string, string>>>(StringComparer.Ordinal);
        var keyHandlers = new Dictionary<string, List<Dictionary<string, string>>>(StringComparer.Ordinal);
        List<Dictionary<string, string>>? currentEventBlock = null;

        foreach (var action in actions)
        {
            var op = action.GetValueOrDefault("op");
            if (op == "event_window_closed")
            {
                currentEventBlock = new List<Dictionary<string, string>>();
                closedHandlers[action.GetValueOrDefault("target") ?? ""] = currentEventBlock;
            }
            else if (op == "event_key_pressed")
            {
                currentEventBlock = new List<Dictionary<string, string>>();
                keyHandlers[action.GetValueOrDefault("value") ?? ""] = currentEventBlock;
            }
            else if (op == "event_end")
            {
                currentEventBlock = null;
            }
            else if (currentEventBlock != null)
            {
                currentEventBlock.Add(action);
            }
            else
            {
                if (op == "window_set_title") windowTitle = action.GetValueOrDefault("value") ?? windowTitle;
                if (op == "window_set_resolution")
                {
                    var val = action.GetValueOrDefault("value") ?? "";
                    var parts = val.Split('x');
                    if (parts.Length == 2 && int.TryParse(parts[0], out var w) && int.TryParse(parts[1], out var h))
                    {
                        width = w;
                        height = h;
                    }
                }
                if (op == "window_set_resizable") resizable = (action.GetValueOrDefault("value") ?? "") == "true";
                if (op == "window_show") hasShow = true;
                if (op == "window_run") hasRun = true;
            }
        }

        var titleRva = AddUtf16(windowTitle);

        var kernelImports = new[] { "ExitProcess", "GetModuleHandleW" };
        var userImports = new[] { "RegisterClassW", "CreateWindowExW", "ShowWindow", "UpdateWindow", "GetMessageW", "TranslateMessage", "DispatchMessageW", "DefWindowProcW", "PostQuitMessage", "DestroyWindow", "PostMessageW" };

        var importNameCursor = importNameCursorStart;
        for (var i = 0; i < kernelImports.Length; i++)
        {
            AddImport(pe, kernelIltRva, kernelIatRva, i, importNameCursor, kernelImports[i]);
            importNameCursor += 0x20;
        }
        for (var i = 0; i < userImports.Length; i++)
        {
            AddImport(pe, userIltRva, userIatRva, i, importNameCursor, userImports[i]);
            importNameCursor += 0x20;
        }

        Encoding.ASCII.GetBytes("KERNEL32.dll\0").CopyTo(pe, RvaToRaw(kernelDllNameRva));
        Encoding.ASCII.GetBytes("USER32.dll\0").CopyTo(pe, RvaToRaw(userDllNameRva));

        // ILT / IAT table entries for KERNEL32
        pe[RvaToRaw(importRva)] = (byte)(kernelIltRva & 0xff); pe[RvaToRaw(importRva) + 1] = (byte)((kernelIltRva >> 8) & 0xff);
        pe[RvaToRaw(importRva) + 12] = (byte)(kernelDllNameRva & 0xff); pe[RvaToRaw(importRva) + 13] = (byte)((kernelDllNameRva >> 8) & 0xff);
        pe[RvaToRaw(importRva) + 16] = (byte)(kernelIatRva & 0xff); pe[RvaToRaw(importRva) + 17] = (byte)((kernelIatRva >> 8) & 0xff);

        // ILT / IAT table entries for USER32
        var userDescRva = importRva + 20;
        pe[RvaToRaw(userDescRva)] = (byte)(userIltRva & 0xff); pe[RvaToRaw(userDescRva) + 1] = (byte)((userIltRva >> 8) & 0xff);
        pe[RvaToRaw(userDescRva) + 12] = (byte)(userDllNameRva & 0xff); pe[RvaToRaw(userDescRva) + 13] = (byte)((userDllNameRva >> 8) & 0xff);
        pe[RvaToRaw(userDescRva) + 16] = (byte)(userIatRva & 0xff); pe[RvaToRaw(userDescRva) + 17] = (byte)((userIatRva >> 8) & 0xff);

        var entryRva = sectionRva + 0x100;
        var codeStart = entryRva;
        var code = new List<byte>();

        void Emit(params byte[] b) => code.AddRange(b);
        int EmitShortJump(byte opcode) { Emit(opcode, 0); return code.Count - 1; }
        void PatchShort(int jumpOffset, int targetRva) { code[jumpOffset] = (byte)((targetRva - (codeStart + jumpOffset + 1)) & 0xFF); }
        void CallIat(int rva)
        {
            Emit(0xFF, 0x15);
            var rip = codeStart + code.Count + 4;
            var offset = rva - rip;
            Emit((byte)(offset & 0xFF), (byte)((offset >> 8) & 0xFF), (byte)((offset >> 16) & 0xFF), (byte)((offset >> 24) & 0xFF));
        }

        var wndProcRva = sectionRva + 0x300;
        var wndProcCode = new List<byte>();
        void EmitProc(params byte[] b) => wndProcCode.AddRange(b);
        void CallProcIat(int rva)
        {
            EmitProc(0xFF, 0x15);
            var rip = wndProcRva + wndProcCode.Count + 4;
            var offset = rva - rip;
            EmitProc((byte)(offset & 0xFF), (byte)((offset >> 8) & 0xFF), (byte)((offset >> 16) & 0xFF), (byte)((offset >> 24) & 0xFF));
        }

        int EmitShortJumpProc(byte op)
        {
            EmitProc(op, 0x00);
            return wndProcCode.Count - 1;
        }

        void PatchShortProc(int offset)
        {
            int diff = wndProcCode.Count - (offset + 1);
            if (diff > 127) throw new CompileError("BACKEND", "B007", 0, 0, "Event block too large for short jump.");
            wndProcCode[offset] = (byte)diff;
        }

        EmitProc(0x48, 0x89, 0x4C, 0x24, 0x08); // rcx -> shadow
        EmitProc(0x89, 0x54, 0x24, 0x10);       // rdx -> shadow
        EmitProc(0x4C, 0x89, 0x44, 0x24, 0x18); // r8 -> shadow
        EmitProc(0x4C, 0x89, 0x4C, 0x24, 0x20); // r9 -> shadow
        EmitProc(0x48, 0x83, 0xEC, 0x28);       // sub rsp, 40

        // WM_DESTROY (2)
        EmitProc(0x81, 0xFA, 0x02, 0x00, 0x00, 0x00); // cmp edx, 2
        var jneDestroy = EmitShortJumpProc(0x75);
        EmitProc(0x31, 0xC9); // xor ecx, ecx
        CallProcIat(userIatRva + 8 * 8); // PostQuitMessage
        EmitProc(0x31, 0xC0); // xor eax, eax
        EmitProc(0x48, 0x83, 0xC4, 0x28); // add rsp, 40
        EmitProc(0xC3); // ret
        PatchShortProc(jneDestroy);

        // WM_CLOSE (16)
        if (closedHandlers.TryGetValue("Window", out var cActions))
        {
            EmitProc(0x81, 0xFA, 0x10, 0x00, 0x00, 0x00); // cmp edx, 16
            var jneClose = EmitShortJumpProc(0x75);
            bool explicitlyClosed = false;
            foreach (var act in cActions)
            {
                if (act.GetValueOrDefault("op") == "window_close")
                {
                    EmitProc(0x48, 0x8B, 0x4C, 0x24, 0x30); // mov rcx, [rsp+48] (hWnd)
                    CallProcIat(userIatRva + 9 * 8); // DestroyWindow
                    explicitlyClosed = true;
                }
            }
            if (explicitlyClosed)
            {
                EmitProc(0x31, 0xC0); // xor eax, eax
                EmitProc(0x48, 0x83, 0xC4, 0x28); // add rsp, 40
                EmitProc(0xC3); // ret
            }
            PatchShortProc(jneClose);
        }

        // WM_KEYDOWN (256 / 0x0100)
        if (keyHandlers.TryGetValue("Escape", out var kActions))
        {
            EmitProc(0x81, 0xFA, 0x00, 0x01, 0x00, 0x00); // cmp edx, 0x0100
            var jneKey = EmitShortJumpProc(0x75);
            EmitProc(0x49, 0x81, 0xF8, 0x1B, 0x00, 0x00, 0x00); // cmp r8, 0x1B (VK_ESCAPE)
            var jneEsc = EmitShortJumpProc(0x75);

            bool explicitlyClosed = false;
            foreach (var act in kActions)
            {
                if (act.GetValueOrDefault("op") == "window_close")
                {
                    EmitProc(0x48, 0x8B, 0x4C, 0x24, 0x30); // mov rcx, [rsp+48] (hWnd)
                    EmitProc(0xBA, 0x10, 0x00, 0x00, 0x00); // mov edx, 0x0010 (WM_CLOSE)
                    EmitProc(0x45, 0x31, 0xC0); // xor r8d, r8d
                    EmitProc(0x45, 0x31, 0xC9); // xor r9d, r9d
                    CallProcIat(userIatRva + 10 * 8); // PostMessageW
                    explicitlyClosed = true;
                }
            }
            if (explicitlyClosed)
            {
                EmitProc(0x31, 0xC0); // xor eax, eax
                EmitProc(0x48, 0x83, 0xC4, 0x28); // add rsp, 40
                EmitProc(0xC3); // ret
            }
            PatchShortProc(jneEsc);
            PatchShortProc(jneKey);
        }

        // DefWindowProcW
        EmitProc(0x48, 0x8B, 0x4C, 0x24, 0x30); // mov rcx, [rsp+48]
        EmitProc(0x8B, 0x54, 0x24, 0x38); // mov edx, [rsp+56]
        EmitProc(0x4C, 0x8B, 0x44, 0x24, 0x40); // mov r8, [rsp+64]
        EmitProc(0x4C, 0x8B, 0x4C, 0x24, 0x48); // mov r9, [rsp+72]
        CallProcIat(userIatRva + 7 * 8); // DefWindowProcW
        EmitProc(0x48, 0x83, 0xC4, 0x28); // add rsp, 40
        EmitProc(0xC3); // ret

        Array.Copy(wndProcCode.ToArray(), 0, pe, RvaToRaw(wndProcRva), wndProcCode.Count);

        Emit(0x48, 0x83, 0xEC, 0x68); // sub rsp, 104
        Emit(0x31, 0xC9); // xor ecx, ecx
        CallIat(kernelIatRva + 1 * 8); // GetModuleHandleW
        Emit(0x48, 0x89, 0xC3); // mov rbx, rax (hInstance)

        Emit(0x48, 0x8D, 0x4C, 0x24, 0x20); // mov rcx, rsp+32
        Emit(0x31, 0xD2); // xor edx, edx
        Emit(0x41, 0xB8, 0x48, 0x00, 0x00, 0x00); // mov r8d, 72 (sizeof WNDCLASSW)
        // memset is complex, let's just zero it directly
        for(int j=0; j<8; j++) Emit(0x48, 0xC7, 0x44, 0x24, (byte)(0x20 + j*8), 0x00, 0x00, 0x00, 0x00);

        Emit(0x48, 0x8D, 0x05);
        int wndProcOffset = wndProcRva - (codeStart + code.Count + 4);
        Emit((byte)(wndProcOffset & 0xFF), (byte)((wndProcOffset >> 8) & 0xFF), (byte)((wndProcOffset >> 16) & 0xFF), (byte)((wndProcOffset >> 24) & 0xFF));
        Emit(0x48, 0x89, 0x44, 0x24, 0x28); // lpfnWndProc = wndProcRva

        Emit(0x48, 0x89, 0x5C, 0x24, 0x38); // hInstance = rbx

        Emit(0x48, 0x8D, 0x05);
        int classNameOffset = classNameRva - (codeStart + code.Count + 4);
        Emit((byte)(classNameOffset & 0xFF), (byte)((classNameOffset >> 8) & 0xFF), (byte)((classNameOffset >> 16) & 0xFF), (byte)((classNameOffset >> 24) & 0xFF));
        Emit(0x48, 0x89, 0x44, 0x24, 0x60); // lpszClassName = classNameRva

        Emit(0x48, 0x8D, 0x4C, 0x24, 0x20); // rcx = &wc
        CallIat(userIatRva); // RegisterClassW

        Emit(0x48, 0xC7, 0xC1, 0x00, 0x00, 0x00, 0x00); // rcx = 0
        Emit(0x48, 0x8D, 0x15); // rdx = classNameRva
        classNameOffset = classNameRva - (codeStart + code.Count + 4);
        Emit((byte)(classNameOffset & 0xFF), (byte)((classNameOffset >> 8) & 0xFF), (byte)((classNameOffset >> 16) & 0xFF), (byte)((classNameOffset >> 24) & 0xFF));
        Emit(0x4C, 0x8D, 0x05); // r8 = titleRva
        int titleOffset = titleRva - (codeStart + code.Count + 4);
        Emit((byte)(titleOffset & 0xFF), (byte)((titleOffset >> 8) & 0xFF), (byte)((titleOffset >> 16) & 0xFF), (byte)((titleOffset >> 24) & 0xFF));

        // WS_VISIBLE=0x10000000, WS_OVERLAPPEDWINDOW=0x00CF0000, WS_CAPTION=0x00C00000, WS_SYSMENU=0x00080000, WS_MINIMIZEBOX=0x00020000
        uint style = resizable ? 0x10CF0000u : 0x10CA0000u;
        Emit(0x41, 0xB9, (byte)(style & 0xFF), (byte)((style >> 8) & 0xFF), (byte)((style >> 16) & 0xFF), (byte)((style >> 24) & 0xFF)); // r9 = style

        Emit(0xC7, 0x44, 0x24, 0x20, 0x00, 0x00, 0x00, 0x80); // CW_USEDEFAULT
        Emit(0xC7, 0x44, 0x24, 0x28, 0x00, 0x00, 0x00, 0x80); // CW_USEDEFAULT
        Emit(0xC7, 0x44, 0x24, 0x30, (byte)(width & 0xFF), (byte)((width >> 8) & 0xFF), 0x00, 0x00);
        Emit(0xC7, 0x44, 0x24, 0x38, (byte)(height & 0xFF), (byte)((height >> 8) & 0xFF), 0x00, 0x00);
        Emit(0x48, 0xC7, 0x44, 0x24, 0x40, 0x00, 0x00, 0x00, 0x00); // hWndParent
        Emit(0x48, 0xC7, 0x44, 0x24, 0x48, 0x00, 0x00, 0x00, 0x00); // hMenu
        Emit(0x48, 0x89, 0x5C, 0x24, 0x50); // hInstance
        Emit(0x48, 0xC7, 0x44, 0x24, 0x58, 0x00, 0x00, 0x00, 0x00); // lpParam

        CallIat(userIatRva + 1 * 8); // CreateWindowExW
        Emit(0x48, 0x89, 0xC3); // rbx = hWnd

        if (hasShow)
        {
            Emit(0x48, 0x89, 0xD9); // rcx = hWnd
            Emit(0xBA, 0x01, 0x00, 0x00, 0x00); // rdx = SW_SHOWNORMAL
            CallIat(userIatRva + 2 * 8); // ShowWindow
            Emit(0x48, 0x89, 0xD9); // rcx = hWnd
            CallIat(userIatRva + 3 * 8); // UpdateWindow
        }

        if (hasRun && hasShow)
        {
            var msgLoopStart = code.Count;
            Emit(0x48, 0x8D, 0x4C, 0x24, 0x20); // rcx = &msg
            Emit(0x31, 0xD2); // rdx = 0
            Emit(0x45, 0x31, 0xC0); // r8 = 0
            Emit(0x45, 0x31, 0xC9); // r9 = 0
            CallIat(userIatRva + 4 * 8); // GetMessageW
            Emit(0x85, 0xC0); // test eax, eax
            var jzExit = EmitShortJump(0x74); // jz exit
            Emit(0x48, 0x8D, 0x4C, 0x24, 0x20); // rcx = &msg
            CallIat(userIatRva + 5 * 8); // TranslateMessage
            Emit(0x48, 0x8D, 0x4C, 0x24, 0x20); // rcx = &msg
            CallIat(userIatRva + 6 * 8); // DispatchMessageW
            var jmpLoop = EmitShortJump(0xEB); // jmp loop
            PatchShort(jmpLoop, sectionRva + 0x100 + msgLoopStart);
            PatchShort(jzExit, sectionRva + 0x100 + code.Count);
        }

        Emit(0x31, 0xC9); // xor ecx, ecx
        CallIat(kernelIatRva); // ExitProcess

        Array.Copy(code.ToArray(), 0, pe, RvaToRaw(entryRva), code.Count);
        pe[0x128] = (byte)(entryRva & 0xff);
        pe[0x129] = (byte)((entryRva >> 8) & 0xff);
        pe[0x12A] = (byte)((entryRva >> 16) & 0xff);
        pe[0x12B] = (byte)((entryRva >> 24) & 0xff);

        return pe;

        int RvaToRaw(int rva) => sectionRaw + (rva - sectionRva);
    }
}
