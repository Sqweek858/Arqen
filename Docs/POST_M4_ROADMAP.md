# Post-M4 Roadmap

Status: `PLANNED`

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

## Later Roadmap

- M9: string variables
- M10: `show message` command
- M11: int + real exit code
- M12: simple `if`
- M13: multiple statements
- M14: basic functions
- M15: create window

