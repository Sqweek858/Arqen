# Codegen Contract M10

Status: current M10/M10G contract

## Target

Codegen currently targets:

```text
Windows x64 PE
```

Current output behavior:

```text
MessageBoxW(title, message)
ExitProcess(0)
```

## Inputs

M10 manual codegen consumes the historical AST dump.

M10G driver codegen consumes stable AST fields:

```text
TITLE
MESSAGE
EXIT
SEMANTIC
```

Required:

```text
SEMANTIC|OK
EXIT|0
```

## Template

Current template:

```text
Experiments\M10_SimpleExpressions\template_messagebox_m8.exe
```

Template requirements:

- valid Windows x64 PE
- imports `user32.dll!MessageBoxW`
- imports `kernel32.dll!ExitProcess`
- message buffer at raw offset `0x400`
- title buffer at raw offset `0x440`
- buffers are UTF-16LE
- current buffer size is 64 bytes each

## Safety Rules

- Do not run codegen after parse failure.
- Do not run codegen after semantic failure.
- Do not overwrite final exe until temp output is complete.
- Reject strings that do not fit template buffers.

## Current Limitations

- exit code is only `0`
- output is MessageBox-only
- no runtime string allocation
- no control flow
- no alternate subsystem/window behavior

## Future Work

- structured backend input
- template-independent PE writer
- non-zero exit code support
- runtime expression support
- multiple statements
