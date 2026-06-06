# AST Dump Format

Status: bootstrap contract

## Purpose

The AST dump is the current text interface between the parser stage and the codegen stage.

Current pipeline:

```text
parser .exe
-> AST dump .txt
-> codegen .exe
-> Windows .exe
```

This is a bootstrap text format. It is stable enough for current codegen, but it is not the final in-memory AST or IR.

## M8 Compatible Header

M8 and later codegen expects the important fields in this shape:

```text
Program:
    name: Hello
    title: Arqen Byte Zero
    message: Hello from Arqen
    exit_code: 0
Semantic: OK
```

Current codegen reads:

- `title`
- `message`
- `exit_code`

Current supported exit code:

```text
0
```

## Variables Section

M9B introduced a variables section:

```text
Variables:
    name: text = Sqweek
    number: int = 0
    active: bool = true
```

Current supported types:

```text
text
int
bool
```

Current `let` values must be literals.

## Message Expression Section

M10 introduced expression details for `message text`:

```text
Message:
    expression:
        BinaryPlus:
            left:
                StringLiteral: Hello, 
            right:
                VariableRef: name
```

For chained text literals:

```text
Message:
    expression:
        BinaryPlus:
            left:
                BinaryPlus:
                    left:
                        StringLiteral: Hello
                    right:
                        StringLiteral:  from 
            right:
                StringLiteral: M10
```

The generated message is still folded into the top-level `message:` field for current codegen.

## Semantic Result

Successful AST dumps contain:

```text
Semantic: OK
```

Failed parse or semantic checks should not produce a valid AST for codegen.

Error files are separate, for example:

```text
arqen_m10_error.txt
arqen_codegen_error.txt
```

## Current Limitations

- AST dump is text-based.
- Indentation is currently meaningful to humans, but codegen mainly searches fields.
- There is no structured/binary IR yet.
- General expression AST is not complete.
- Parser and codegen are still milestone-shaped.

## Future Direction

Recommended future stable AST/IR work:

```text
M10R_GenericParser:
parser builds generalized AST records
AST dump remains debug output
codegen consumes structured AST fields
```
