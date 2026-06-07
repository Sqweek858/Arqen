# Tool Map

Status: M10I backend architecture

Use this file to know which executable is safe to run and which one is old, broken, partial, or only a generated output.

## Status Legend

```text
known-good  verified in current smoke tests or milestone logs
partial     useful but incomplete
obsolete    old milestone artifact kept for history
broken      known failed artifact, archived
unknown     not enough evidence yet
```

## Compiler Stages

| File | Path | Milestone | Category | Does | Inputs | Outputs | Command | Standalone | Node required | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `arqc_m10g.exe` | `Tools` | M10I | compiler stage | Single driver: lexes, parses, checks semantics, lowers to ARQIR, runs backend, and writes artifact manifest | any M10 `.arq` file or `--backend-only` `.arqir` file | `Build\Tokens`, `Build\AST`, `Build\IR`, `Build\EXE`, `Build\Manifests`, `Build\Errors`, `Build\Diagnostics`, `Build\Logs` | `.\Tools\arqc_m10g.exe .\Samples\hello_m10.arq` | yes | no | known-good | Bootstrap .NET tool; current workflow |
| `new_command_scaffold.ps1` | `Tools` | M10H | bootstrap helper | Creates command implementation draft folders | command name | `Experiments\CommandDrafts\<Name>` | `.\Tools\new_command_scaffold.ps1 BlendMixToCode` | no | no | known-good | PowerShell scaffold helper, not compiler runtime |
| `arq_lexer_m10_tokens.exe` | `Experiments\M10_SimpleExpressions` | M10 | compiler stage | Lexes M10 source | `m10.arq` | `m10.tokens.txt` | `.\arq_lexer_m10_tokens.exe` | yes | no | known-good | Latest lexer artifact |
| `arq_parser_m10.exe` | `Experiments\M10_SimpleExpressions` | M10 | compiler stage | Parses M10 token dump and folds message expression | `m10.tokens.txt` | `m10.ast.txt` or `arqen_m10_error.txt` | `.\arq_parser_m10.exe` | yes | no | known-good | Target-shaped but passing |
| `arqc_m10.exe` | `Experiments\M10_SimpleExpressions` | M10 | compiler stage | Generates MessageBox PE from AST | `m10.ast.txt`, `template_messagebox_m8.exe` | `m10.exe` | `.\arqc_m10.exe` | yes | no | known-good | Fixed-path bootstrap codegen |
| `arq_lexer_m9b_tokens.exe` | `Experiments\M9B_LetVariablesComplete` | M9B | compiler stage | Lexes M9B source | `hello_m9b.arq` | `hello_m9b.tokens.txt` | `.\arq_lexer_m9b_tokens.exe` | yes | no | known-good | Bool currently tokenized as `KEYWORD(true)` |
| `arq_parser_m9b.exe` | `Experiments\M9B_LetVariablesComplete` | M9B | compiler stage | Parses M9B lets and semantic checks | `hello_m9b.tokens.txt` | `hello_m9b.ast.txt` or `arqen_m9b_error.txt` | `.\arq_parser_m9b.exe` | yes | no | known-good | Target-shaped symbol table |
| `arq_lexer_m9_tokens.exe` | `Experiments\M9_LetVariables` | M9 | compiler stage | Lexes M9 source | `hello_m9.arq` | `hello_m9.tokens.txt` | `.\arq_lexer_m9_tokens.exe` | yes | no | known-good | Historical M9 |
| `arq_parser_m9.exe` | `Experiments\M9_LetVariables` | M9 | compiler stage | Parses first `let` variables | `hello_m9.tokens.txt` | `hello_m9.ast.txt` | `.\arq_parser_m9.exe` | yes | no | known-good | Superseded by M9B |
| `arq_lexer_m8_tokens.exe` | `Experiments\M8_AST_Codegen` | M8 | compiler stage | Lexes M8 source | `hello_m8.arq` | `hello_m8.tokens.txt` | `.\arq_lexer_m8_tokens.exe` | yes | no | known-good | Historical M8 |
| `arq_parser_m8.exe` | `Experiments\M8_AST_Codegen` | M8 | compiler stage | Parses M8 token dump | `hello_m8.tokens.txt` | `hello_m8.ast.txt` | `.\arq_parser_m8.exe` | yes | no | known-good | Historical M8 |
| `arqc_m8.exe` | `Experiments\M8_AST_Codegen` | M8 | compiler stage | Generates MessageBox PE from AST | `hello_m8.ast.txt`, `template_messagebox_m8.exe` | `hello_m8.exe` | `.\arqc_m8.exe` | yes | no | known-good | Base for M10 codegen |
| `arq_lexer_m7b_tokens.exe` | `Experiments\M7B_TokenStreamParser` | M7B | compiler stage | Lexes M7B source | `hello_m7b.arq` | `hello_m7b.tokens.txt` | `.\arq_lexer_m7b_tokens.exe` | yes | no | known-good | Historical token-stream parser input |
| `arq_parser_m7b.exe` | `Experiments\M7B_TokenStreamParser` | M7B | compiler stage | Parses token dump into AST | `hello_m7b.tokens.txt` | `hello_m7b.ast.txt` | `.\arq_parser_m7b.exe` | yes | no | known-good | First parser from token stream |
| `arq_lexer_m6d.exe` | `Experiments\M6D_LexerErrors` | M6D | compiler stage | Lexes strict input and emits lexer errors | `m6d_input.arq` | token/error files | `.\arq_lexer_m6d.exe` | yes | no | known-good | Error tests pass |
| `arq_lexer_m6c.exe` | `Experiments\M6C_LineColumn` | M6C | compiler stage | Emits line/column token dump | `hello_m6c.arq` | `hello_m6c.tokens.txt` | `.\arq_lexer_m6c.exe` | yes | no | known-good | Superseded by later lexers |
| `arq_lexer_m6b.exe` | `Experiments\M6_LexerV1` | M6B | compiler stage | Emits token values | `hello_m6b.arq` | `hello_m6b.tokens.txt` | `.\arq_lexer_m6b.exe` | yes | no | known-good | Historical |
| `arq_lexer_m6.exe` | `Experiments\M6_LexerV1` | M6 | compiler stage | Emits basic token kinds | `hello_m6.arq` | `hello_m6.tokens.txt` | `.\arq_lexer_m6.exe` | yes | no | known-good | Historical |

## Generators And Generated Outputs

| File | Path | Milestone | Category | Does | Inputs | Outputs | Command | Standalone | Node required | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `m10.exe` | `Experiments\M10_SimpleExpressions` | M10 | generated output | Shows folded M10 message | none | MessageBox + exit 0 | `.\m10.exe` | yes | no | known-good | Latest generated output |
| `hello_m8.exe` | `Experiments\M8_AST_Codegen` | M8 | generated output | Shows M8 message | none | MessageBox + exit 0 | `.\hello_m8.exe` | yes | no | known-good | Historical output |
| `arqc_m5.exe` | `Experiments\M5_CLI_Minimal` | M5 | compiler stage | Minimal CLI generator | `hello_m5.arq` | `hello_m5.exe` | `.\arqc_m5.exe hello_m5.arq` | yes | no | known-good | With no args exits non-zero |
| `hello_m5.exe` | `Experiments\M5_CLI_Minimal` | M5 | generated output | Shows M5 message | none | MessageBox + exit 0 | `.\hello_m5.exe` | yes | no | known-good | Regenerated by M5 CLI |
| `arqen_generator_m4c.exe` | `Experiments\M4C_StrictArqReader` | M4C | bootstrap helper | Reads strict `.arq`, writes PE | `input\hello_m4c.arq` | `output\generated_hello_m4c.exe` | `.\arqen_generator_m4c.exe` | yes | no | known-good | Strict reader, not full parser |
| `generated_hello_m4c.exe` | `Experiments\M4C_StrictArqReader\output` | M4C | generated output | Shows M4C message | none | MessageBox + exit 0 | `.\generated_hello_m4c.exe` | yes | no | known-good | Historical output |
| `arqen_generator_m4b.exe` | `Experiments\M4B_TemplatePatch` | M4B | bootstrap helper | Patches template message | fixed template | `output\generated_hello_m4b.exe` | `.\arqen_generator_m4b.exe` | yes | no | known-good | No real parser |
| `generated_hello_m4b.exe` | `Experiments\M4B_TemplatePatch\output` | M4B | generated output | Shows M4B message | none | MessageBox + exit 0 | `.\generated_hello_m4b.exe` | yes | no | known-good | Historical output |
| `arqen_generator_m4a.exe` | `Experiments\M4A_StaticExeWriter` | M4A | bootstrap helper | Writes known MessageBox PE bytes | none | `output\generated_hello.exe` | `.\arqen_generator_m4a.exe` | yes | no | known-good | First executable that creates an exe |
| `generated_hello.exe` | `Experiments\M4A_StaticExeWriter\output` | M4A | generated output | Shows M4A/M2 message | none | MessageBox + exit 0 | `.\generated_hello.exe` | yes | no | known-good | Historical output |
| `arqen_m2_messagebox_v2_fixed_messagebox_call.exe` | `Experiments\M2_MessageBoxW` | M2 | generated output | Calls MessageBoxW then ExitProcess | none | MessageBox + exit 0 | `.\arqen_m2_messagebox_v2_fixed_messagebox_call.exe` | yes | no | known-good | Passing M2 |
| `arqen_m1_exitprocess_v3_fixed_text_flags.exe` | `Experiments\M1_ExitProcess` | M1 | generated output | Calls ExitProcess(0) | none | exit 0 | `.\arqen_m1_exitprocess_v3_fixed_text_flags.exe` | yes | no | known-good | Passing M1 |

## Partial Tools

| File | Path | Milestone | Category | Does | Inputs | Outputs | Command | Standalone | Node required | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `arqen_generator_m4d_errors.exe` | `Experiments\M4D_Errors` | M4D | bootstrap helper | Detects missing message | bad M4D source | `arqen_error.txt` | `.\arqen_generator_m4d_errors.exe` | yes | no | partial | M4D not fully complete |
| `arqen_generator_m4d_missing_title.exe` | `Experiments\M4D_Errors` | M4D | bootstrap helper | Detects missing title | bad M4D source | `arqen_error.txt` | `.\arqen_generator_m4d_missing_title.exe` | yes | no | partial | Single-case variant |
| `arqen_generator_m4d_missing_exit.exe` | `Experiments\M4D_Errors` | M4D | bootstrap helper | Detects missing exit | bad M4D source | `arqen_error.txt` | `.\arqen_generator_m4d_missing_exit.exe` | yes | no | partial | Single-case variant |
| `arq_parser_m7a.exe` | `Experiments\M7_AST_Minimal` | M7A | compiler stage | Fixed-format AST probe | `hello_m7.arq` | `hello_m7.ast.txt` | `.\arq_parser_m7a.exe` | yes | no | obsolete | Superseded by M7B |

## Archived Broken Artifacts

| File | Path | Milestone | Category | What happened | Standalone | Node required | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `arqen_m1_exitprocess.exe` | `Experiments_Archive_FailedArtifacts\M1_ExitProcess` | M1 | broken | Early M1 failed with access violation/import issue | yes | no | broken | Kept for history only |
| `arqen_m1_exitprocess_v2.exe` | `Experiments_Archive_FailedArtifacts\M1_ExitProcess` | M1 | broken | Entry bytes existed but `.text` flags were wrong | yes | no | broken | Kept for history only |
| `arqen_m2_messagebox.exe` | `Experiments_Archive_FailedArtifacts\M2_MessageBoxW` | M2 | broken | Early M2 called wrong address / hint-name path | yes | no | broken | Kept for history only |

## Codex Bootstrap Emitters

These are outside the project repo folder by design:

```text
C:\Users\Sqweek\Documents\Arqen\Codex
```

| File | Path | Milestone | Category | Does | Inputs | Outputs | Command | Standalone | Node required | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `emit_m10.js` | `C:\Users\Sqweek\Documents\Arqen\Codex` | M10 | bootstrap helper | Emits/patches M10 lexer, parser, codegen artifacts | previous templates | M10 `.exe` tools | `node emit_m10.js` | no | yes | known-good | Temporary, not final compiler |
| `emit_m9b.js` | `C:\Users\Sqweek\Documents\Arqen\Codex` | M9B | bootstrap helper | Emits M9B lexer/parser artifacts | M6C template | M9B `.exe` tools | `node emit_m9b.js` | no | yes | known-good | Temporary |
| `emit_m9.js` | `C:\Users\Sqweek\Documents\Arqen\Codex` | M9 | bootstrap helper | Emits M9 lexer/parser artifacts | M6C template | M9 `.exe` tools | `node emit_m9.js` | no | yes | known-good | Temporary |
| `emit_m8.js` | `C:\Users\Sqweek\Documents\Arqen\Codex` | M8 | bootstrap helper | Emits M8 lexer/parser/codegen artifacts | M7B/M2 templates | M8 `.exe` tools | `node emit_m8.js` | no | yes | known-good | Temporary |
| `emit_m7b.js` | `C:\Users\Sqweek\Documents\Arqen\Codex` | M7B | bootstrap helper | Emits M7B lexer/parser artifacts | M6C template | M7B `.exe` tools | `node emit_m7b.js` | no | yes | known-good | Temporary |
| `emit_m6d.js` | `C:\Users\Sqweek\Documents\Arqen\Codex` | M6D | bootstrap helper | Emits M6D lexer error artifact | M6C template | `arq_lexer_m6d.exe` | `node emit_m6d.js` | no | yes | known-good | Temporary |

## Safe Default

If you only want the latest working pipeline, use:

```powershell
cd C:\Users\Sqweek\Documents\Arqen\Arqen
.\Tools\arqc_m10g.exe .\Samples\hello_m10.arq
.\Build\EXE\hello_m10.exe
```

Current M10I outputs:

```text
Build\Tokens\hello_m10.tokens
Build\AST\hello_m10.ast
Build\IR\hello_m10.arqir
Build\EXE\hello_m10.exe
Build\Manifests\hello_m10.manifest.txt
Build\Logs\hello_m10.build.log
```

Backend-only bootstrap test:

```powershell
.\Tools\arqc_m10g.exe --backend-only .\Build\IR\hello_m10.arqir -o .\Build\EXE\hello_m10_from_ir.exe
```

The old M10 manual stages remain available for debugging.

## M18A Hardening Tools

| File | Path | Milestone | Category | Does | Inputs | Outputs | Command | Standalone | Node required | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `validate_repo_hygiene.ps1` | `Tools` | M18A | validator | Checks line-ending policy, ignore rules, required hardening tools, and tracked junk guards | `.gitattributes`, `.gitignore`, git index | `Build\Generated\repo_hygiene_validation.txt` | `.\Tools\validate_repo_hygiene.ps1` | yes | no | active | Prevents invisible repo rot before style/DX12 |
| `validate_backend_capabilities.ps1` | `Tools` | M18A | validator | Checks supported/reserved backend operations and artifact verifier coverage | backend config + backend helper | `Build\Generated\backend_capability_validation.txt` | `.\Tools\validate_backend_capabilities.ps1` | yes | no | active | Keeps wrapper/backend capabilities aligned |
| `generate_error_code_registry.ps1` | `Tools` | M18A | generator | Scans compiler/tools/docs for error code references | `Tools`, `Docs` | `Build\Generated\error_code_registry.txt` | `.\Tools\generate_error_code_registry.ps1` | yes | no | active | Generated registry, not hand-maintained truth |
| `validate_command_test_coverage.ps1` | `Tools` | M18A | validator | Ensures every command test has expected mapping and valid/invalid coverage | `Tests\CommandTests` | `Build\Generated\command_test_coverage_validation.txt` | `.\Tools\validate_command_test_coverage.ps1` | yes | no | active | Catches orphaned tests and missing expected entries |
## M18B boundary / DX12 readiness tools

```text
Tools/generate_runtime_action_registry.ps1
Tools/validate_ir_contract.ps1
Tools/validate_wrapper_cache_contract.ps1
Tools/validate_dx12_readiness.ps1
Tools/validate_backend_contract_docs.ps1
```

These tools are fast static/contract checks. They do not implement DX12; they protect the boundary before DX12 work starts.
- `Tools/validate_parser_split.ps1` - validates the M18FG parser extraction/split boundary.

## M18H/M18I/M18J pre-DX12 hardening tools

| File | Path | Milestone | Category | Does | Inputs | Outputs | Command | Standalone | Node required | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `run_test_slice.ps1` | `Tools` | M18H | test runner | Runs selected command-test folders and tooling groups, including changed-file slices | `Tests\CommandTests`, tools, git diff | `Build\Logs\test_slice.last.txt` | `.\Tools\run_test_slice.ps1 -Group m18h` | yes | no | active | Includes untracked-file detection and fails no-match case filters |
| `validate_test_slice.ps1` | `Tools` | M18H | validator | Checks selective runner safety guarantees | `Tools\run_test_slice.ps1` | console output | `.\Tools\validate_test_slice.ps1` | yes | no | active | Prevents false-green slices |
| `validate_strict_ir.ps1` | `Tools` | M18I | validator | Exercises backend-only strict IR rejection cases | `Tools\arqc_m10g.exe`, generated IR samples | `Build\Temp\strict_ir` | `.\Tools\validate_strict_ir.ps1` | yes | no | active | Requires built driver exe |
| `validate_keyword_registry.ps1` | `Tools` | M18J | validator | Compares spec keyword registry against lexer keywords and reserved runtime/DX12 docs | `Specs\Commands`, `Lexer.cs`, docs | `Build\Generated\keyword_registry.txt` | `.\Tools\validate_keyword_registry.ps1` | yes | no | active | Catches forgotten lexer keywords before style/DX12 grammar work |
| `validate_parser_statement_map.ps1` | `Tools` | M18J | validator | Validates generated parser statement map and core dispatch coverage | parser split, specs, tests | `Build\Generated\parser_statement_map.txt` | `.\Tools\validate_parser_statement_map.ps1` | yes | no | active | Warnings are allowed for older gaps; missing specs fail |
