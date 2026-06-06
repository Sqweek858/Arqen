# PE Notes

## Core Idea

PE files have two coordinate systems:

- File offset: where bytes live on disk.
- RVA: where bytes appear relative to the image base after Windows maps the executable.

These are related by section mapping, but they are not the same thing.

## Minimal PE Areas

A Windows x64 executable needs:

1. DOS header
2. PE signature
3. COFF file header
4. PE32+ optional header
5. Data directories
6. Section table
7. Section raw data

For `ExitProcess(0)`, we also need:

8. Import table
9. Import lookup table / thunk data
10. Import address table
11. Hint/name entry for `ExitProcess`
12. DLL name `kernel32.dll`

## Headers

### DOS Header

Starts at file offset `0x0000`.

Important fields:

- `e_magic`: must be `MZ`
- `e_lfanew`: file offset to NT headers

### NT Headers

Start at the file offset stored in `e_lfanew`.

Layout:

1. PE signature: `PE\0\0`
2. COFF file header
3. Optional header
4. Section table

### COFF File Header

Important fields:

- `Machine = 0x8664` for AMD64
- `NumberOfSections`
- `SizeOfOptionalHeader`
- `Characteristics`

### PE32+ Optional Header

Important fields:

- `Magic = 0x20B`
- `AddressOfEntryPoint`
- `ImageBase`
- `SectionAlignment`
- `FileAlignment`
- `SizeOfImage`
- `SizeOfHeaders`
- `Subsystem`
- Data directories

## Sections

Initial sections:

- `.text`: executable code
- `.idata`: import data

Common section alignment choices:

- `SectionAlignment = 0x1000`
- `FileAlignment = 0x200`

## Import Table

For `ExitProcess`, the import data must describe:

- imported DLL: `kernel32.dll`
- imported function: `ExitProcess`
- thunk resolved by the Windows loader

The code does not call `kernel32.dll` by name. It calls through an address slot filled by the loader.

## First Unknowns To Resolve

- exact optional header field values
- exact `.text` code bytes
- exact `.idata` layout
- console vs GUI subsystem for Milestone 1

## Current Layout Decisions

For the first layout pass:

- `e_lfanew = 0x80`
- NT headers start at file offset `0x80`
- COFF header starts at `0x84`
- PE32+ optional header starts at `0x98`
- optional header size is `0xF0`
- section table starts at `0x188`
- `.text` section header starts at `0x188`
- `.idata` section header starts at `0x1B0`
- `SizeOfHeaders = 0x200`
- `.text` raw data starts at file offset `0x200`, RVA `0x1000`
- `.idata` raw data starts at file offset `0x400`, RVA `0x2000`

These are planning decisions, not emitted bytes yet.

## Milestone 1 Import Layout

For `kernel32.dll!ExitProcess`, `.idata` contains:

1. Import descriptor for `kernel32.dll`
2. Null import descriptor
3. Import Lookup Table
4. Import Address Table
5. Hint/name entry for `ExitProcess`
6. ASCII DLL name `kernel32.dll`

Important RVAs:

- Import descriptor: `0x2000`
- ILT: `0x2040`
- IAT: `0x2050`
- Hint/name: `0x2060`
- DLL name: `0x2070`

The executable code will call through the IAT slot at RVA `0x2050`.

Before load, the IAT entry contains `0x2060`, pointing to the hint/name entry.

After load, Windows overwrites the IAT entry with the real address of `ExitProcess`.

## Milestone 1 Entry Code

The entry point is planned at:

- file offset `0x0200`
- RVA `0x1000`

Used bytes:

```text
48 83 EC 28 31 C9 FF 15 44 10 00 00
```

Meaning:

1. Reserve stack space required for a Windows x64 API call.
2. Put `0` in the first argument register for `ExitProcess(0)`.
3. Call through the IAT slot at RVA `0x2050`.

The RIP-relative call displacement is `0x1044`, encoded little-endian as:

```text
44 10 00 00
```

