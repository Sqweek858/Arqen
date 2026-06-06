# M9 Let Variables Experiment Log

Status: `PASSED`

## Files Changed

```text
hello_m9.arq
expected_ast.txt
arq_lexer_m9_tokens.exe
arq_parser_m9.exe
hello_m9.tokens.txt
hello_m9.ast.txt
EXPERIMENT_LOG.md
```

Codex emitter:

```text
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m9.js
```

Bootstrap note:

- `emit_m9.js` is temporary Codex-side byte-emitter tooling.
- It is not the final Arqen compiler implementation.
- Node.js is required only to build or refresh the M9 `.exe` files during bootstrap.
- The milestone artifacts are `arq_lexer_m9_tokens.exe` and `arq_parser_m9.exe`.
- Those `.exe` artifacts run standalone without Node.js.

## Command To Run

```text
.\arq_lexer_m9_tokens.exe
.\arq_parser_m9.exe
```

## Input

```text
program "Hello"
let name be "Sqweek"
let number be 0
title "Arqen Byte Zero"
message text "Hello from Arqen"
exit 0
end program "Hello"
```

## Output Files

```text
hello_m9.tokens.txt
hello_m9.ast.txt
```

## Token Highlights

```text
KEYWORD(let) line 2 col 1
IDENT(name) line 2 col 5
KEYWORD(be) line 2 col 10
STRING(Sqweek) line 2 col 13

KEYWORD(let) line 3 col 1
IDENT(number) line 3 col 5
KEYWORD(be) line 3 col 12
INT(0) line 3 col 15
```

## AST Output

```text
Program:
    name: Hello
    Let:
        name: name
        type: text
        value: Sqweek
    Let:
        name: number
        type: int
        value: 0
    title: Arqen Byte Zero
    message: Hello from Arqen
    exit_code: 0
Semantic: OK
```

## Pass/Fail Result

```text
LEX_EXIT: 0
PARSE_EXIT: 0
AST_MATCH: True
DUP_LEX_EXIT: 0
DUP_PARSE_EXIT: 1
DUP_AST_EXISTS: False
UNKNOWN_LEX_EXIT: 0
UNKNOWN_PARSE_EXIT: 1
UNKNOWN_AST_EXISTS: False
```

## Known Limitations

- M9 supports the strict initial variables `name` and `number`.
- General lowercase identifier handling is not complete yet.
- Duplicate/unknown checks are strict for this M9 target shape, not a general symbol table.
- No variable references in expressions yet.
- No string concatenation yet.
- No codegen changes in M9.
- Parser errors are exit-code only; richer parser errors are reserved for M13.
