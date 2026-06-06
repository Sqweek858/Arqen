# M4A WinAPI Call Notes

Purpose:

- Define the exact Windows x64 call setup needed by the M4A static EXE writer.
- Avoid guessing when writing entry bytes.

## APIs

M4A imports from `kernel32.dll`:

- `CreateFileW`
- `WriteFile`
- `CloseHandle`
- `ExitProcess`

## Windows x64 Recap

First four integer/pointer arguments:

| Argument | Register |
|---:|---|
| 1 | `RCX` |
| 2 | `RDX` |
| 3 | `R8` |
| 4 | `R9` |

Arguments 5+ go on the stack.

Before a call:

- reserve 32 bytes shadow space
- keep stack alignment correct

## Strategy For M4A

Use one stack allocation at entry large enough for:

- 32 bytes shadow space
- stack arguments for `CreateFileW`
- stack argument for `WriteFile`
- local scratch if needed

This avoids repeated stack adjustment between calls.

Proposed first allocation:

```text
sub rsp, 0x58
```

Reason:

- `0x20` shadow space
- enough room for 3 stack arguments for `CreateFileW`
- enough room for 1 stack argument for `WriteFile`
- maintains call alignment from process entry pattern

This value must be verified in x64dbg.

## CreateFileW

Signature:

```text
CreateFileW(
    LPCWSTR lpFileName,
    DWORD   dwDesiredAccess,
    DWORD   dwShareMode,
    LPSECURITY_ATTRIBUTES lpSecurityAttributes,
    DWORD   dwCreationDisposition,
    DWORD   dwFlagsAndAttributes,
    HANDLE  hTemplateFile
)
```

M4A target:

```text
CreateFileW(
    L"output\\generated_hello.exe",
    0x40000000,
    0,
    NULL,
    2,
    0x80,
    NULL
)
```

Register arguments:

| Argument | Value | Location |
|---:|---|---|
| 1 | output path pointer | `RCX` |
| 2 | `GENERIC_WRITE = 0x40000000` | `RDX` |
| 3 | `0` | `R8` |
| 4 | `NULL` | `R9` |

Stack arguments:

| Argument | Value |
|---:|---|
| 5 | `CREATE_ALWAYS = 2` |
| 6 | `FILE_ATTRIBUTE_NORMAL = 0x80` |
| 7 | `NULL` |

With a fixed stack frame, place stack args at:

```text
[rsp + 0x20] = 2
[rsp + 0x28] = 0x80
[rsp + 0x30] = 0
```

Then call through IAT:

```text
CreateFileW IAT slot
```

Return:

```text
RAX = file handle
```

Store `RAX` in writable data:

```text
fileHandle
```

Failure value:

```text
INVALID_HANDLE_VALUE = 0xFFFFFFFFFFFFFFFF
```

M4A minimal may ignore failure at first, but a cleaner version should branch to `ExitProcess(1)`.

## WriteFile

Signature:

```text
WriteFile(
    HANDLE       hFile,
    LPCVOID      lpBuffer,
    DWORD        nNumberOfBytesToWrite,
    LPDWORD      lpNumberOfBytesWritten,
    LPOVERLAPPED lpOverlapped
)
```

M4A target:

```text
WriteFile(
    fileHandle,
    embedded_m2_exe_bytes,
    2048,
    &bytesWritten,
    NULL
)
```

Register arguments:

| Argument | Value | Location |
|---:|---|---|
| 1 | file handle | `RCX` |
| 2 | embedded M2 bytes pointer | `RDX` |
| 3 | `2048` | `R8` |
| 4 | `&bytesWritten` | `R9` |

Stack arguments:

| Argument | Value |
|---:|---|
| 5 | `NULL` |

Place stack arg:

```text
[rsp + 0x20] = 0
```

Then call through IAT:

```text
WriteFile IAT slot
```

Return:

```text
RAX != 0 means success
RAX = 0 means failure
```

M4A minimal may ignore this at first.

## CloseHandle

Signature:

```text
CloseHandle(HANDLE hObject)
```

Register arguments:

| Argument | Value | Location |
|---:|---|---|
| 1 | file handle | `RCX` |

Then call through IAT:

```text
CloseHandle IAT slot
```

## ExitProcess

Signature:

```text
ExitProcess(UINT uExitCode)
```

Register arguments:

| Argument | Value | Location |
|---:|---|---|
| 1 | `0` or `1` | `RCX` |

Then call through IAT:

```text
ExitProcess IAT slot
```

## M4A Minimal Success Path

Conceptual sequence:

```text
sub rsp, 0x58

CreateFileW(...)
store RAX -> fileHandle

WriteFile(fileHandle, embeddedBytes, 2048, &bytesWritten, NULL)

CloseHandle(fileHandle)

ExitProcess(0)
```

## Next Byte Decisions

Need exact RVAs for:

- `outputPath`
- `embeddedM2ExeBytes`
- `fileHandle`
- `bytesWritten`
- IAT slots:
  - `CreateFileW`
  - `WriteFile`
  - `CloseHandle`
  - `ExitProcess`

Need exact code bytes for:

- loading pointers via RIP-relative `lea`
- writing stack args
- storing `RAX`
- loading stored handle
- calling through RIP-relative IAT slots

