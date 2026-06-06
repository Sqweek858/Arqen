# M6C Line/Column Experiment Log

Status: `PASSED`

Executable:

```text
arq_lexer_m6c.exe
```

Input:

```text
hello_m6c.arq
```

Output:

```text
hello_m6c.tokens.txt
```

Result:

```text
LEX_EXIT: 0
```

Tokens:

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

Notes:

- `NEWLINE line 4` appears because the source file ends with a newline.
- Lowercase words are emitted as `KEYWORD(...)`.
- Uppercase-start words are emitted as `IDENT(...)`.
