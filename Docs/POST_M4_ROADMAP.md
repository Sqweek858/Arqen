# Post-M4 Roadmap

Status: `HISTORICAL ROADMAP - COMPLETED THROUGH M10, WITH M4D PARTIAL`

## M4D: Clear `.arq` Errors

First error system, still simple.

Error cases:

- missing `title`
- missing `message`
- missing `exit`
- string too long for fixed buffer
- missing quotes
- unsupported exit code
- unknown keyword

Initial output:

```text
arqen_error.txt
```

Generator exits non-zero.

Example:

```text
Error A004:
Missing required field: message

Expected:
message "Hello from Arqen"
```

## M5: Minimal CLI

Status: `PASSED`

Goal:

```text
arqc hello_message.arq
```

Output:

```text
hello_message.exe
```

Windows API:

- `GetCommandLineW`

Avoid `CommandLineToArgvW` for now because it requires `shell32.dll`.

## M6: Lexer v1

Status: `PASSED`

Token types:

- identifier
- string literal
- integer literal
- newline
- colon, if used
- keywords: `program`, `title`, `message`, `exit`
- EOF

First accepted shape:

```arq
program Hello
title "Arqen Byte Zero"
message "Hello from Arqen"
exit 0
```

## M7: Minimal AST + Semantic Check

Status: `PASSED`

Internal structure:

```text
Program:
    name
    title
    message
    exit_code
```

Checks:

- program name exists
- title exists
- message exists
- exit exists
- title/message fit buffers
- exit code is supported

## M8: Clean Codegen From AST

Status: `PASSED`

Pipeline:

```text
source .arq
-> lexer
-> parser
-> AST
-> semantic check
-> PE generator
-> .exe
```

At M8, Arqen has a real tiny compiler.

## M9-M10 Completed Follow-up

Status: `PASSED THROUGH M10`

Current completed path:

```text
M9: let variables
M9B: text/int/bool let variables plus clearer let errors
M10: simple message expressions with text concatenation
```

## Later Roadmap

- M10F: foundation hardening
- M10G: single `arqc` driver
- M10R: generic parser/token contract migration
- M11: int + real exit code
- M12: simple `if`
- M13: multiple statements
- M14: basic functions
- M15: create window
