# M7B Token Stream Parser Experiment Log

Status: `PASSED`

## Files Changed

```text
hello_m7b.arq
expected_ast.txt
arq_lexer_m7b_tokens.exe
arq_parser_m7b.exe
hello_m7b.tokens.txt
hello_m7b.ast.txt
EXPERIMENT_LOG.md
```

Codex emitter:

```text
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m7b.js
```

Bootstrap note:

- `emit_m7b.js` is temporary Codex-side byte-emitter tooling.
- It is not the final Arqen compiler implementation.
- Node.js is required only to build or refresh the M7B `.exe` files during bootstrap.
- The milestone artifacts are `arq_lexer_m7b_tokens.exe` and `arq_parser_m7b.exe`.
- Those `.exe` artifacts run standalone without Node.js.

## Command To Run

```text
.\arq_lexer_m7b_tokens.exe
.\arq_parser_m7b.exe
```

## Input

```text
program "Hello"
title "Arqen Byte Zero"
message text "Hello from Arqen"
exit 0
end program "Hello"
```

## Output Files

```text
hello_m7b.tokens.txt
hello_m7b.ast.txt
```

## AST Output

```text
Program:
    name: Hello
    title: Arqen Byte Zero
    message: Hello from Arqen
    exit_code: 0
Semantic: OK
```

## Pass/Fail Result

```text
LEX_EXIT: 0
PARSE_EXIT: 0
BAD_PARSE_EXIT: 1
```

Bad token stream result:

```text
Error P001:
Unexpected token stream.
```

## Known Limitations

- Parser reads M6 token dump text, not a binary token format.
- Parser supports only the strict M7B grammar.
- Parser does not compare start/end program names yet.
- Parser error is generic `P001`; richer parser errors are reserved for M13.
- No codegen in M7B.
