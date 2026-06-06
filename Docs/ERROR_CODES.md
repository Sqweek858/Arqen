# Error Codes

Status: current bootstrap registry

## Rules

- Error codes should be stable once documented.
- Do not reuse a code for a different meaning.
- Prefer one code per distinct user-facing failure.
- Include the stage that emits the error.

## M4 `.arq` Reader Errors

| Code | Stage | Meaning | Example |
| --- | --- | --- | --- |
| A003 | M4D generator | Missing required field: title | source has message/exit but no title |
| A004 | M4D generator | Missing required field: message | source has title/exit but no message |
| A005 | M4D generator | Missing required field: exit | source has title/message but no exit |

Known M4D gaps:

```text
missing quotes
string too long
unsupported exit code
unknown keyword
```

## Lexer Errors

| Code | Stage | Meaning | Example bad source |
| --- | --- | --- | --- |
| L001 | M6D lexer | Unknown character | `@bad` |
| L002 | M6D/M9B lexer/parser path | Unterminated string | `title "Missing end quote` |
| L003 | M6D lexer | Invalid integer | `exit abc` in strict lexer test |
| L004 | M6D lexer | Unexpected control character | source contains unsupported control byte |

Example:

```text
Error L002 at line 1, column 7:
Unterminated string.
```

## Parser Errors

| Code | Stage | Meaning | Example bad source |
| --- | --- | --- | --- |
| P001 | M7B/M9B parser | Unexpected token in strict parser path | malformed token sequence |
| M9P001 | M9 parser | Unexpected token in M9 parser | malformed M9 token sequence |
| P010 | M10 parser | Expected expression after `message text` | `message text` |
| P011 | M10 parser | Expected expression after `+` | `message text "Hello" +` |
| P012 | M9B parser | Expected value after `be` | `let number be` |

Important:

```text
P012 is currently used by M9B for missing let value.
Do not reuse P012 for another expression error without renaming one side.
```

## Semantic Errors

| Code | Stage | Meaning | Example bad source |
| --- | --- | --- | --- |
| S001 | M9B semantic | Duplicate variable | `let name be "A"` then `let name be "B"` |
| S002 | M9B semantic | Invalid variable name | invalid `let` identifier shape |
| S003 | M9B semantic | Unknown variable reference in let value | `let name be otherName` |
| S010 | M10 semantic | Unknown variable in expression | `message text "Hello, " + username` |
| S011 | M10 semantic | Type mismatch in expression | `message text "Active: " + active` |
| S012 | M10 semantic | `message text` requires text expression | `message text number` |
| S013 | M10 semantic | Unsupported expression type in M10 | unrecognized expression shape |
| T001 | M9B semantic | Unknown literal type for variable | unsupported `let` value |

## Codegen Errors

| Code | Stage | Meaning | Example |
| --- | --- | --- | --- |
| C001 | M8/M10 codegen | Invalid AST for current codegen | missing expected `title`, `message`, or `exit_code` |

## Notes

Current errors are milestone-shaped and not all include rich suggestions yet.

Future target for every error:

```text
Error CODE at line X, column Y:
What happened.

Expected:
...

Fix:
...
```
