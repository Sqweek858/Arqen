# Token Dump Format

Status: bootstrap contract, implemented by M10G driver

## Purpose

The token dump is the current text interface between the lexer stage and the parser stage.

Current pipeline:

```text
.arq source
-> lexer .exe
-> token dump .txt
-> parser .exe
```

This is a bootstrap internal format. It is not the final Arqen IR.

## Current Human Format

Current emitted examples:

```text
KEYWORD(program) line 1 col 1
STRING(Hello) line 1 col 9
IDENT(name) line 3 col 5
PLUS(+) line 8 col 24
INT(0) line 9 col 6
KEYWORD(true) line 5 col 15
NEWLINE line 1
EOF
```

Rules:

- One token per line.
- Token type is uppercase.
- Token value appears inside parentheses for value-carrying tokens.
- `NEWLINE` carries line only.
- `EOF` has no value, line, or column in the current human format.
- Line and column are 1-based.
- Column means source character position where the token starts.

Current token types:

```text
KEYWORD
IDENT
STRING
INT
PLUS
NEWLINE
EOF
```

Current bool note:

```text
true is currently emitted as KEYWORD(true), not BOOL(true).
```

## Stable M10G Format

M10G emits this stable format:

```text
TYPE|VALUE|LINE|COLUMN
```

Examples:

```text
KEYWORD|program|1|1
STRING|Hello|1|9
IDENT|name|3|5
PLUS|+|8|24
INT|0|9|6
BOOL|true|5|15
NEWLINE||1|14
EOF||12|1
```

## Stable Format Rules

- Field separator: `|`.
- Exactly four fields per token line.
- Empty value is represented as an empty field.
- Empty line/column is allowed only for legacy EOF, but future EOF should carry a location.
- Values escape `\`, `|`, CR, and LF.
- Strings are stored without surrounding quotes.
- Line and column are decimal integers, 1-based.

Escapes:

```text
\\ = literal backslash
\p = literal |
\r = carriage return
\n = line feed
```

Current M10G boolean token:

```text
BOOL|true|5|15
BOOL|false|5|15
```

## Parser Contract

Parser tools should depend on token type and value, not cosmetic wording.

Good:

```text
TYPE=KEYWORD, VALUE=message
TYPE=STRING, VALUE=Hello
```

Fragile:

```text
find "KEYWORD(message) line"
```

## Migration TODO

M10G implements the stable format in the single driver path.

The older M10 manual lexer still emits the historical human format.

Suggested future milestone:

```text
M10R_GenericParser:
manual lexer/parser tools migrate to TYPE|VALUE|LINE|COLUMN
old human format becomes debug-only
```
