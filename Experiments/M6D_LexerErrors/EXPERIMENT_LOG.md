# M6D Lexer Errors Experiment Log

Status: `PASSED`

Executable:

```text
arq_lexer_m6d.exe
```

Input:

```text
m6d_input.arq
```

Error output:

```text
arqen_lexer_error.txt
```

Verified cases:

```text
valid_ok              -> exit 0
unknown_character     -> L001 line 1 col 1, exit 1
unterminated_string   -> L002 line 1 col 7, exit 2
invalid_integer       -> L003 line 1 col 6, exit 3
unexpected_control    -> L004 line 1 col 9, exit 4
```

Example error:

```text
Error L002 at line 1, column 7:
Unterminated string.
```

Notes:

- The lexer keeps line and column while scanning.
- `exit abc` is treated as invalid integer in the strict M6D language path.

## Bootstrap Emitter Note

The bootstrap emitter is:

```text
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m6d.js
```

This JavaScript file is temporary Codex-side byte-emitter tooling. It is not the final Arqen compiler implementation.

Node.js is required only to build or refresh `arq_lexer_m6d.exe` during bootstrap. The milestone artifact is `arq_lexer_m6d.exe`, and it runs standalone without Node.js.
