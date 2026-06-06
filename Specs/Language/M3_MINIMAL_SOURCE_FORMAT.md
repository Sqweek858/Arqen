# M3 Minimal Source Format

Status:

```text
CONCEPTUAL
```

Purpose:

- Define the first tiny `.arq` source shape.
- Map that source directly to the already proven M2 executable behavior.
- Do not implement a parser yet.

## Target Behavior

M3 source should describe this behavior:

```text
MessageBoxW(NULL, L"Hello from Arqen", L"Arqen Byte Zero", 0)
ExitProcess(0)
```

M2 already proved this behavior can be emitted as a valid Windows x64 PE32+ executable.

## First Source Example

```arq
program Hello:
    show message "Hello from Arqen"
    exit 0
```

## Syntax Rules

This first format is intentionally strict.

### Program Header

Required:

```arq
program Name:
```

Rules:

- `program` is lowercase.
- `Name` must be an identifier.
- The line must end with `:`.
- The program body is indented.

Identifier draft rule:

```text
[A-Za-z_][A-Za-z0-9_]*
```

### Show Message Statement

Required form:

```arq
show message "text"
```

Rules:

- `show message` is lowercase.
- The message must be a string literal.
- For M3, only one `show message` statement is allowed.
- For M3, the message maps to the `MessageBoxW` body text.

### Exit Statement

Required form:

```arq
exit 0
```

Rules:

- `exit` is lowercase.
- For M3, only integer literal `0` is supported.
- The statement maps to `ExitProcess(0)`.

## Current Fixed Caption

M3 source does not define the message box caption yet.

For this milestone, the caption is fixed by the backend:

```text
Arqen Byte Zero
```

Future syntax may allow:

```arq
show message "Hello from Arqen" titled "Arqen Byte Zero"
```

But that is not part of M3.

## Minimal Grammar Sketch

This is a sketch, not an implemented parser.

```text
program_file    = program_header newline statement+ ;
program_header  = "program" space identifier ":" ;
statement       = indent show_message newline
                | indent exit_statement newline ;
show_message    = "show" space "message" space string_literal ;
exit_statement  = "exit" space integer_literal ;
identifier      = letter_or_underscore (letter_or_digit_or_underscore)* ;
string_literal  = '"' character* '"' ;
integer_literal = "0" ;
```

## Semantic Mapping

For this exact source:

```arq
program Hello:
    show message "Hello from Arqen"
    exit 0
```

The conceptual backend maps:

| Source | PE/WinAPI Meaning |
|---|---|
| `program Hello:` | executable entry unit |
| `show message "Hello from Arqen"` | `MessageBoxW(NULL, L"Hello from Arqen", L"Arqen Byte Zero", 0)` |
| `exit 0` | `ExitProcess(0)` |

## Not Supported In M3

M3 does not support:

- variables
- functions
- multiple messages
- custom captions
- custom exit codes other than `0`
- escape sequences
- Unicode source validation rules
- comments
- imports
- memory domains
- windows
- devices
- parser implementation
- compiler implementation

## Error Style Draft

Even though M3 has no parser yet, the intended error style is:

```text
Error S001 at line 1, column 1:
Expected program header.

Expected:
program Name:

Found:
show message "Hello"
```

For missing exit:

```text
Error P001:
Program "Hello" has no exit statement.

M3 programs must end with:
    exit 0
```

## M3 Success Criteria

M3 is passed when:

- The minimal source format is documented.
- A sample `.arq` file exists.
- The mapping to the proven M2 executable behavior is clear.
- No parser has been implemented yet.

