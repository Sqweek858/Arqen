# M10G Core Pipeline Upgrade

Status: PASSED

## Goal

Turn the M10 multi-tool experiment into a single-driver compiler workflow.

No new language features were added.

## Driver

```text
Tools\arqc_m10g.exe
```

Command:

```powershell
.\Tools\arqc_m10g.exe .\Samples\hello_m10.arq
```

Output:

```text
Build\Tokens\hello_m10.tokens
Build\AST\hello_m10.ast
Build\EXE\hello_m10.exe
Build\Logs\hello_m10.build.log
```

Custom output is supported:

```powershell
.\Tools\arqc_m10g.exe .\Samples\hello_m10.arq -o .\Output\custom.exe
```

## Stage Result Contract

Example success:

```text
[LEX] PASS -> Build\Tokens\hello_m10.tokens
[PARSE] PASS -> syntax OK
[SEMANTIC] PASS -> Build\AST\hello_m10.ast
[CODEGEN] PASS -> Build\EXE\hello_m10.exe
[BUILD] PASS
```

Example failure:

```text
[SEMANTIC] FAIL S010 -> Build\Errors\unknown_variable.semantic.error.txt
Compiler stopped before codegen.
```

## Build Layout

```text
Build\Tokens
Build\AST
Build\EXE
Build\Errors
Build\Logs
```

## Stable Token Format

M10G emits:

```text
TYPE|VALUE|LINE|COLUMN
```

Example:

```text
KEYWORD|program|1|1
STRING|Hello|1|9
IDENT|name|3|5
PLUS|+|8|24
BOOL|true|5|15
EOF||12|1
```

## Stable AST Format

M10G emits:

```text
PROGRAM|Hello
LET|name|text|Sqweek
TITLE|Arqen Byte Zero
MESSAGE|Hello, Sqweek
MESSAGE_EXPR|plus(str("Hello, "),var(name))
EXIT|0
SEMANTIC|OK
```

## Parser Generality

M10G supports arbitrary variable names in M10 grammar:

```text
let userName be "Sqweek"
let greeting be "Hello"
message text greeting + ", " + userName
```

Generated message:

```text
Hello, Sqweek
```

## Verification

```text
Tools\run_all_tests.ps1
Total: 39/39 passed
```

M10G driver cases:

```text
M10G_DRIVER_SAMPLE PASS
M10G_OUT PASS
M10G_VALID_NAME PASS
M10G_VALID_STRING PASS
M10G_ARBITRARY_VARS PASS
M10G_UNKNOWN_VAR PASS
M10G_DUPLICATE_VAR PASS
M10G_BOOL_MISMATCH PASS
M10G_MESSAGE_TEXT_TYPE PASS
M10G_BROKEN_PLUS PASS
```

## Known Limitations

- Driver is a bootstrap .NET tool, not the final self-hosted compiler.
- Generated output PE still uses the M8 MessageBox template.
- `let` values are still literals only.
- `message text` is still the only expression-enabled field.
- `+` is still text concatenation only.
- No if/else, blend, functions, loops, UI/window/style, or new syntax.
