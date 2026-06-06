# Arqen Project Status Report - After M10

Date: 2026-06-05

## Executive Summary

Arqen has a real bootstrap compiler chain up to M10:

```text
.arq source
-> lexer .exe
-> token dump
-> parser .exe
-> AST text
-> codegen .exe
-> Windows x64 PE .exe
```

The latest working milestone is:

```text
M10 Simple Expressions: PASSED
```

Current M10 source shape:

```text
program "Hello"

let name be "Sqweek"
let number be 0
let active be true

title "Arqen Byte Zero"
message text "Hello, " + name
exit 0

end program "Hello"
```

This produces `m10.exe`, a standalone Windows x64 executable that displays:

```text
title: Arqen Byte Zero
text:  Hello, Sqweek
exit:  0
```

## Current Folder Map

Project root:

```text
C:\Users\Sqweek\Documents\Arqen\Arqen
```

Codex bootstrap/scratch:

```text
C:\Users\Sqweek\Documents\Arqen\Codex
```

Main docs:

```text
Docs\MILESTONES.md
Docs\BOOTSTRAP_BYTE_EMITTERS.md
Docs\POST_M4_ROADMAP.md
Docs\PE_NOTES.md
Docs\WINDOWS_X64_ABI.md
Docs\OFFSETS.md
```

Main experiments:

```text
Experiments\M1_ExitProcess
Experiments\M2_MessageBoxW
Experiments\M4A_StaticExeWriter
Experiments\M4B_TemplatePatch
Experiments\M4C_StrictArqReader
Experiments\M4D_Errors
Experiments\M5_CLI_Minimal
Experiments\M6_LexerV1
Experiments\M6C_LineColumn
Experiments\M6D_LexerErrors
Experiments\M7_AST_Minimal
Experiments\M7B_TokenStreamParser
Experiments\M8_AST_Codegen
Experiments\M9_LetVariables
Experiments\M9B_LetVariablesComplete
Experiments\M10_SimpleExpressions
```

Codex emitters:

```text
Codex\emit_m6d.js
Codex\emit_m7b.js
Codex\emit_m8.js
Codex\emit_m9.js
Codex\emit_m9b.js
Codex\emit_m10.js
```

These emitters are temporary bootstrap byte emitters, not the final Arqen compiler implementation.

## Milestone Status

```text
M0   Empty valid PE concept          Documented, no standalone experiment folder
M1   ExitProcess-only PE             PASSED
M2   MessageBoxW PE                  PASSED
M3   Conceptual .arq source          PASSED
M4A  Static EXE writer               PASSED
M4B  Template + patch                PASSED
M4C  Strict .arq reader              PASSED
M4D  Clear .arq errors               PARTIAL PASS
M5   Minimal CLI                     PASSED
M6   Lexer v1                        PASSED
M6B  Token values                    PASSED
M6C  Line/column tokens              PASSED
M6D  Lexer error system              PASSED
M7A  Minimal AST parser              PASSED
M7B  Parser from token stream        PASSED
M8   Codegen from AST                PASSED
M9   Let variables                   PASSED
M9B  Let variables complete          PASSED
M10  Simple message expressions      PASSED
```

## Latest Smoke Verification

Final smoke result:

```text
29/29 passing checks
```

Verified:

```text
M1 ExitProcess v3                  exit 0
M2 MessageBox fixed                message box + exit 0
M4A generator                      exit 0
M4A generated exe                  message box + exit 0
M4B generator                      exit 0
M4B generated exe                  message box + exit 0
M4C generator                      exit 0
M4C generated exe                  message box + exit 0
M5 arqc hello_m5.arq               exit 0
M5 generated exe                   message box + exit 0
M6D valid/error cases              expected exits 0/1/2/3/4
M7B lexer/parser                   exit 0/0
M8 lexer/parser/codegen/exe        exit 0/0/0/0
M9 lexer/parser                    exit 0/0
M9B lexer/parser                   exit 0/0
M10 lexer/parser/codegen/exe       exit 0/0/0/0
```

## What Is Good

The big win: this is not just notes. There are real Windows x64 PE files being produced and run.

Strong points:

- M1 proved a minimal PE can start and call `ExitProcess(0)`.
- M2 proved imports beyond kernel32 work through `user32.dll!MessageBoxW`.
- M4A proved an Arqen-built executable can write another valid executable.
- M4B/M4C proved template patching and strict source reading.
- M5 proved a minimal CLI shape.
- M6/M6B/M6C/M6D proved tokens, token values, line/column, and lexer errors.
- M7B moved parsing from source scanning to token-stream parsing.
- M8 established the important compiler pipeline: source -> tokens -> AST -> codegen -> exe.
- M9/M9B added variables and basic semantic checks.
- M10 added the first expression support for `message text`.
- Bootstrap boundary is documented: Node.js is only for emitting bootstrap artifacts.
- The generated `.exe` artifacts run standalone without Node.js.
- The project has experiment logs for every major step.

## What Is Weak

### 1. Parser is still target-shaped

M10 works for the approved fixtures, but it is not a general parser yet.

Examples:

- variable names are still mostly hardcoded around `name`, `number`, `active`
- M10 recognizes the tested expression shapes
- `end program "Hello"` is not fully validated in older milestones
- token-stream parsing exists, but grammar coverage is still narrow

Risk:

```text
Small syntax changes can fail unexpectedly.
```

### 2. Codegen is still fixed-path and template-based

M8/M10 codegen reads fixed AST filenames and patches a fixed MessageBox PE template.

Risk:

```text
This is fine for bootstrap, but not yet a flexible compiler backend.
```

### 3. Token dump text is the compiler interface

The parser consumes text token dumps like:

```text
KEYWORD(program) line 1 col 1
```

That is useful for learning/debugging, but fragile as a long-term internal format.

Risk:

```text
Formatting changes can break parsing.
```

### 4. M4D error system is partial

Passed:

```text
missing title
missing message
missing exit
```

Still not fully covered:

```text
string too long
missing quotes
unsupported exit code
unknown keyword
```

### 5. Docs have status drift

Some docs still carry older labels:

- M2 says `IN PROGRESS` in one place even though M2 passed.
- M4 says `PLANNING` in one place even though M4A/B/C passed and M4D partial passed.
- M5 is named `Minimal Parser` in one heading, but the actual passed artifact is minimal CLI.
- `BOOTSTRAP_BYTE_EMITTERS.md` has the lower M10 entries, but the top emitter list still needs `emit_m10.js`.

Risk:

```text
Future you may trust old status labels and lose time.
```

### 6. Old failed artifacts are still present

Examples:

```text
M1: arqen_m1_exitprocess.exe
M1: arqen_m1_exitprocess_v2.exe
M2: arqen_m2_messagebox.exe
```

The passing versions are documented, but the old files can confuse manual testing.

Risk:

```text
Opening the wrong exe can look like a regression.
```

### 7. No git repository detected

`C:\Users\Sqweek\Documents\Arqen\Arqen` is not currently a git repository.

Risk:

```text
No easy rollback, diff, branch, or milestone snapshot.
```

### 8. PE internals are still hand/patch heavy

This is expected for Byte Zero, but it is fragile.

Risk areas:

- fixed RVAs
- fixed raw offsets
- fixed import layouts
- fixed string buffers
- section sizes patched manually
- many tools depend on exact template bytes

### 9. Language scope is intentionally tiny

Current language can not yet do:

- if/else
- loops
- functions
- multiple output actions
- runtime expression evaluation
- real int math
- non-zero exit code support in generated code
- variables in all useful positions
- arbitrary identifiers
- reusable modules
- real UI/window syntax

This is not a failure. It is just the true boundary.

## Current Language Capability

Currently proven:

```text
program "Hello"
let name be "Sqweek"
let number be 0
let active be true
title "Arqen Byte Zero"
message text "Hello, " + name
exit 0
end program "Hello"
```

Supported concepts:

- program name
- title
- message text
- exit 0
- text/int/bool literal variables
- text concatenation in `message text`
- unknown variable error
- type mismatch error
- broken `+` error

Not supported yet:

- expression values in `let`
- text + int
- text + bool
- int math
- bool logic
- if/else
- `blend mix to code`
- real generalized CLI for latest pipeline

## Best Next Move

Best technical next step:

```text
M10R / M11A: make parser less target-shaped before adding if/else.
```

Recommended order:

1. Clean docs status drift.
2. Move old failed exes into an `archive` folder or mark them clearly.
3. Initialize git.
4. Make M10 parser support arbitrary variable names from token stream.
5. Make a single current CLI driver:

```text
arqc m10.arq
```

6. Only then add M11 if/else or M12 `blend mix to code`.

Reason:

```text
Adding if/else on top of a target-shaped parser will multiply bugs.
Hardening M10 first gives the language a stronger spine.
```

## Verdict

Arqen is in a surprisingly good place for a byte-first compiler project.

The core idea is proven:

```text
we can build raw PE files,
we can generate PE files from our own executables,
we can lex/parse/AST/codegen through standalone .exe artifacts,
and M10 can compile a tiny expression into a working Windows executable.
```

The main weakness is not concept. The main weakness is generality.

Current state:

```text
Real: yes.
Tiny: yes.
Fragile: yes.
Worth continuing: absolutely.
```
