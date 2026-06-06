# M6 Lexer v1 Experiment Log

Status: `PASSED`

Executable:

```text
arq_lexer_m6.exe
```

Input:

```text
hello_m6.arq
```

Output:

```text
hello_m6.tokens.txt
```

Result:

```text
LEX_EXIT: 0
```

## M6D: Lexer Errors

Status: `PASSED`

Executable:

```text
Experiments/M6D_LexerErrors/arq_lexer_m6d.exe
```

Cases:

```text
valid_ok              -> exit 0
unknown_character     -> L001 line 1 col 1, exit 1
unterminated_string   -> L002 line 1 col 7, exit 2
invalid_integer       -> L003 line 1 col 6, exit 3
unexpected_control    -> L004 line 1 col 9, exit 4
```

Tokens:

```text
KEYWORD
IDENT
NEWLINE
KEYWORD
STRING
NEWLINE
KEYWORD
STRING
NEWLINE
KEYWORD
INT
NEWLINE
EOF
```

Implemented:

- keyword-like lowercase identifiers
- uppercase identifier
- string literal scanning
- integer scanning
- newline tokens
- EOF token

Limits:

- no lexeme output yet
- keyword detection is v1-level, not full keyword table
- fixed input/output paths

## M6B: Token Lexemes

Status: `PASSED`

Executable:

```text
arq_lexer_m6b.exe
```

Input:

```text
hello_m6b.arq
```

Output:

```text
hello_m6b.tokens.txt
```

Tokens:

```text
KEYWORD program
IDENT Hello
KEYWORD title
STRING Arqen Byte Zero
KEYWORD message
KEYWORD text
STRING Hello from Arqen
KEYWORD exit
INT 0
EOF
```

Limits:

- keyword detection is still simple lowercase-word detection
- fixed input/output paths

## M6C: Line/Column Token Dump

Status: `PASSED`

Executable:

```text
Experiments/M6C_LineColumn/arq_lexer_m6c.exe
```

Input:

```text
Experiments/M6C_LineColumn/hello_m6c.arq
```

Output:

```text
Experiments/M6C_LineColumn/hello_m6c.tokens.txt
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

Result:

```text
LEX_EXIT: 0
```
