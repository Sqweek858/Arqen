# Arqen Byte Zero Plan

## Purpose

Arqen Byte Zero starts with one proof:

bytes -> valid Windows x64 executable -> runs -> exits cleanly

We are not designing the full language yet. We are first proving that we understand enough of the Windows PE32+ format to build a minimal executable intentionally.

## Initial Target

- Platform: Windows 10/11 x64
- Executable format: PE32+
- Architecture: AMD64
- First milestone behavior: call `ExitProcess(0)`
- Second milestone behavior: show `MessageBoxW`, then call `ExitProcess(0)`

## Constraints

For the purist first phase, do not use:

- C++
- Python
- Rust
- Zig
- textual assembly
- NASM / MASM
- LLVM
- external linker-generated executables
- template PE generators

Allowed:

- hex editor
- PE inspector
- debugger
- dependency/import inspector
- documentation
- calculator
- Codex for planning, explanation, and documentation

## First Session Scope

This first session is documentation and layout only.

We will not write executable bytes yet.

We will:

1. Choose tools.
2. Define the minimal PE layout.
3. Define initial constants.
4. Define the sections.
5. Define the conceptual entry point.
6. Start the offset ledger.

## Initial Tool Choices

Recommended:

- Hex editor: HxD
- PE inspector: PE-bear
- Debugger: x64dbg
- Import checker: Dependencies
- Calculator: Windows Calculator in Programmer mode

Only HxD and PE-bear are needed immediately.

## Initial Constants

These are the first proposed constants for a simple, conventional PE32+ layout:

- `ImageBase = 0x0000000140000000`
- `SectionAlignment = 0x1000`
- `FileAlignment = 0x200`
- First section RVA: `0x1000`
- NT headers file offset: `0x80`
- Size of headers: `0x200`

These values are not final bytes yet. They are planning values.

## First Layout Decision

We will place the NT headers at file offset `0x80`.

This keeps the first file-aligned block simple:

- `0x0000..0x003F`: DOS header
- `0x0040..0x007F`: DOS stub / padding
- `0x0080..0x01D7`: PE signature, COFF header, optional header, section table
- `0x01D8..0x01FF`: padding
- `0x0200`: first raw section starts

## Initial Sections

Milestone 0 / 1 likely needs:

- `.text` for executable code
- `.idata` for imports

Possible later:

- `.rdata` for read-only strings and constants, especially for `MessageBoxW`

For the first clean plan, keep `.text` and `.idata`.

## Conceptual Execution Flow

Milestone 1:

1. Windows loader maps the image.
2. Loader resolves imports.
3. Loader writes the resolved address of `ExitProcess` into the IAT slot at RVA `0x2050`.
4. Control starts at `AddressOfEntryPoint`, currently planned as RVA `0x1000`.
5. Entry code prepares `ExitProcess(0)`.
6. Entry code calls through the imported function pointer in the IAT.
7. Process exits with code `0`.

## Milestone 1 Entry Bytes

Entry point:

- RVA `0x1000`
- file offset `0x0200`

Bytes:

```text
48 83 EC 28 31 C9 FF 15 44 10 00 00
```

These bytes call through the IAT slot at RVA `0x2050`, where the Windows loader will place the real address of `ExitProcess`.

Milestone 1 result:

```text
PASSED
```

Passing file:

```text
Experiments/M1_ExitProcess/arqen_m1_exitprocess_v3_fixed_text_flags.exe
```

Observed exit code:

```text
0
```

## Milestone 3 Result

Milestone 3 defines the first conceptual `.arq` source shape:

```arq
program Hello:
    show message "Hello from Arqen"
    exit 0
```

This maps to the already proven M2 behavior:

```text
MessageBoxW(NULL, L"Hello from Arqen", L"Arqen Byte Zero", 0)
ExitProcess(0)
```

Status:

```text
PASSED
```

Spec:

```text
Specs/Language/M3_MINIMAL_SOURCE_FORMAT.md
```

Sample:

```text
Samples/hello_message.arq
```

## Milestone 4 Direction

M4 is the first generator milestone.

It is split into:

```text
M4A: Static EXE Writer
M4B: Template + Patch
M4C: Strict .arq Reader
```

M4A proves:

```text
an executable made from our bytes can create another executable made from our bytes
```

M4A generator behavior:

```text
arqen_generator_m4a.exe
-> output/generated_hello.exe
```

The generated executable should match the M2 behavior:

```text
MessageBoxW(NULL, L"Hello from Arqen", L"Arqen Byte Zero", 0)
ExitProcess(0)
```

Detailed plan:

```text
Docs/M4_STATIC_EXE_WRITER_PLAN.md
```

## Milestone 2 Plan

Milestone 2 adds visible output:

```text
MessageBoxW(NULL, L"Hello from Arqen", L"Arqen Byte Zero", 0)
ExitProcess(0)
```

Layout change:

- `.text`: entry code
- `.rdata`: UTF-16 message and caption
- `.idata`: imports for `kernel32.dll` and `user32.dll`

The exact planned byte layout is recorded in:

- `M2_BYTE_CHECKLIST.md`

Milestone 2 result:

```text
PASSED
```

Passing file:

```text
Experiments/M2_MessageBoxW/arqen_m2_messagebox_v2_fixed_messagebox_call.exe
```

Observed exit code:

```text
0
```

## Milestone 1 Byte Checklist

The exact planned byte layout is recorded in:

- `M1_BYTE_CHECKLIST.md`

Manual HxD build steps are recorded in:

- `M1_HXD_MANUAL_BUILD.md`

## Milestone 1 Subsystem Decision

Use:

- `Subsystem = 3`
- Meaning: Windows CUI / console subsystem

Reason:

- The first executable has no visible UI.
- Console subsystem is practical for checking exit behavior from a terminal.
- We can switch to GUI subsystem later when `MessageBoxW` becomes the main visible behavior.

## Verification

Milestone 0:

- PE-bear opens the file as PE32+.
- Machine is AMD64.
- Section table is readable.
- Windows does not reject the file as invalid format.

Milestone 1:

- Program starts.
- Program exits without crash.
- Exit code is `0`.
- x64dbg shows execution reaching the entry point.
- Import table contains `kernel32.dll!ExitProcess`.
