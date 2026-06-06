# M6 Lexer Completion Plan

Status: `PASSED`

M6A and M6B proved scanning/token output, but M6 is not complete until token records are parser-ready.

## Stable Token Format

```text
TYPE(value) line X col Y
```

Special cases:

```text
NEWLINE line X
EOF
```

Example:

```text
KEYWORD(program) line 1 col 1
IDENT(Hello) line 1 col 9
STRING(Arqen Byte Zero) line 2 col 7
INT(0) line 4 col 6
EOF
```

## M6C: Line/Column

Status: `PASSED`

Track:

- current line
- current column
- token start line
- token start column

Needed for errors like:

```text
Error L002 at line 3, column 14:
Unterminated string.
```

Passing executable:

```text
Experiments/M6C_LineColumn/arq_lexer_m6c.exe
```

Current stable token dump:

```text
KEYWORD(program) line 1 col 1
IDENT(Hello) line 1 col 9
NEWLINE line 1
KEYWORD(title) line 2 col 1
STRING(Arqen Byte Zero) line 2 col 7
NEWLINE line 2
KEYWORD(message) line 3 col 1
KEYWORD(text) line 3 col 9
STRING(Hello from Arqen) line 3 col 14
NEWLINE line 3
KEYWORD(exit) line 4 col 1
INT(0) line 4 col 6
NEWLINE line 4
EOF
```

## M6D: Lexer Error Tests

Status: `PASSED`

Required cases:

- unknown character
- unterminated string
- invalid integer
- unexpected control character

Passing executable:

```text
Experiments/M6D_LexerErrors/arq_lexer_m6d.exe
```

Verified cases:

```text
valid_ok              -> exit 0
unknown_character     -> L001 line 1 col 1, exit 1
unterminated_string   -> L002 line 1 col 7, exit 2
invalid_integer       -> L003 line 1 col 6, exit 3
unexpected_control    -> L004 line 1 col 9, exit 4
```

## M6E: Completion Boundary

M6 is complete when:

- token values are emitted
- line/column are emitted
- token dump format is stable
- lexer errors include line/column

Then M7B can be parser-from-token-stream, not fixed-format scanning.

Current status:

```text
M6 COMPLETE
```
