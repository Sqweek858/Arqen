# M4A Static EXE Writer Experiment Log

## Goal

Build a byte-authored generator executable that writes another byte-authored executable.

Target:

```text
arqen_generator_m4a.exe
-> output/generated_hello.exe
```

The generated executable should behave like the passing M2 MessageBoxW executable.

## Status

```text
PASSED
```

## Current Rule

No parser yet.

No `.arq` input yet.

No external compiler/linker-generated generator.

## Planned Imports

From `kernel32.dll`:

- `CreateFileW`
- `WriteFile`
- `CloseHandle`
- `ExitProcess`

## Main New Challenge

M4A introduces Windows API calls with more than four arguments.

This requires correct stack argument placement in addition to:

- register arguments
- 32-byte shadow space
- stack alignment

## Next Work

M4A passed.

Reference docs:

- `Docs/M4_STATIC_EXE_WRITER_PLAN.md`
- `Docs/M4A_WINAPI_CALLS.md`
- `Docs/M4A_LAYOUT.md`

## Passing Generator

```text
Experiments/M4A_StaticExeWriter/arqen_generator_m4a.exe
```

Observed:

```text
GEN_EXIT: 0
OUT_EXISTS: True
OUT_SIZE: 2048
MATCHES_M2: True
OUT_EXIT: 0
```

Generated output:

```text
Experiments/M4A_StaticExeWriter/output/generated_hello.exe
```

Conclusion:

```text
M4A Static EXE Writer: PASSED
```
