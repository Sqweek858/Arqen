# M8 AST Codegen Experiment Log

Status: `PASSED`

## Files Changed

```text
hello_m8.arq
expected_ast.txt
arq_lexer_m8_tokens.exe
arq_parser_m8.exe
arqc_m8.exe
template_messagebox_m8.exe
hello_m8.tokens.txt
hello_m8.ast.txt
hello_m8.exe
EXPERIMENT_LOG.md
```

Codex emitter:

```text
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m8.js
```

Bootstrap note:

- `emit_m8.js` is temporary Codex-side byte-emitter tooling.
- It is not the final Arqen compiler implementation.
- Node.js is required only to build or refresh the M8 `.exe` files during bootstrap.
- The milestone artifacts are `arq_lexer_m8_tokens.exe`, `arq_parser_m8.exe`, `arqc_m8.exe`, and `hello_m8.exe`.
- Those `.exe` artifacts run standalone without Node.js.

## Command To Run

```text
.\arq_lexer_m8_tokens.exe
.\arq_parser_m8.exe
.\arqc_m8.exe
```

## Input

```text
program "Hello"
title "Arqen Byte Zero"
message text "Hello from M8"
exit 0
end program "Hello"
```

## Output Files

```text
hello_m8.tokens.txt
hello_m8.ast.txt
hello_m8.exe
```

## AST

```text
Program:
    name: Hello
    title: Arqen Byte Zero
    message: Hello from M8
    exit_code: 0
Semantic: OK
```

## Generated EXE

```text
OUT_EXISTS: True
OUT_SIZE: 2048
MessageBoxW title: Arqen Byte Zero
MessageBoxW text: Hello from M8
RUN_DONE: True
EXIT: 0
```

## Pass/Fail Result

```text
LEX_EXIT: 0
PARSE_EXIT: 0
GEN_EXIT: 0
BAD_LEX_EXIT: 0
BAD_PARSE_EXIT: 1
AST_EXISTS after bad parse: False
EXE_EXISTS after bad parse: False
```

Bad source fails before codegen:

```text
Error P001:
Unexpected token stream.
```

## Known Limitations

- M8 uses three explicit tools, not one automatic driver command yet.
- `arqc_m8.exe` reads `hello_m8.ast.txt`; lexer/parser must run first.
- `template_messagebox_m8.exe` is a local codegen template file.
- Only strict M7B grammar is supported.
- Exit code support is still only `0`.
- Title/message buffers are fixed at 31 visible ASCII characters.
- No variables, expressions, if/else, or `blend mix` yet.
