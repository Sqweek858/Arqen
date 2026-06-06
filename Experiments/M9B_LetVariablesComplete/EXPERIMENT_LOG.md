# M9B Let Variables Complete Experiment Log

Status: `PASSED`

## Files Changed

```text
hello_m9b.arq
expected_ast.txt
arq_lexer_m9b_tokens.exe
arq_parser_m9b.exe
hello_m9b.tokens.txt
hello_m9b.ast.txt
EXPERIMENT_LOG.md
```

Codex emitter:

```text
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m9b.js
```

Bootstrap note:

- `emit_m9b.js` is temporary Codex-side byte-emitter tooling.
- It is not the final Arqen compiler implementation.
- Node.js is required only to build or refresh the M9B `.exe` files during bootstrap.
- The milestone artifacts are `arq_lexer_m9b_tokens.exe` and `arq_parser_m9b.exe`.
- Those `.exe` artifacts run standalone without Node.js.

## Command To Run

```text
.\arq_lexer_m9b_tokens.exe
.\arq_parser_m9b.exe
```

## Input

```text
program "Hello"

let name be "Sqweek"
let number be 0
let active be true

title "Arqen Byte Zero"
message text "Hello from M9"
exit 0

end program "Hello"
```

## Output Files

```text
hello_m9b.tokens.txt
hello_m9b.ast.txt
arqen_m9b_error.txt
```

## Token Highlights

```text
KEYWORD(let)
IDENT(name)
KEYWORD(be)
STRING(Sqweek)

KEYWORD(let)
IDENT(number)
KEYWORD(be)
INT(0)

KEYWORD(let)
IDENT(active)
KEYWORD(be)
KEYWORD(true)
```

## AST Output

```text
Program:
    name: Hello

Variables:
    name: text = Sqweek
    number: int = 0
    active: bool = true

title: Arqen Byte Zero
message: Hello from M9
exit_code: 0

Semantic: OK
```

## Pass/Fail Result

```text
LEX_EXIT: 0
PARSE_EXIT: 0
AST_MATCH: True
```

Error cases:

```text
duplicate_name       -> Error S001, parse exit 1, no AST
missing_value        -> Error P012, parse exit 1, no AST
unknown_variable     -> Error S003, parse exit 1, no AST
unknown_type         -> Error T001, parse exit 1, no AST
invalid_name         -> Error S002, parse exit 1, no AST
unterminated_string  -> Error L002, parse exit 1, no AST
```

## Known Limitations

- Bool literal is currently represented in token dump as `KEYWORD(true)`.
- M9B validates the variable/title/message/exit body and emits the AST.
- `end program "Hello"` is present in source, but M9B parser does not fully validate it yet.
- General symbol table is still minimal and target-shaped.
- No variable references in message expressions yet.
- No string concatenation yet.
- No codegen changes in M9B.
