# Bootstrap Byte Emitters

Status: `TEMPORARY BOOTSTRAP ONLY`

These files are Codex-side bootstrap byte emitters:

```text
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m6d.js
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m7b.js
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m8.js
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m9.js
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m9b.js
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m10.js
```

`emit_m7b.js` is the current M7 token-stream parser emitter. If notes refer to `emit_m7.js`, they mean this M7B emitter.

## Purpose

The emitters exist to write bootstrap PE artifacts from raw bytes while Arqen does not yet have its own mature compiler pipeline.

They may:

- copy or patch a known PE template
- write `.exe` files used by milestones
- create fixed-path test tools for a milestone

They must not be treated as:

- the final Arqen compiler implementation
- the final parser implementation
- the final code generator design
- a runtime dependency of generated milestone artifacts

## Milestone Artifacts

The actual milestone artifacts are the generated executable files:

```text
Experiments\M6D_LexerErrors\arq_lexer_m6d.exe
Experiments\M7B_TokenStreamParser\arq_lexer_m7b_tokens.exe
Experiments\M7B_TokenStreamParser\arq_parser_m7b.exe
Experiments\M8_AST_Codegen\arq_lexer_m8_tokens.exe
Experiments\M8_AST_Codegen\arq_parser_m8.exe
Experiments\M8_AST_Codegen\arqc_m8.exe
Experiments\M8_AST_Codegen\hello_m8.exe
Experiments\M9_LetVariables\arq_lexer_m9_tokens.exe
Experiments\M9_LetVariables\arq_parser_m9.exe
Experiments\M9B_LetVariablesComplete\arq_lexer_m9b_tokens.exe
Experiments\M9B_LetVariablesComplete\arq_parser_m9b.exe
Experiments\M10_SimpleExpressions\arq_lexer_m10_tokens.exe
Experiments\M10_SimpleExpressions\arq_parser_m10.exe
Experiments\M10_SimpleExpressions\arqc_m10.exe
Experiments\M10_SimpleExpressions\m10.exe
```

Node.js is required only to run the temporary bootstrap emitter scripts and produce or refresh those `.exe` files.

After emission, the `.exe` files run directly as Windows PE executables without Node.js.

## Pass Criteria

A milestone passes only if:

- the generated `.exe` artifact runs standalone
- the artifact behavior matches the milestone requirement
- Node.js is not needed to run the artifact
- Node.js is used only for the temporary bootstrap emission step

## Current Confirmation

```text
M6D: arq_lexer_m6d.exe runs standalone without Node.js.
M7B: arq_lexer_m7b_tokens.exe and arq_parser_m7b.exe run standalone without Node.js.
M8: arq_lexer_m8_tokens.exe, arq_parser_m8.exe, arqc_m8.exe, and hello_m8.exe run standalone without Node.js.
M9: arq_lexer_m9_tokens.exe and arq_parser_m9.exe run standalone without Node.js.
M9B: arq_lexer_m9b_tokens.exe and arq_parser_m9b.exe run standalone without Node.js.
M10: arq_lexer_m10_tokens.exe, arq_parser_m10.exe, arqc_m10.exe, and m10.exe run standalone without Node.js.
```

Latest standalone verification:

```text
M6D_EXIT: 0
M7B_LEX_EXIT: 0
M7B_PARSE_EXIT: 0
M8_LEX_EXIT: 0
M8_PARSE_EXIT: 0
M8_GEN_EXIT: 0
HELLO_M8_EXIT: 0
M9_LEX_EXIT: 0
M9_PARSE_EXIT: 0
M9B_LEX_EXIT: 0
M9B_PARSE_EXIT: 0
M10_LEX_EXIT: 0
M10_PARSE_EXIT: 0
M10_CODEGEN_EXIT: 0
M10_EXE_EXIT: 0
```

Current temporary emitter list:

```text
emit_m6d.js
emit_m7b.js
emit_m8.js
emit_m9.js
emit_m9b.js
emit_m10.js
```

## Boundary

When Arqen grows a real self-hosted compiler path, these JavaScript emitters should be retired or kept only as historical/bootstrap tooling.
