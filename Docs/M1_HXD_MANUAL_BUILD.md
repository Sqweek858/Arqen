# Milestone 1 Manual HxD Build

Goal:

- Create the first Arqen Byte Zero executable manually in HxD.
- Do not use a compiler, assembler, linker, or generator.
- Use `M1_BYTE_CHECKLIST.md` as the source of truth.

## Output File

Recommended output path:

```text
C:\Users\Sqweek\Documents\Arqen\Arqen\Experiments\M1_ExitProcess\arqen_m1_exitprocess.exe
```

If the folder does not exist yet, create it manually or let Codex create only that folder when approved.

## HxD Steps

1. Open HxD.
2. Create a new file.
3. Insert `0x600` bytes filled with `00`.
4. Save it as `arqen_m1_exitprocess.exe`.
5. Use `M1_BYTE_CHECKLIST.md`.
6. For each listed offset, jump to that offset and overwrite the exact bytes.
7. Do not insert bytes after the initial `0x600`; only overwrite.
8. Final file size must remain exactly `0x600` bytes.

## Important HxD Rule

Use overwrite mode, not insert mode.

If a byte edit changes the file size, the file is wrong.

Expected final size:

```text
0x600 bytes = 1536 bytes
```

## Write Order

Recommended order:

1. DOS header
2. PE signature
3. COFF header
4. Optional header
5. Data directories
6. Section table
7. `.text` raw data
8. `.idata` raw data

This order matches the file layout and makes verification easier.

## First PE-bear Check

After saving:

1. Open the file in PE-bear.
2. Confirm:
   - PE32+
   - Machine: AMD64
   - `ImageBase = 0x140000000`
   - `AddressOfEntryPoint = 0x1000`
   - `.text` raw offset `0x200`, RVA `0x1000`
   - `.idata` raw offset `0x400`, RVA `0x2000`
3. Open the imports view.
4. Confirm:
   - `kernel32.dll`
   - `ExitProcess`

If PE-bear cannot parse the file, do not run it yet.

## Terminal Run Check

Only after PE-bear looks correct, run from PowerShell:

```powershell
& "C:\Users\Sqweek\Documents\Arqen\Arqen\Experiments\M1_ExitProcess\arqen_m1_exitprocess.exe"
$LASTEXITCODE
```

Expected result:

```text
0
```

## x64dbg Check

Open the executable in x64dbg.

Expected:

- entry point is at image base plus `0x1000`
- first bytes at entry:

```text
48 83 EC 28 31 C9 FF 15 44 10 00 00
```

Expected behavior:

- program reaches the call through IAT
- `ExitProcess` is called
- process exits cleanly

## If It Fails

Do not patch randomly.

Check in this order:

1. File size is exactly `0x600`.
2. `e_lfanew` at `0x003C` is `80 00 00 00`.
3. PE signature at `0x0080` is `50 45 00 00`.
4. Section table starts at `0x0188`.
5. `.text` raw offset is `0x0200`.
6. `.idata` raw offset is `0x0400`.
7. Import directory is `RVA 0x2000`, size `0x28`.
8. IAT directory is `RVA 0x2050`, size `0x10`.
9. IAT slot contains `60 20 00 00 00 00 00 00` before load.
10. Hint/name says `ExitProcess`.
11. DLL name says `kernel32.dll`.

