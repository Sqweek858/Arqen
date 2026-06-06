# Milestone 1 Byte Checklist

Target:

- Windows x64
- PE32+
- Imports `kernel32.dll!ExitProcess`
- Entry point calls `ExitProcess(0)`
- Total file size: `0x0600` bytes

This checklist describes the exact bytes for the first Milestone 1 executable.

All unspecified bytes are `00`.

## File Ranges

| File Range | Size | Area |
|---:|---:|---|
| `0x0000..0x01FF` | `0x0200` | Headers |
| `0x0200..0x03FF` | `0x0200` | `.text` raw data |
| `0x0400..0x05FF` | `0x0200` | `.idata` raw data |

## DOS Header

| Offset | Bytes | Meaning |
|---:|---|---|
| `0x0000` | `4D 5A` | `MZ` |
| `0x003C` | `80 00 00 00` | `e_lfanew = 0x80` |

Everything else from `0x0002..0x007F` is `00`.

## NT Headers

### PE Signature

| Offset | Bytes | Meaning |
|---:|---|---|
| `0x0080` | `50 45 00 00` | `PE\0\0` |

### COFF Header

| Offset | Bytes | Field |
|---:|---|---|
| `0x0084` | `64 86` | `Machine = 0x8664`, AMD64 |
| `0x0086` | `02 00` | `NumberOfSections = 2` |
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
| `0x00A0` | `00 02 00 00` | `SizeOfInitializedData = 0x200` |
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
| `0x00D0` | `00 30 00 00` | `SizeOfImage = 0x3000` |
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

Each directory is `RVA, Size`, both 32-bit little-endian.

| Offset | Bytes | Directory |
|---:|---|---|
| `0x0108` | `00 00 00 00 00 00 00 00` | Export: none |
| `0x0110` | `00 20 00 00 80 00 00 00` | Import: RVA `0x2000`, size `0x80` |
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
| `0x0168` | `50 20 00 00 10 00 00 00` | IAT: RVA `0x2050`, size `0x10` |
| `0x0170` | `00 00 00 00 00 00 00 00` | Delay Import: none |
| `0x0178` | `00 00 00 00 00 00 00 00` | CLR Runtime: none |
| `0x0180` | `00 00 00 00 00 00 00 00` | Reserved |

## Section Table

### `.text`

| Offset | Bytes | Field |
|---:|---|---|
| `0x0188` | `2E 74 65 78 74 00 00 00` | Name `.text` |
| `0x0190` | `0C 00 00 00` | `VirtualSize = 0x0C` |
| `0x0194` | `00 10 00 00` | `VirtualAddress = 0x1000` |
| `0x0198` | `00 02 00 00` | `SizeOfRawData = 0x200` |
| `0x019C` | `00 02 00 00` | `PointerToRawData = 0x200` |
| `0x01A0` | `00 00 00 00` | `PointerToRelocations = 0` |
| `0x01A4` | `00 00 00 00` | `PointerToLinenumbers = 0` |
| `0x01A8` | `00 00` | `NumberOfRelocations = 0` |
| `0x01AA` | `00 00` | `NumberOfLinenumbers = 0` |
| `0x01AC` | `20 00 00 60` | `Characteristics = 0x60000020` |

### `.idata`

| Offset | Bytes | Field |
|---:|---|---|
| `0x01B0` | `2E 69 64 61 74 61 00 00` | Name `.idata` |
| `0x01B8` | `80 00 00 00` | `VirtualSize = 0x80` |
| `0x01BC` | `00 20 00 00` | `VirtualAddress = 0x2000` |
| `0x01C0` | `00 02 00 00` | `SizeOfRawData = 0x200` |
| `0x01C4` | `00 04 00 00` | `PointerToRawData = 0x400` |
| `0x01C8` | `00 00 00 00` | `PointerToRelocations = 0` |
| `0x01CC` | `00 00 00 00` | `PointerToLinenumbers = 0` |
| `0x01D0` | `00 00` | `NumberOfRelocations = 0` |
| `0x01D2` | `00 00` | `NumberOfLinenumbers = 0` |
| `0x01D4` | `40 00 00 C0` | `Characteristics = 0xC0000040` |

Everything from `0x01D8..0x01FF` is `00`.

## `.text` Raw Data

| Offset | Bytes | Meaning |
|---:|---|---|
| `0x0200` | `48 83 EC 28` | Reserve stack space |
| `0x0204` | `31 C9` | `RCX = 0` for `ExitProcess(0)` |
| `0x0206` | `FF 15 44 10 00 00` | Call through IAT slot at RVA `0x2050` |

Everything from `0x020C..0x03FF` is `00`.

## `.idata` Raw Data

### Import Descriptor

| Offset | Bytes | Field |
|---:|---|---|
| `0x0400` | `40 20 00 00` | `OriginalFirstThunk = 0x2040` |
| `0x0404` | `00 00 00 00` | `TimeDateStamp = 0` |
| `0x0408` | `00 00 00 00` | `ForwarderChain = 0` |
| `0x040C` | `70 20 00 00` | `Name = 0x2070` |
| `0x0410` | `50 20 00 00` | `FirstThunk = 0x2050` |

Everything from `0x0414..0x043F` is `00`.

### Import Lookup Table

| Offset | Bytes | Meaning |
|---:|---|---|
| `0x0440` | `60 20 00 00 00 00 00 00` | Thunk points to hint/name RVA `0x2060` |
| `0x0448` | `00 00 00 00 00 00 00 00` | Null thunk |

### Import Address Table

| Offset | Bytes | Meaning |
|---:|---|---|
| `0x0450` | `60 20 00 00 00 00 00 00` | Loader overwrites this with `ExitProcess` address |
| `0x0458` | `00 00 00 00 00 00 00 00` | Null thunk |

### Hint/Name Entry

| Offset | Bytes | Meaning |
|---:|---|---|
| `0x0460` | `00 00` | Hint = 0 |
| `0x0462` | `45 78 69 74 50 72 6F 63 65 73 73 00` | ASCII `ExitProcess\0` |

Everything from `0x046E..0x046F` is `00`.

### DLL Name

| Offset | Bytes | Meaning |
|---:|---|---|
| `0x0470` | `6B 65 72 6E 65 6C 33 32 2E 64 6C 6C 00` | ASCII `kernel32.dll\0` |

Everything from `0x047D..0x05FF` is `00`.

## Verification Checklist

After creating the file:

1. Open in PE-bear.
2. Confirm PE32+.
3. Confirm Machine is AMD64.
4. Confirm sections:
   - `.text` RVA `0x1000`, raw `0x200`
   - `.idata` RVA `0x2000`, raw `0x400`
5. Confirm import:
   - `kernel32.dll`
   - `ExitProcess`
6. Run from terminal and check exit code.
7. Open in x64dbg and confirm entry point at image base plus `0x1000`.
