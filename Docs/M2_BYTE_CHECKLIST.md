# Milestone 2 Byte Checklist

Target:

- Windows x64
- PE32+
- Imports:
  - `kernel32.dll!ExitProcess`
  - `user32.dll!MessageBoxW`
- Shows a UTF-16 message box.
- Exits through `ExitProcess(0)`.
- Total file size: `0x0800` bytes.

All unspecified bytes are `00`.

## File Ranges

| File Range | Size | Area |
|---:|---:|---|
| `0x0000..0x01FF` | `0x0200` | Headers |
| `0x0200..0x03FF` | `0x0200` | `.text` raw data |
| `0x0400..0x05FF` | `0x0200` | `.rdata` raw data |
| `0x0600..0x07FF` | `0x0200` | `.idata` raw data |

## Layout Constants

| Name | Value |
|---|---:|
| `ImageBase` | `0x140000000` |
| `SectionAlignment` | `0x1000` |
| `FileAlignment` | `0x200` |
| `SizeOfHeaders` | `0x200` |
| `SizeOfImage` | `0x4000` |
| `.text RVA / raw` | `0x1000 / 0x0200` |
| `.rdata RVA / raw` | `0x2000 / 0x0400` |
| `.idata RVA / raw` | `0x3000 / 0x0600` |

## DOS Header

| Offset | Bytes | Meaning |
|---:|---|---|
| `0x0000` | `4D 5A` | `MZ` |
| `0x003C` | `80 00 00 00` | `e_lfanew = 0x80` |

## NT Headers

| Offset | Bytes | Meaning |
|---:|---|---|
| `0x0080` | `50 45 00 00` | `PE\0\0` |

## COFF Header

| Offset | Bytes | Field |
|---:|---|---|
| `0x0084` | `64 86` | `Machine = 0x8664`, AMD64 |
| `0x0086` | `03 00` | `NumberOfSections = 3` |
| `0x0088` | `00 00 00 00` | `TimeDateStamp = 0` |
| `0x008C` | `00 00 00 00` | `PointerToSymbolTable = 0` |
| `0x0090` | `00 00 00 00` | `NumberOfSymbols = 0` |
| `0x0094` | `F0 00` | `SizeOfOptionalHeader = 0xF0` |
| `0x0096` | `22 00` | `Characteristics = 0x0022` |

## Optional Header PE32+

| Offset | Bytes | Field |
|---:|---|---|
| `0x0098` | `0B 02` | `Magic = 0x20B` |
| `0x009A` | `00` | `MajorLinkerVersion = 0` |
| `0x009B` | `00` | `MinorLinkerVersion = 0` |
| `0x009C` | `00 02 00 00` | `SizeOfCode = 0x200` |
| `0x00A0` | `00 04 00 00` | `SizeOfInitializedData = 0x400` |
| `0x00A4` | `00 00 00 00` | `SizeOfUninitializedData = 0` |
| `0x00A8` | `00 10 00 00` | `AddressOfEntryPoint = 0x1000` |
| `0x00AC` | `00 10 00 00` | `BaseOfCode = 0x1000` |
| `0x00B0` | `00 00 00 40 01 00 00 00` | `ImageBase = 0x140000000` |
| `0x00B8` | `00 10 00 00` | `SectionAlignment = 0x1000` |
| `0x00BC` | `00 02 00 00` | `FileAlignment = 0x200` |
| `0x00C0` | `06 00` | `MajorOperatingSystemVersion = 6` |
| `0x00C2` | `00 00` | `MinorOperatingSystemVersion = 0` |
| `0x00C4` | `00 00` | `MajorImageVersion = 0` |
| `0x00C6` | `00 00` | `MinorImageVersion = 0` |
| `0x00C8` | `06 00` | `MajorSubsystemVersion = 6` |
| `0x00CA` | `00 00` | `MinorSubsystemVersion = 0` |
| `0x00CC` | `00 00 00 00` | `Win32VersionValue = 0` |
| `0x00D0` | `00 40 00 00` | `SizeOfImage = 0x4000` |
| `0x00D4` | `00 02 00 00` | `SizeOfHeaders = 0x200` |
| `0x00D8` | `00 00 00 00` | `CheckSum = 0` |
| `0x00DC` | `03 00` | `Subsystem = 3`, Windows CUI |
| `0x00DE` | `00 00` | `DllCharacteristics = 0` |
| `0x00E0` | `00 00 10 00 00 00 00 00` | `SizeOfStackReserve = 0x100000` |
| `0x00E8` | `00 10 00 00 00 00 00 00` | `SizeOfStackCommit = 0x1000` |
| `0x00F0` | `00 00 10 00 00 00 00 00` | `SizeOfHeapReserve = 0x100000` |
| `0x00F8` | `00 10 00 00 00 00 00 00` | `SizeOfHeapCommit = 0x1000` |
| `0x0100` | `00 00 00 00` | `LoaderFlags = 0` |
| `0x0104` | `10 00 00 00` | `NumberOfRvaAndSizes = 16` |

## Data Directories

| Offset | Bytes | Directory |
|---:|---|---|
| `0x0108` | `00 00 00 00 00 00 00 00` | Export: none |
| `0x0110` | `00 30 00 00 E0 00 00 00` | Import: RVA `0x3000`, size `0xE0` |
| `0x0118` | `00 00 00 00 00 00 00 00` | Resource: none |
| `0x0120` | `00 00 00 00 00 00 00 00` | Exception: none |
| `0x0128` | `00 00 00 00 00 00 00 00` | Certificate: none |
| `0x0130` | `00 00 00 00 00 00 00 00` | Base relocation: none |
| `0x0138` | `00 00 00 00 00 00 00 00` | Debug: none |
| `0x0140` | `00 00 00 00 00 00 00 00` | Architecture: none |
| `0x0148` | `00 00 00 00 00 00 00 00` | Global Ptr: none |
| `0x0150` | `00 00 00 00 00 00 00 00` | TLS: none |
| `0x0158` | `00 00 00 00 00 00 00 00` | Load Config: none |
| `0x0160` | `00 00 00 00 00 00 00 00` | Bound Import: none |
| `0x0168` | `60 30 00 00 20 00 00 00` | IAT: RVA `0x3060`, size `0x20` |
| `0x0170` | `00 00 00 00 00 00 00 00` | Delay Import: none |
| `0x0178` | `00 00 00 00 00 00 00 00` | CLR Runtime: none |
| `0x0180` | `00 00 00 00 00 00 00 00` | Reserved |

## Section Table

### `.text`

| Offset | Bytes | Field |
|---:|---|---|
| `0x0188` | `2E 74 65 78 74 00 00 00` | Name `.text` |
| `0x0190` | `25 00 00 00` | `VirtualSize = 0x25` |
| `0x0194` | `00 10 00 00` | `VirtualAddress = 0x1000` |
| `0x0198` | `00 02 00 00` | `SizeOfRawData = 0x200` |
| `0x019C` | `00 02 00 00` | `PointerToRawData = 0x200` |
| `0x01A0` | `00 00 00 00` | `PointerToRelocations = 0` |
| `0x01A4` | `00 00 00 00` | `PointerToLinenumbers = 0` |
| `0x01A8` | `00 00` | `NumberOfRelocations = 0` |
| `0x01AA` | `00 00` | `NumberOfLinenumbers = 0` |
| `0x01AC` | `20 00 00 60` | `Characteristics = 0x60000020` |

### `.rdata`

| Offset | Bytes | Field |
|---:|---|---|
| `0x01B0` | `2E 72 64 61 74 61 00 00` | Name `.rdata` |
| `0x01B8` | `60 00 00 00` | `VirtualSize = 0x60` |
| `0x01BC` | `00 20 00 00` | `VirtualAddress = 0x2000` |
| `0x01C0` | `00 02 00 00` | `SizeOfRawData = 0x200` |
| `0x01C4` | `00 04 00 00` | `PointerToRawData = 0x400` |
| `0x01C8` | `00 00 00 00` | `PointerToRelocations = 0` |
| `0x01CC` | `00 00 00 00` | `PointerToLinenumbers = 0` |
| `0x01D0` | `00 00` | `NumberOfRelocations = 0` |
| `0x01D2` | `00 00` | `NumberOfLinenumbers = 0` |
| `0x01D4` | `40 00 00 40` | `Characteristics = 0x40000040` |

### `.idata`

| Offset | Bytes | Field |
|---:|---|---|
| `0x01D8` | `2E 69 64 61 74 61 00 00` | Name `.idata` |
| `0x01E0` | `E0 00 00 00` | `VirtualSize = 0xE0` |
| `0x01E4` | `00 30 00 00` | `VirtualAddress = 0x3000` |
| `0x01E8` | `00 02 00 00` | `SizeOfRawData = 0x200` |
| `0x01EC` | `00 06 00 00` | `PointerToRawData = 0x600` |
| `0x01F0` | `00 00 00 00` | `PointerToRelocations = 0` |
| `0x01F4` | `00 00 00 00` | `PointerToLinenumbers = 0` |
| `0x01F8` | `00 00` | `NumberOfRelocations = 0` |
| `0x01FA` | `00 00` | `NumberOfLinenumbers = 0` |
| `0x01FC` | `40 00 00 C0` | `Characteristics = 0xC0000040` |

## `.text` Raw Data

Entry point:

- file offset `0x0200`
- RVA `0x1000`

| Offset | Bytes | Meaning |
|---:|---|---|
| `0x0200` | `48 83 EC 28` | Reserve stack/shadow space |
| `0x0204` | `31 C9` | `RCX = 0`, `hWnd = NULL` |
| `0x0206` | `48 8D 15 F3 0F 00 00` | `RDX = &message` at RVA `0x2000` |
| `0x020D` | `4C 8D 05 2C 10 00 00` | `R8 = &caption` at RVA `0x2040` |
| `0x0214` | `45 31 C9` | `R9D = 0`, message box type |
| `0x0217` | `FF 15 53 20 00 00` | Call IAT slot at RVA `0x3070`, `MessageBoxW` |
| `0x021D` | `31 C9` | `RCX = 0`, exit code |
| `0x021F` | `FF 15 3B 20 00 00` | Call IAT slot at RVA `0x3060`, `ExitProcess` |

Everything from `0x0225..0x03FF` is `00`.

### RIP-Relative Calculations

Message text:

```text
target RVA = 0x2000
next RVA after lea = 0x100D
disp32 = 0x2000 - 0x100D = 0x0FF3
bytes = F3 0F 00 00
```

Caption:

```text
target RVA = 0x2040
next RVA after lea = 0x1014
disp32 = 0x2040 - 0x1014 = 0x102C
bytes = 2C 10 00 00
```

MessageBoxW IAT:

```text
target RVA = 0x3070
next RVA after call = 0x101D
disp32 = 0x3070 - 0x101D = 0x2053
bytes = 53 20 00 00
```

ExitProcess IAT:

```text
target RVA = 0x3060
next RVA after call = 0x1025
disp32 = 0x3060 - 0x1025 = 0x203B
bytes = 3B 20 00 00
```

## `.rdata` Raw Data

Message text at file offset `0x0400`, RVA `0x2000`:

```text
48 00 65 00 6C 00 6C 00 6F 00 20 00 66 00 72 00
6F 00 6D 00 20 00 41 00 72 00 71 00 65 00 6E 00
00 00
```

Meaning:

```text
Hello from Arqen
```

Caption at file offset `0x0440`, RVA `0x2040`:

```text
41 00 72 00 71 00 65 00 6E 00 20 00 42 00 79 00
74 00 65 00 20 00 5A 00 65 00 72 00 6F 00 00 00
```

Meaning:

```text
Arqen Byte Zero
```

## `.idata` Raw Data

### Import Descriptors

Kernel32 descriptor at file offset `0x0600`, RVA `0x3000`:

| Offset | Bytes | Field |
|---:|---|---|
| `0x0600` | `40 30 00 00` | `OriginalFirstThunk = 0x3040` |
| `0x0604` | `00 00 00 00` | `TimeDateStamp = 0` |
| `0x0608` | `00 00 00 00` | `ForwarderChain = 0` |
| `0x060C` | `C0 30 00 00` | `Name = 0x30C0` |
| `0x0610` | `60 30 00 00` | `FirstThunk = 0x3060` |

User32 descriptor at file offset `0x0614`, RVA `0x3014`:

| Offset | Bytes | Field |
|---:|---|---|
| `0x0614` | `50 30 00 00` | `OriginalFirstThunk = 0x3050` |
| `0x0618` | `00 00 00 00` | `TimeDateStamp = 0` |
| `0x061C` | `00 00 00 00` | `ForwarderChain = 0` |
| `0x0620` | `D0 30 00 00` | `Name = 0x30D0` |
| `0x0624` | `70 30 00 00` | `FirstThunk = 0x3070` |

Null descriptor:

- `0x0628..0x063B` are `00`.

### ILT

| Offset | Bytes | Meaning |
|---:|---|---|
| `0x0640` | `90 30 00 00 00 00 00 00` | Kernel32 ILT: hint/name RVA `0x3090` |
| `0x0648` | `00 00 00 00 00 00 00 00` | Kernel32 ILT null |
| `0x0650` | `A0 30 00 00 00 00 00 00` | User32 ILT: hint/name RVA `0x30A0` |
| `0x0658` | `00 00 00 00 00 00 00 00` | User32 ILT null |

### IAT

| Offset | Bytes | Meaning |
|---:|---|---|
| `0x0660` | `90 30 00 00 00 00 00 00` | Kernel32 IAT slot for `ExitProcess` |
| `0x0668` | `00 00 00 00 00 00 00 00` | Kernel32 IAT null |
| `0x0670` | `A0 30 00 00 00 00 00 00` | User32 IAT slot for `MessageBoxW` |
| `0x0678` | `00 00 00 00 00 00 00 00` | User32 IAT null |

### Hint/Name Entries

`ExitProcess` at file offset `0x0690`, RVA `0x3090`:

```text
00 00 45 78 69 74 50 72 6F 63 65 73 73 00
```

`MessageBoxW` at file offset `0x06A0`, RVA `0x30A0`:

```text
00 00 4D 65 73 73 61 67 65 42 6F 78 57 00
```

### DLL Names

`kernel32.dll` at file offset `0x06C0`, RVA `0x30C0`:

```text
6B 65 72 6E 65 6C 33 32 2E 64 6C 6C 00
```

`user32.dll` at file offset `0x06D0`, RVA `0x30D0`:

```text
75 73 65 72 33 32 2E 64 6C 6C 00
```

Everything from `0x06DB..0x07FF` is `00`.

## Verification

Static checks:

- PE32+
- AMD64
- 3 sections: `.text`, `.rdata`, `.idata`
- `.text` characteristics `0x60000020`
- `.rdata` characteristics `0x40000040`
- `.idata` characteristics `0xC0000040`
- imports:
  - `kernel32.dll!ExitProcess`
  - `user32.dll!MessageBoxW`

Runtime check:

1. Run the executable.
2. Message box appears with text `Hello from Arqen`.
3. Click OK.
4. PowerShell `$LASTEXITCODE` is `0`.
