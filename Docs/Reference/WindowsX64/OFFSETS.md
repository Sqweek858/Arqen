# Offset Ledger

This file records every byte range we plan or write.

Rule: no PE byte should be considered "done" unless it has an offset, field name, value, reason, and verification method.

## Global Layout Draft

Planning decision for Milestone 0 / 1:

- Put NT headers at file offset `0x0080`.
- Keep all headers inside the first `0x200` bytes.
- Put `.text` raw data at file offset `0x0200`.
- Put `.idata` raw data at file offset `0x0400`.

| File Offset | RVA | Size | Area | Notes |
|---:|---:|---:|---|---|
| `0x0000` | n/a | `0x0040` | DOS header | Starts with `MZ`; `e_lfanew` at `0x003C` |
| `0x0040` | n/a | `0x0040` | DOS stub / padding | Minimal filler until NT headers |
| `0x0080` | n/a | `0x0004` | PE signature | `PE\0\0` |
| `0x0084` | n/a | `0x0014` | COFF file header | AMD64, 2 sections |
| `0x0098` | n/a | `0x00F0` | Optional header PE32+ | Standard PE32+ header with 16 data directories |
| `0x0188` | n/a | `0x0028` | `.text` section header | First section table entry |
| `0x01B0` | n/a | `0x0028` | `.idata` section header | Second section table entry |
| `0x01D8` | n/a | `0x0028` | Header padding | Pads headers to `0x0200` |
| `0x0200` | `0x1000` | `0x0200` | `.text` raw data | First section, one file-aligned block |
| `0x0400` | `0x2000` | `0x0200` | `.idata` raw data | Import section, one file-aligned block |

## Initial Constants

| Name | Value | Reason |
|---|---:|---|
| `ImageBase` | `0x0000000140000000` | Common Windows x64 image base |
| `SectionAlignment` | `0x1000` | Common page alignment |
| `FileAlignment` | `0x200` | Common disk alignment |
| `.text RVA` | `0x1000` | First section after headers |
| `.text raw offset` | `0x0200` | First file-aligned block after headers |
| `.idata RVA` | `0x2000` | Second section page |
| `.idata raw offset` | `0x0400` | Second file-aligned block |
| `NT headers file offset` | `0x0080` | Simple conventional placement after DOS header/stub |
| `SizeOfHeaders` | `0x0200` | Headers fit inside one file-aligned block |
| `NumberOfRvaAndSizes` | `16` | Standard PE data directory count |

## Fields To Define

### DOS Header

| Offset | Field | Value | Why | Verify |
|---:|---|---|---|---|
| `0x0000` | `e_magic` | `MZ` / `0x5A4D` | DOS/PE signature | PE-bear DOS header |
| `0x003C` | `e_lfanew` | `0x00000080` | Points to NT headers at file offset `0x80` | PE-bear NT headers |

### NT Headers

| Offset | Field | Value | Why | Verify |
|---:|---|---|---|---|
| `0x0080` | PE signature | `PE\0\0` / `50 45 00 00` | Marks start of NT headers | PE-bear NT headers |

### COFF Header

| Offset | Field | Value | Why | Verify |
|---:|---|---|---|---|
| `0x0084` | `Machine` | `0x8664` | AMD64 | PE-bear File Header |
| `0x0086` | `NumberOfSections` | `2` | `.text`, `.idata` | PE-bear sections |
| `0x0088` | `TimeDateStamp` | `0` | Deterministic first layout | PE-bear File Header |
| `0x008C` | `PointerToSymbolTable` | `0` | No COFF symbols | PE-bear File Header |
| `0x0090` | `NumberOfSymbols` | `0` | No COFF symbols | PE-bear File Header |
| `0x0094` | `SizeOfOptionalHeader` | `0x00F0` | PE32+ optional header with 16 data directories | PE-bear File Header |
| `0x0096` | `Characteristics` | `0x0022` | Executable image, large-address-aware | PE-bear File Header |

### Optional Header PE32+

| Offset | Field | Value | Why | Verify |
|---:|---|---|---|---|
| `0x0098` | `Magic` | `0x20B` | PE32+ | PE-bear Optional Header |
| `0x009A` | `MajorLinkerVersion` | `0` | No linker | PE-bear Optional Header |
| `0x009B` | `MinorLinkerVersion` | `0` | No linker | PE-bear Optional Header |
| `0x009C` | `SizeOfCode` | `0x200` | One raw `.text` block | PE-bear Optional Header |
| `0x00A0` | `SizeOfInitializedData` | `0x200` | One raw `.idata` block | PE-bear Optional Header |
| `0x00A4` | `SizeOfUninitializedData` | `0` | No `.bss` | PE-bear Optional Header |
| `0x00A8` | `AddressOfEntryPoint` | `0x1000` | Start at beginning of `.text` | PE-bear Optional Header / x64dbg |
| `0x00AC` | `BaseOfCode` | `0x1000` | `.text` RVA | PE-bear Optional Header |
| `0x00B0` | `ImageBase` | `0x140000000` | x64 image base | PE-bear Optional Header |
| `0x00B8` | `SectionAlignment` | `0x1000` | Memory alignment | PE-bear Optional Header |
| `0x00BC` | `FileAlignment` | `0x200` | File alignment | PE-bear Optional Header |
| `0x00C0` | `MajorOperatingSystemVersion` | `6` | Modern Windows baseline | PE-bear Optional Header |
| `0x00C2` | `MinorOperatingSystemVersion` | `0` | Modern Windows baseline | PE-bear Optional Header |
| `0x00C4` | `MajorImageVersion` | `0` | Prototype | PE-bear Optional Header |
| `0x00C6` | `MinorImageVersion` | `0` | Prototype | PE-bear Optional Header |
| `0x00C8` | `MajorSubsystemVersion` | `6` | Modern Windows baseline | PE-bear Optional Header |
| `0x00CA` | `MinorSubsystemVersion` | `0` | Modern Windows baseline | PE-bear Optional Header |
| `0x00CC` | `Win32VersionValue` | `0` | Reserved | PE-bear Optional Header |
| `0x00D0` | `SizeOfImage` | `0x3000` | Headers + `.text` + `.idata` aligned in memory | PE-bear Optional Header |
| `0x00D4` | `SizeOfHeaders` | `0x200` | Headers occupy one file-aligned block | PE-bear Optional Header |
| `0x00D8` | `CheckSum` | `0` | Not required for normal EXE | PE-bear Optional Header |
| `0x00DC` | `Subsystem` | `3` | Windows CUI for first exit-code testing | PE-bear Optional Header |
| `0x00DE` | `DllCharacteristics` | `0` | Keep first image simple, no ASLR flags yet | PE-bear Optional Header |
| `0x00E0` | `SizeOfStackReserve` | `0x100000` | Common default stack reserve | PE-bear Optional Header |
| `0x00E8` | `SizeOfStackCommit` | `0x1000` | Common default stack commit | PE-bear Optional Header |
| `0x00F0` | `SizeOfHeapReserve` | `0x100000` | Common default heap reserve | PE-bear Optional Header |
| `0x00F8` | `SizeOfHeapCommit` | `0x1000` | Common default heap commit | PE-bear Optional Header |
| `0x0100` | `LoaderFlags` | `0` | Reserved | PE-bear Optional Header |
| `0x0104` | `NumberOfRvaAndSizes` | `16` | Standard data directory count | PE-bear Optional Header |
| `0x0108` | Export Directory RVA/Size | `0, 0` | No exports | PE-bear Data Directories |
| `0x0110` | Import Directory RVA/Size | `0x2000`, `0x0080` | Covers the used `.idata` import layout | PE-bear Data Directories |
| `0x0118` | Resource Directory RVA/Size | `0, 0` | No resources | PE-bear Data Directories |
| `0x0120` | Exception Directory RVA/Size | `0, 0` | No unwind data in first prototype | PE-bear Data Directories |
| `0x0128` | Certificate Directory RVA/Size | `0, 0` | No certificate | PE-bear Data Directories |
| `0x0130` | Base Relocation Directory RVA/Size | `0, 0` | No relocations in first prototype | PE-bear Data Directories |
| `0x0138` | Debug Directory RVA/Size | `0, 0` | No debug directory | PE-bear Data Directories |
| `0x0140` | Architecture Directory RVA/Size | `0, 0` | Reserved | PE-bear Data Directories |
| `0x0148` | Global Ptr Directory RVA/Size | `0, 0` | Not used | PE-bear Data Directories |
| `0x0150` | TLS Directory RVA/Size | `0, 0` | No TLS | PE-bear Data Directories |
| `0x0158` | Load Config Directory RVA/Size | `0, 0` | No load config | PE-bear Data Directories |
| `0x0160` | Bound Import Directory RVA/Size | `0, 0` | No bound imports | PE-bear Data Directories |
| `0x0168` | IAT Directory RVA/Size | `0x2050`, `0x0010` | Identifies the import address table | PE-bear Data Directories |
| `0x0170` | Delay Import Directory RVA/Size | `0, 0` | No delay imports | PE-bear Data Directories |
| `0x0178` | CLR Runtime Header RVA/Size | `0, 0` | Native executable, no CLR | PE-bear Data Directories |
| `0x0180` | Reserved Directory RVA/Size | `0, 0` | Reserved | PE-bear Data Directories |

### Section Table

| Offset | Field | Value | Why | Verify |
|---:|---|---|---|---|
| `0x0188` | `.text.Name` | `.text` | Code section | PE-bear sections |
| `0x0190` | `.text.VirtualSize` | `0x000C` | 12 bytes of entry code | PE-bear sections |
| `0x0194` | `.text.VirtualAddress` | `0x1000` | First section RVA | PE-bear sections |
| `0x0198` | `.text.SizeOfRawData` | `0x200` | One file-aligned block | PE-bear sections |
| `0x019C` | `.text.PointerToRawData` | `0x0200` | First raw block | PE-bear sections |
| `0x01A0` | `.text.PointerToRelocations` | `0` | No relocations | PE-bear sections |
| `0x01A4` | `.text.PointerToLinenumbers` | `0` | No line numbers | PE-bear sections |
| `0x01A8` | `.text.NumberOfRelocations` | `0` | No relocations | PE-bear sections |
| `0x01AA` | `.text.NumberOfLinenumbers` | `0` | No line numbers | PE-bear sections |
| `0x01AC` | `.text.Characteristics` | `0x60000020` | Code, execute, read | PE-bear sections |
| `0x01B0` | `.idata.Name` | `.idata` | Import section | PE-bear sections |
| `0x01B8` | `.idata.VirtualSize` | `0x0080` | Actual import data used through DLL name plus padding | PE-bear sections |
| `0x01BC` | `.idata.VirtualAddress` | `0x2000` | Import section RVA | PE-bear sections |
| `0x01C0` | `.idata.SizeOfRawData` | `0x200` | One file-aligned block | PE-bear sections |
| `0x01C4` | `.idata.PointerToRawData` | `0x0400` | Import raw block | PE-bear sections |
| `0x01C8` | `.idata.PointerToRelocations` | `0` | No relocations | PE-bear sections |
| `0x01CC` | `.idata.PointerToLinenumbers` | `0` | No line numbers | PE-bear sections |
| `0x01D0` | `.idata.NumberOfRelocations` | `0` | No relocations | PE-bear sections |
| `0x01D2` | `.idata.NumberOfLinenumbers` | `0` | No line numbers | PE-bear sections |
| `0x01D4` | `.idata.Characteristics` | `0xC0000040` | Initialized data, read, write | PE-bear sections |

## Next Work

Milestone 1 passed with `arqen_m1_exitprocess_v3_fixed_text_flags.exe`.

Milestone 2 passed with `arqen_m2_messagebox_v2_fixed_messagebox_call.exe`.

Milestone 4A passed with `arqen_generator_m4a.exe`.

Next, prepare Milestone 4B: template + patch.

## Milestone 4A Summary

Passing generator:

- `Experiments/M4A_StaticExeWriter/arqen_generator_m4a.exe`

Generated output:

- `Experiments/M4A_StaticExeWriter/output/generated_hello.exe`

Result:

```text
generator exit 0
generated file size 2048
generated file matches M2 bytes
generated file exits 0
```

M4A layout:

- `M4A_LAYOUT.md`

## Milestone 2 Layout Summary

Detailed byte checklist:

- `M2_BYTE_CHECKLIST.md`

Passing executable:

- `Experiments/M2_MessageBoxW/arqen_m2_messagebox_v2_fixed_messagebox_call.exe`

Result:

```text
MessageBoxW(NULL, L"Hello from Arqen", L"Arqen Byte Zero", 0)
ExitProcess(0)
```

Observed PowerShell exit code:

```text
0
```

### M2 Global Layout

| File Offset | RVA | Size | Area | Notes |
|---:|---:|---:|---|---|
| `0x0000` | n/a | `0x0200` | Headers | DOS + PE + 3 section headers |
| `0x0200` | `0x1000` | `0x0200` | `.text` | Entry code |
| `0x0400` | `0x2000` | `0x0200` | `.rdata` | UTF-16 message and caption |
| `0x0600` | `0x3000` | `0x0200` | `.idata` | Imports for kernel32/user32 |

### M2 Section Characteristics

| Section | Offset | Value | Bytes | Meaning |
|---|---:|---:|---|---|
| `.text` | `0x01AC` | `0x60000020` | `20 00 00 60` | code, execute, read |
| `.rdata` | `0x01D4` | `0x40000040` | `40 00 00 40` | initialized data, read |
| `.idata` | `0x01FC` | `0xC0000040` | `40 00 00 C0` | initialized data, read, write |

### M2 Key RVAs

| Item | RVA | File Offset |
|---|---:|---:|
| Entry point | `0x1000` | `0x0200` |
| UTF-16 message | `0x2000` | `0x0400` |
| UTF-16 caption | `0x2040` | `0x0440` |
| Import descriptor array | `0x3000` | `0x0600` |
| Kernel32 ILT | `0x3040` | `0x0640` |
| User32 ILT | `0x3050` | `0x0650` |
| Kernel32 IAT / `ExitProcess` slot | `0x3060` | `0x0660` |
| User32 IAT / `MessageBoxW` slot | `0x3070` | `0x0670` |
| `ExitProcess` hint/name | `0x3090` | `0x0690` |
| `MessageBoxW` hint/name | `0x30A0` | `0x06A0` |
| `kernel32.dll` name | `0x30C0` | `0x06C0` |
| `user32.dll` name | `0x30D0` | `0x06D0` |

### M2 Entry Bytes

| File Offset | RVA | Bytes | Meaning |
|---:|---:|---|---|
| `0x0200` | `0x1000` | `48 83 EC 28` | Reserve stack/shadow space |
| `0x0204` | `0x1004` | `31 C9` | `hWnd = NULL` |
| `0x0206` | `0x1006` | `48 8D 15 F3 0F 00 00` | `RDX = &message` |
| `0x020D` | `0x100D` | `4C 8D 05 2C 10 00 00` | `R8 = &caption` |
| `0x0214` | `0x1014` | `45 31 C9` | `uType = 0` |
| `0x0217` | `0x1017` | `FF 15 53 20 00 00` | Call `MessageBoxW` through IAT |
| `0x021D` | `0x101D` | `31 C9` | exit code `0` |
| `0x021F` | `0x101F` | `FF 15 3B 20 00 00` | Call `ExitProcess` through IAT |

### M2 Debug Notes

First runtime attempt failed with:

```text
0xC0000005
```

Cause:

- The `MessageBoxW` call displacement was `0x2073`, targeting RVA `0x3090`.
- RVA `0x3090` is the `ExitProcess` hint/name entry, not an IAT slot.

Fix:

```text
0x0219: 73 -> 53
```

Correct displacement:

```text
0x3070 - 0x101D = 0x2053
```

Correct call bytes:

```text
FF 15 53 20 00 00
```

## `.text` Entry Code for Milestone 1

Goal:

- Call `ExitProcess(0)`.
- Use Windows x64 calling convention.
- Call through the IAT slot at RVA `0x2050`.

Planning decision:

- `.text` raw file offset: `0x0200`
- `.text` RVA: `0x1000`
- Entry point: RVA `0x1000`
- IAT slot for `ExitProcess`: RVA `0x2050`

### Entry Code Bytes

| File Offset | RVA | Bytes | Meaning |
|---:|---:|---|---|
| `0x0200` | `0x1000` | `48 83 EC 28` | Reserve 40 bytes: 32 bytes shadow space plus stack alignment |
| `0x0204` | `0x1004` | `31 C9` | Set first argument register to zero: exit code `0` |
| `0x0206` | `0x1006` | `FF 15 44 10 00 00` | Call the function pointer stored at IAT RVA `0x2050` |
| `0x020C` | `0x100C` | padding zeros | Not expected to execute because `ExitProcess` does not return |

Full used `.text` bytes:

```text
48 83 EC 28 31 C9 FF 15 44 10 00 00
```

### RIP-Relative Call Calculation

The call instruction starts at RVA `0x1006`.

The instruction is 6 bytes long, so the next instruction address is:

```text
0x1006 + 0x0006 = 0x100C
```

The target memory slot is the IAT entry:

```text
0x2050
```

Displacement:

```text
0x2050 - 0x100C = 0x1044
```

Little-endian `disp32`:

```text
44 10 00 00
```

So the call bytes are:

```text
FF 15 44 10 00 00
```

### Section Size Updates

Now that `.text` has concrete entry bytes:

| Field Offset | Field | Value | Why |
|---:|---|---:|---|
| `0x0190` | `.text.VirtualSize` | `0x000C` | 12 bytes of entry code |
| `0x009C` | `SizeOfCode` | `0x0200` | `.text` raw size is one file-aligned block |

## `.idata` Layout for Milestone 1

Goal:

- Import `kernel32.dll!ExitProcess`.
- Let the Windows loader resolve `ExitProcess` into the Import Address Table.
- Let `.text` call through that IAT slot.

Planning decision:

- `.idata` raw file offset: `0x0400`
- `.idata` RVA: `0x2000`
- Import descriptor starts at RVA `0x2000`
- Import Lookup Table starts at RVA `0x2040`
- Import Address Table starts at RVA `0x2050`
- Hint/name entry starts at RVA `0x2060`
- DLL name starts at RVA `0x2070`

### `.idata` Offset Map

| File Offset | RVA | Size | Item | Value / Notes |
|---:|---:|---:|---|---|
| `0x0400` | `0x2000` | `0x0014` | Import descriptor for `kernel32.dll` | One `IMAGE_IMPORT_DESCRIPTOR` |
| `0x0414` | `0x2014` | `0x0014` | Null import descriptor | Terminates descriptor array |
| `0x0428` | `0x2028` | `0x0018` | Padding | Keeps ILT at `0x2040` |
| `0x0440` | `0x2040` | `0x0008` | ILT entry 0 | RVA of hint/name: `0x2060` |
| `0x0448` | `0x2048` | `0x0008` | ILT null entry | Terminates ILT |
| `0x0450` | `0x2050` | `0x0008` | IAT entry 0 | Initially RVA of hint/name: `0x2060`; loader overwrites with function address |
| `0x0458` | `0x2058` | `0x0008` | IAT null entry | Terminates IAT |
| `0x0460` | `0x2060` | `0x000E` | Hint/name entry | Hint `0`, ASCII `ExitProcess`, null |
| `0x046E` | `0x206E` | `0x0002` | Padding | Align DLL name to `0x2070` |
| `0x0470` | `0x2070` | `0x000D` | DLL name | ASCII `kernel32.dll`, null |
| `0x047D` | `0x207D` | `0x0183` | Padding | Rest of raw `.idata` block |

### Import Descriptor Fields

Import descriptor at file offset `0x0400`, RVA `0x2000`.

| File Offset | RVA | Field | Value | Why | Verify |
|---:|---:|---|---:|---|---|
| `0x0400` | `0x2000` | `OriginalFirstThunk` | `0x2040` | Points to ILT | PE-bear imports |
| `0x0404` | `0x2004` | `TimeDateStamp` | `0` | Not bound | PE-bear imports |
| `0x0408` | `0x2008` | `ForwarderChain` | `0` | No forwarder chain | PE-bear imports |
| `0x040C` | `0x200C` | `Name` | `0x2070` | Points to `kernel32.dll` | PE-bear imports |
| `0x0410` | `0x2010` | `FirstThunk` | `0x2050` | Points to IAT | PE-bear imports |

Null descriptor at file offset `0x0414`, RVA `0x2014`:

- 20 zero bytes.

### ILT and IAT Fields

PE32+ thunk entries are 8 bytes each.

| File Offset | RVA | Field | Value | Why | Verify |
|---:|---:|---|---:|---|---|
| `0x0440` | `0x2040` | ILT thunk 0 | `0x2060` | Import by name, points to hint/name entry | PE-bear imports |
| `0x0448` | `0x2048` | ILT null | `0` | Terminates ILT | PE-bear imports |
| `0x0450` | `0x2050` | IAT thunk 0 | `0x2060` | Loader overwrites this with resolved address | PE-bear imports / x64dbg |
| `0x0458` | `0x2058` | IAT null | `0` | Terminates IAT | PE-bear imports |

### Hint/Name Entry

Hint/name entry at file offset `0x0460`, RVA `0x2060`.

Layout:

| Relative Offset | Bytes | Meaning |
|---:|---|---|
| `+0x00` | `00 00` | Hint = 0 |
| `+0x02` | `45 78 69 74 50 72 6F 63 65 73 73` | ASCII `ExitProcess` |
| `+0x0D` | `00` | Null terminator |

### DLL Name

DLL name at file offset `0x0470`, RVA `0x2070`.

Bytes:

```text
6B 65 72 6E 65 6C 33 32 2E 64 6C 6C 00
```

Meaning:

```text
kernel32.dll\0
```

### Data Directory Values for Imports

These fill fields already listed in the PE32+ optional header:

| Optional Header Offset | Field | Value | Why |
|---:|---|---:|---|
| `0x0110` | Import Directory RVA | `0x2000` | Import descriptor array starts at `.idata` |
| `0x0114` | Import Directory Size | `0x0080` | Covers descriptor, ILT, IAT, hint/name, and DLL name |
| `0x0168` | IAT Directory RVA | `0x2050` | IAT starts here |
| `0x016C` | IAT Directory Size | `0x0010` | One 8-byte thunk plus null thunk |

### Section Size Updates

Now that `.idata` has a concrete layout:

| Field Offset | Field | Value | Why |
|---:|---|---:|---|
| `0x01B8` | `.idata.VirtualSize` | `0x0080` | Import data used through DLL name plus padding |
