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


## M20A DX12 bridge tools

| File | Path | Milestone | Category | Does | Inputs | Outputs | Command | Standalone | Node required | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `validate_m20a_dx12_contract.ps1` | `Tools` | M20A | validator | Checks M20A DX12 bridge docs/source boundaries and verifies reserved capability flags remain unsupported | DX12 docs, runtime source, capability table | `Build\Generated\m20a_dx12_contract_validation.txt` | `.\Tools\validate_m20a_dx12_contract.ps1` | yes | no | active | Static contract guard for the first native DX12 bridge slice |
| `build_m20a_dx12_clear.ps1` | `Backends\DX12\Runtime` | M20A | native smoke builder | Builds the standalone DX12 clear smoke executable using MSVC and Windows SDK libs | DX12 runtime C++ source | `Build\EXE\m20a_dx12_clear_smoke.exe` | `.\Backends\DX12\Runtime\build_m20a_dx12_clear.ps1` | yes, from VS Developer shell | no | partial | Optional Windows-only runtime validation; not compiler feature support |

## M20B DX12 syntax tools

| File | Path | Milestone | Category | Does | Inputs | Outputs | Command | Standalone | Node required | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `validate_m20b_dx12_syntax_contract.ps1` | `Tools` | M20B | validator | Checks DX12 metadata syntax docs, parser/AST/IR wiring, tests, and unsupported capability boundary | compiler source, specs, tests, docs, capability table | `Build\Generated\m20b_dx12_syntax_contract_validation.txt` | `.\Tools\validate_m20b_dx12_syntax_contract.ps1` | yes | no | active | Static contract guard for M20B renderer metadata syntax |
## M20C DX12 style bridge tools

| File | Path | Milestone | Category | Does | Inputs | Outputs | Command | Standalone | Node required | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `validate_m20c_dx12_style_bridge_contract.ps1` | `Tools` | M20C | validator | Checks DX12 style-derived clear metadata docs, parser/AST/IR wiring, tests, and unsupported capability boundary | compiler source, specs, tests, docs, capability table | `Build\Generated\m20c_dx12_style_bridge_contract_validation.txt` | `.\Tools\validate_m20c_dx12_style_bridge_contract.ps1` | yes | no | active | Static contract guard for style-derived renderer clear metadata |

## M20D/M20E0 DX12 validation tools

- `Tools/validate_m20d_dx12_semantic_contract.ps1` checks renderer symbol conflict and parenting semantic hardening.
- `Tools/validate_m20e0_dx12_clear_readiness.ps1` checks derived `DX12_CLEAR_READY` metadata wiring and capability boundaries.
- `Tools/run_test_slice.ps1 -Group m20d` runs the DX12 command folder plus the M20A/M20B/M20C/M20D/M20E0 validators.


## M20E1 DX12 lowering tools

| File | Path | Milestone | Category | Does | Inputs | Outputs | Command | Standalone | Node required | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `lower_m20e1_dx12_clear_from_ir.ps1` | `Tools` | M20E1 | lowerer | Consumes `DX12_CLEAR_READY` metadata and window actions from ARQIR to generate native DX12 clear bridge config | `.arqir` file | `Build\M20E1\dx12_clear_manifest.generated.txt`, `Build\M20E1\dx12_clear_config.generated.h` | `.\Tools\lower_m20e1_dx12_clear_from_ir.ps1 -IrPath .\Build\IR\dx12_clear_m20e1.arqir` | yes | no | experimental | Explicit lowering only, does not promote DX12 capability |
| `build_m20e1_dx12_clear_from_ir.ps1` | `Backends\DX12\Runtime` | M20E1 | native smoke builder | Runs the M20E1 lowerer, generates a C++ smoke source, and builds it with MSVC/DX12 libs | `.arqir` file, DX12 bridge source | `Build\EXE\m20e1_dx12_clear_from_ir.exe` | `.\Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1 -IrPath .\Build\IR\dx12_clear_m20e1.arqir` | yes, from VS Developer shell | no | optional | Manual Windows-only runtime validation; not part of standard regression |
| `validate_m20e1_dx12_lowering_contract.ps1` | `Tools` | M20E1 | validator | Checks M20E1 lowerer, fixtures, docs, generated manifest/header behavior, and unsupported capability boundary | lowering fixtures, docs, tools, capability table | `Build\Generated\m20e1_dx12_lowering_validation.txt` | `.\Tools\validate_m20e1_dx12_lowering_contract.ps1` | yes | no | active | Static/offline guard for experimental clear lowering |
## M20F/M20G DX12 tools

| File | Path | Milestone | Category | Does | Inputs | Outputs | Command | Standalone | Node required | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `build_m20f_dx12_clear_smoke.ps1` | `Tools` | M20F | smoke wrapper | Compiles the official M20F DX12 sample and lowers clear-ready metadata into generated native bridge config | `Samples\DX12\dx12_clear_smoke_m20f.arq` | `Build\M20F\dx12_clear_manifest.generated.txt`, `Build\M20F\dx12_clear_config.generated.h` | `.\Tools\build_m20f_dx12_clear_smoke.ps1` | yes | no | active | Native build/run optional behind switches |
| `validate_m20f_dx12_clear_smoke_contract.ps1` | `Tools` | M20F | validator | Checks the M20F smoke wrapper, sample, docs, generated manifest/config markers, and unsupported capability boundary | docs, tools, sample, compiler output | `Build\Generated\m20f_dx12_clear_smoke_validation.txt` | `.\Tools\validate_m20f_dx12_clear_smoke_contract.ps1` | yes | no | active | Does not require native DX12 runtime |
| `validate_m20g_dx12_frame_syntax_contract.ps1` | `Tools` | M20G | validator | Checks frame metadata parser/AST/IR wiring, tests, docs, and unsupported capability boundary | compiler source, tests, docs, capability table | `Build\Generated\m20g_dx12_frame_syntax_validation.txt` | `.\Tools\validate_m20g_dx12_frame_syntax_contract.ps1` | yes | no | active | Frame syntax remains metadata-only |

## M20H/M20I DX12 tools

```text
Tools\validate_m20h_dx12_frame_lowering_contract.ps1
Tools\validate_m20i_dx12_native_smoke_polish_contract.ps1
Tools\build_m20i_dx12_frame_clear_smoke.ps1
```

M20H validates frame-aware lowering from `DX12_FRAME` metadata. M20I validates the frame-clear smoke wrapper and optional native build/run boundary.

## M21 shader/pipeline tools

```text
Tools/validate_m21a_shader_pipeline_bible.ps1 - validates M21 shader/pipeline docs/spec boundary.
Tools/validate_m21b_shader_pipeline_metadata.ps1 - validates M21B parser/AST/IR/strict-IR metadata surface.
```

## M21C/M21D DX12 tools

- `Tools/validate_m21c_vertex_draw_metadata.ps1` validates vertex buffer/draw metadata implementation and tests.
- `Tools/validate_m21d_dx12_triangle_smoke.ps1` validates the first-triangle lowering/smoke path without requiring native DX12 execution.
- `Tools/build_m21d_dx12_triangle_smoke.ps1` compiles the M21D Arqen sample and lowers it to generated native smoke config; `-BuildNative -Run` are optional/manual.

## M21E/M21F DX12 tools

- `Tools/validate_m21e_dx12_standalone_runtime.ps1` validates generated native executable diagnostics/fallback hooks without requiring native DX12 execution.
- `Tools/validate_m21f_dx12_frame_loop.ps1` validates fixed-frame triangle loop lowering/wrapper behavior without requiring native DX12 execution.
- `Tools/build_m21f_dx12_triangle_loop_smoke.ps1` compiles the M21D triangle sample and lowers it into `Build\M21F` with frame-loop config markers; `-BuildNative -Run` are optional/manual.

## M21G/M21H DX12 animation tooling

- `Tools\validate_m21g_constant_buffer_metadata.ps1` validates constant buffer syntax/metadata/native tint bridge markers.
- `Tools\validate_m21h_dx12_color_animation.ps1` validates color sequence animation metadata and animated triangle lowering.
- `Tools\build_m21h_dx12_animated_triangle_smoke.ps1` compiles/lowers the animated triangle sample and can optionally build/run native DX12.

## M21I/M21J DX12 color animation polish and hardening

- `Tools\build_m21i_dx12_color_animation_smoke_polish.ps1` wraps the M21H animated triangle path with explicit frame/fps/hold/out-dir/runtime knobs and generated M21I manifest/config markers.
- `Tools\validate_m21i_dx12_color_animation_smoke_polish.ps1` validates the M21I wrapper, runtime knob markers, docs, and unsupported capability boundary.
- `Tools\validate_m21j_dx12_color_animation_metadata_hardening.ps1` validates the M21J parser/lowerer hardening contract, invalid unbound animation test, docs/spec, and unsupported capability boundary.

## M22 DX12 mini scene tools

- `Tools\new_m22b_dx12_crystal_cluster_sample.ps1` generates deterministic crystal-cluster `.arq` samples using the existing DX12 vertex-buffer/draw syntax.
- `Tools\build_m22i_dx12_crystal_scene.ps1` compiles, lowers, and optionally builds/runs the official M22 crystal mini scene. It supports `-KeepOpen` for an indefinite native window.
- `Tools\validate_m22_dx12_mini_scene_contract.ps1` validates the M22 A-I docs, samples, generator, wrapper, keep-open lowerer/runtime markers, and unsupported DX12 capability boundary.
- `Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1` accepts `-KeepOpen` and emits generated native code with Escape/Q close handling.

## M23 DX12 real scene object tools

- `Tools\build_m23c_dx12_multi_object_scene.ps1` compiles, lowers, and optionally builds/runs the official M23C multi-object DX12 scene using `define object called "CrystalA"` and `draw "CrystalA"`.
- `Tools\validate_m23_dx12_scene_objects.ps1` validates M23A/M23B/M23C docs, parser/AST/IR markers, command tests, lowering markers, runtime draw-call support, and unsupported DX12 capability boundary.
- `Samples\DX12\dx12_multi_object_scene_m23c.arq` is the official object/multi-draw scene sample.
- `Samples\DX12\dx12_explicit_multi_draw_m23c.arq` covers the explicit low-level multi-draw syntax.

## M24/M25/M26 DX12 runtime scene tools

- `Tools\build_m26c_dx12_interactive_camera_scene.ps1` compiles, lowers, builds, and optionally runs the official M26 interactive scene using object transforms, an orthographic camera, and keyboard input.
- `Tools\validate_m24_m25_m26_dx12_runtime_scene.ps1` validates M24 transform metadata/runtime markers, M25 camera metadata/runtime markers, M26 keyboard metadata/runtime markers, generated config output, docs, samples, and runtime source integration.

## M27 DX12 perspective/depth tools

- `Tools\build_m27c_dx12_perspective_depth_scene.ps1` compiles, lowers, builds, and optionally runs the official M27C perspective/depth scene using `set camera "MainCamera" projection to perspective` plus FOV/near/far metadata.
- `Tools\validate_m27_dx12_perspective_depth.ps1` validates M27 parser/AST/IR/strict-IR contracts, lowerer markers, runtime depth-buffer/perspective hooks, native builder wiring, command tests, docs, and official sample.
- `Samples\DX12\dx12_perspective_depth_scene_m27c.arq` is the official perspective/depth smoke scene.
- `Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1` now passes generated M27 perspective camera and depth-enable config into `ArqenDx12TriangleWindowDesc` when native build is requested.


## M27D/M28A Native window style + box primitive tools

| File | Path | Milestone | Category | Does | Inputs | Outputs | Command | Standalone | Node required | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `validate_m27d_m28a_dx12_window_style_box.ps1` | `Tools` | M27D/M28A | validator | Checks native window style parser/lowering/DWM bridge plus box primitive parser/AST/IR/lowerer/docs/tests/sample | compiler source, lowerer, native builder, tests, docs, sample | `Build\Generated\m27d_m28a_dx12_window_style_box_validation.txt` | `.\Tools\validate_m27d_m28a_dx12_window_style_box.ps1` | yes | no | active | Runs wrapper compile/lower only; native DX12 run remains local/optional |
| `build_m28a_dx12_window_style_box_scene.ps1` | `Tools` | M27D/M28A | smoke wrapper | Compiles and lowers the official native-window-style + generated-box scene, optionally builds/runs native DX12 | `Samples\DX12\dx12_window_style_box_scene_m28a.arq` | `Build\M28A\dx12_clear_manifest.generated.txt`, `Build\M28A\dx12_clear_config.generated.h`, optional exe | `.\Tools\build_m28a_dx12_window_style_box_scene.ps1 -BuildNative -RunNative -KeepOpen` | yes | no | active | Requires rebuilt driver after parser changes |

## M28B DX12 full peripheral input

- `Tools/build_m28b_dx12_full_peripheral_input_scene.ps1` builds/lowers the official M28B sample and can optionally build/run native DX12.
- `Tools/validate_m28b_dx12_full_peripheral_input.ps1` validates parser, AST/IR, lowerer, runtime, wrapper, docs, sample, and command tests for M28B.

## M28C/M29A DX12 rotation + fake lighting

- `Tools/validate_m28c_m29a_dx12_rotation_light.ps1` validates M28C object rotation and M29A fake directional lighting contracts.
- `Tools/build_m29a_dx12_rotation3d_fake_light_scene.ps1` compiles/lowers/builds the official M29A scene.
- `Samples/DX12/dx12_rotation3d_fake_light_scene_m29a.arq` is the official sample.

- `Tools/validate_m29b_dx12_ue_style_viewport_navigation.ps1` - validates M29B UE-style RMB viewport navigation, camera-relative WASD/QE movement, cursor release, wrapper/sample/docs markers.
- `Tools/build_m29b_dx12_ue_style_viewport_navigation_scene.ps1` - builds/lowers/runs the official M29B DX12 viewport navigation sample.

## M29C DX12 object selector rotate

- `Tools/build_m29c_dx12_object_selector_rotate_scene.ps1` builds/lowers the official selector/rotate sample.
- `Tools/validate_m29c_dx12_object_selector_rotate.ps1` validates parser/model/IR/lowerer/runtime/docs/sample coverage for M29C.
