# Windows x64 ABI Notes

## Register Arguments

Windows x64 passes the first four integer/pointer arguments in:

| Argument | Register |
|---:|---|
| 1 | `RCX` |
| 2 | `RDX` |
| 3 | `R8` |
| 4 | `R9` |

Additional arguments go on the stack.

## Shadow Space

Before calling a function, the caller reserves 32 bytes of shadow space on the stack.

This matters for calls into Windows APIs.

## Stack Alignment

The stack must be aligned correctly at call boundaries.

For our first API calls, the entry code must handle:

- argument registers
- 32 bytes of shadow space
- correct stack alignment

## ExitProcess

Target call:

```text
ExitProcess(0)
```

Argument mapping:

| Function Argument | Value | Register |
|---|---:|---|
| `uExitCode` | `0` | `RCX` |

## MessageBoxW

Target call:

```text
MessageBoxW(hwnd, text, caption, type)
```

Argument mapping:

| Function Argument | Value | Register |
|---|---|---|
| `hWnd` | `0` | `RCX` |
| `lpText` | pointer to UTF-16 text | `RDX` |
| `lpCaption` | pointer to UTF-16 title | `R8` |
| `uType` | `0` | `R9` |

## Current Status

Milestone 1 entry code has been planned as raw bytes, but not emitted as an executable yet.

The planned entry code reserves 40 bytes before calling `ExitProcess`:

- 32 bytes for shadow space
- 8 extra bytes to preserve the usual Windows x64 call alignment pattern at process entry

Because `ExitProcess` does not return, no stack cleanup code is needed after the call.

