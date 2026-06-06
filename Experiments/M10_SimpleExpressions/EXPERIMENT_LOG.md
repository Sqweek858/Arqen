# M10 Simple Expressions

Status: PASSED

## Goal

Add the first expression system for `message text`.

Supported in M10:

- string literals
- variable references
- binary `+`
- compile-time text concatenation

Not supported:

- int math
- bool concatenation
- runtime string allocation
- if/else
- functions
- UI/window syntax

## Files

- `m10.arq`
- `arq_lexer_m10_tokens.exe`
- `arq_parser_m10.exe`
- `arqc_m10.exe`
- `m10.tokens.txt`
- `m10.ast.txt`
- `m10.exe`
- `tests\*.arq`

Bootstrap emitter:

- `C:\Users\Sqweek\Documents\Arqen\Codex\emit_m10.js`

`emit_m10.js` is temporary bootstrap byte-emitter tooling. It is not the final Arqen compiler implementation.

## Commands

```text
.\arq_lexer_m10_tokens.exe
.\arq_parser_m10.exe
.\arqc_m10.exe
.\m10.exe
```

## Result

```text
LEX_EXIT: 0
PARSE_EXIT: 0
CODEGEN_EXIT: 0
M10_EXE_EXIT: 0
```

Generated `m10.exe` displays:

```text
title: Arqen Byte Zero
text:  Hello, Sqweek
```

## Test Matrix

```text
valid_name_concat      -> PASS, Hello, Sqweek
valid_string_concat    -> PASS, Hello from M10
unknown_variable       -> PASS, Error S010
type_mismatch_bool     -> PASS, Error S011
message_expects_text   -> PASS, Error S012
broken_plus            -> PASS, Error P011
```

## Known Limitations

- `let` values are still literals only.
- Parser is still target-shaped for the M10 fixtures.
- Only `message text` accepts expressions.
- `+` is supported only for text concatenation.
- No expression codegen exists yet beyond compile-time folding into the generated MessageBox text.
