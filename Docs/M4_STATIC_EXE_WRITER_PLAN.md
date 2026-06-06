# M4 Static EXE Writer Plan

## Purpose

M4 is not a complete language compiler.

M4 proves this:

```text
an executable made by us can create another executable made by us
```

This is the first real step from manual bytes toward a compiler.

## M4 Split

### M4A: Static EXE Writer

Goal:

```text
run arqen_generator_m4.exe
-> writes output/generated_hello.exe
-> generated_hello.exe shows "Hello from Arqen"
```

Rules:

- No `.arq` input yet.
- No parser.
- No syntax analysis.
- No template patching yet.
- The generator writes known PE bytes to disk.
- The output executable is behaviorally equivalent to the M2 MessageBoxW executable.

Success means:

- `arqen_generator_m4.exe` runs.
- It writes `output/generated_hello.exe`.
- The generated exe runs.
- It shows the message box.
- After OK, it exits with code `0`.

### M4B: Template + Patch

Goal:

- The generator has a PE template.
- It patches a fixed UTF-16 message string area.
- It writes the final executable.

Example fixed setting:

```text
message = "Hello from Arqen"
```

Still not a parser.

### M4C: Strict `.arq` Reader

Goal:

```text
hello_message.arq
-> generator reads text
-> extracts strict fields
-> writes exe
```

Possible strict source shape:

```arq
program Hello
message title "Arqen Byte Zero"
message text "Hello from Arqen"
exit 0
```

No synonyms, no natural-language interpretation, no flexible grammar.

## Purist Rule

For the pure path, the M4 generator itself is also a PE executable built from bytes.

We do not use:

- C++
- Python
- Rust
- Zig
- textual assembly
- NASM / MASM
- LLVM
- linker-generated executable

This makes M4A harder, but it proves the right thing.

## M4A Required Windows APIs

Imports from `kernel32.dll`:

- `CreateFileW`
- `WriteFile`
- `CloseHandle`
- `ExitProcess`

Optional later:

- `GetLastError`
- `CreateDirectoryW`

For M4A, keep the API list minimal and assume the `output` directory already exists.

If the generator must create the `output` directory itself, add `CreateDirectoryW`.

## M4A Conceptual Flow

```text
CreateFileW(L"output\\generated_hello.exe", GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL)
WriteFile(fileHandle, embedded_m2_exe_bytes, embedded_m2_exe_size, &bytesWritten, NULL)
CloseHandle(fileHandle)
ExitProcess(0)
```

If `CreateFileW` fails:

- minimal M4A can still call `ExitProcess(1)`
- better M4A can call `GetLastError`, but that is optional

## M4A Constants

### CreateFileW

Target:

```text
CreateFileW(
    L"output\\generated_hello.exe",
    GENERIC_WRITE,
    0,
    NULL,
    CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL,
    NULL
)
```

Constants:

| Name | Value |
|---|---:|
| `GENERIC_WRITE` | `0x40000000` |
| `CREATE_ALWAYS` | `2` |
| `FILE_ATTRIBUTE_NORMAL` | `0x80` |
| `INVALID_HANDLE_VALUE` | `-1` / `0xFFFFFFFFFFFFFFFF` |

### WriteFile

Target:

```text
WriteFile(
    fileHandle,
    embedded_m2_exe_bytes,
    2048,
    &bytesWritten,
    NULL
)
```

The M2 passing executable is `2048` bytes.

## Windows x64 Calling Convention Impact

The first four parameters go in:

| Argument | Register |
|---:|---|
| 1 | `RCX` |
| 2 | `RDX` |
| 3 | `R8` |
| 4 | `R9` |

Additional arguments go on the stack.

M4A needs stack arguments:

- `CreateFileW` has 7 arguments.
- `WriteFile` has 5 arguments.

This is the new technical challenge after M2.

M1 and M2 only used up to 4 arguments.

Detailed call notes:

```text
M4A_WINAPI_CALLS.md
```

## Required M4A Data

The generator executable needs:

1. UTF-16 output path:

```text
output\generated_hello.exe
```

2. Embedded output bytes:

```text
the full M2 passing executable bytes
```

3. Writable storage for:

```text
file handle
bytesWritten
```

Because `bytesWritten` must be written by `WriteFile`, M4A needs a writable section or writable data area.

## Proposed M4A Sections

Use:

- `.text`: generator code
- `.rdata`: output path and embedded M2 executable bytes
- `.data`: writable variables such as file handle and bytesWritten
- `.idata`: imports

This is our first PE with four sections.

## Proposed M4A Output

Generator:

```text
Experiments/M4A_StaticExeWriter/arqen_generator_m4a.exe
```

Generated executable:

```text
Experiments/M4A_StaticExeWriter/output/generated_hello.exe
```

For M4A, the `output` directory may be created before running the generator.

## Main New Risks

1. Stack arguments for WinAPI calls with more than 4 parameters.
2. Maintaining stack alignment across multiple calls.
3. Correct writable storage for `bytesWritten`.
4. Correctly embedding a 2048-byte executable inside another PE.
5. Avoiding section/header byte shifts like the M1 `.text` characteristics bug.
6. Windows policy may block unsigned, manually built executables.

## M4A Success Criteria

M4A is passed when:

1. The generator executable is built from documented bytes.
2. Running it creates `output/generated_hello.exe`.
3. `generated_hello.exe` matches the known M2 behavior.
4. Running `generated_hello.exe` shows the message box.
5. After OK, `$LASTEXITCODE` is `0`.

## Next Design Step

Before writing bytes:

1. Define exact M4A section layout.
2. Define exact import table layout for four kernel32 functions.
3. Define exact data layout:
   - output path
   - embedded M2 bytes
   - writable variables
4. Define exact entry code bytes for:
   - `CreateFileW`
   - `WriteFile`
   - `CloseHandle`
   - `ExitProcess`

Exact layout:

- `M4A_LAYOUT.md`
