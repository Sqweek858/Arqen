# M4A Layout

Status: `PASSED`

Goal:

```text
arqen_generator_m4a.exe -> output/generated_hello.exe
```

The generator embeds the passing M2 executable and writes its bytes with `CreateFileW` + `WriteFile`.

## Global Layout

| Section | RVA | Raw | Raw Size | Use |
|---|---:|---:|---:|---|
| headers | n/a | `0x0000` | `0x0400` | PE headers, 4 section headers |
| `.text` | `0x1000` | `0x0400` | `0x0200` | generator code |
| `.rdata` | `0x2000` | `0x0600` | `0x0A00` | output path + embedded M2 exe |
| `.data` | `0x3000` | `0x1000` | `0x0200` | `fileHandle`, `bytesWritten` |
| `.idata` | `0x4000` | `0x1200` | `0x0200` | imports |

File size: `0x1400`

SizeOfImage: `0x5000`

## Key RVAs

| Item | RVA | Raw |
|---|---:|---:|
| entry point | `0x1000` | `0x0400` |
| output path UTF-16 | `0x2000` | `0x0600` |
| embedded M2 exe bytes | `0x2200` | `0x0800` |
| fileHandle | `0x3000` | `0x1000` |
| bytesWritten | `0x3008` | `0x1008` |
| import descriptor | `0x4000` | `0x1200` |
| ILT | `0x4040` | `0x1240` |
| IAT | `0x4080` | `0x1280` |
| `CreateFileW` hint/name | `0x40C0` | `0x12C0` |
| `WriteFile` hint/name | `0x40D0` | `0x12D0` |
| `CloseHandle` hint/name | `0x40E0` | `0x12E0` |
| `ExitProcess` hint/name | `0x40F0` | `0x12F0` |
| `kernel32.dll` name | `0x4120` | `0x1320` |

## IAT Slots

| Function | RVA |
|---|---:|
| `CreateFileW` | `0x4080` |
| `WriteFile` | `0x4088` |
| `CloseHandle` | `0x4090` |
| `ExitProcess` | `0x4098` |

## Output Path

For M4A, the output directory is created before running the generator.

Path embedded as UTF-16:

```text
output\generated_hello.exe
```

## Result

Passing generator:

```text
Experiments/M4A_StaticExeWriter/arqen_generator_m4a.exe
```

Generated output:

```text
Experiments/M4A_StaticExeWriter/output/generated_hello.exe
```

Verification:

```text
GEN_EXIT: 0
OUT_SIZE: 2048
MATCHES_M2: True
OUT_EXIT: 0
```
