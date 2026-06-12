# Arqen Byte Zero Milestones

## Milestone 0: Empty Valid PE

Goal:

- Windows recognizes the file as a valid Windows x64 PE executable.

It does not need useful behavior yet.

Verification:

- PE-bear opens it.
- Machine is AMD64.
- Optional header is PE32+.
- Section table is readable.
- Windows does not reject it as invalid format.

## Milestone 1: ExitProcess Only

Status:

```text
PASSED, M6B LEXEMES PASSED
```

Goal:

- Program starts.
- Program calls `ExitProcess(0)`.
- Program exits cleanly.

Requirements:

- valid `.text`
- valid `.idata`
- import `kernel32.dll`
- import `ExitProcess`
- entry point points into `.text`
- Windows x64 calling convention obeyed

Verification:

- no crash
- exit code `0`
- x64dbg reaches entry point
- import visible in Dependencies or PE-bear

Current byte checklist:

- `M1_BYTE_CHECKLIST.md`

Current experiment log:

- `Experiments/M1_ExitProcess/EXPERIMENT_LOG.md`

Passing executable:

- `Experiments/M1_ExitProcess/arqen_m1_exitprocess_v3_fixed_text_flags.exe`

Observed PowerShell exit code:

```text
0
```

## Milestone 2: MessageBoxW

Status:

```text
PASSED
```

Goal:

- Program displays a message box.
- After OK, program exits cleanly.

New requirements:

- import `user32.dll`
- import `MessageBoxW`
- UTF-16 text string
- UTF-16 caption string
- four-argument Windows x64 call setup

Verification:

- message box appears
- OK closes it
- process exits cleanly

Current byte checklist:

- `M2_BYTE_CHECKLIST.md`

Passing executable:

- `Experiments/M2_MessageBoxW/arqen_m2_messagebox_v2_fixed_messagebox_call.exe`

Observed PowerShell exit code:

```text
0
```

## Milestone 3: Conceptual `.arq`

Status:

```text
PASSED
```

Goal:

- Define a tiny source format without implementing a parser yet.

Example:

```text
program Hello:
    show message "Hello from Arqen"
    exit 0
```

Current spec:

- `Specs/Language/M3_MINIMAL_SOURCE_FORMAT.md`

Current sample:

- `Samples/hello_message.arq`

## Milestone 4: First Generator

Status:

```text
M4A PASSED, M4B PASSED, M4C PASSED, M4D PARTIAL PASS
```

Goal:

- A future `arqc` writes the same bytes as the manually understood MessageBoxW executable.

Important:

- This comes after the manual layout is understood.
- The generator writes PE bytes.
- It is not a full compiler yet.

Current split:

- M4A: static EXE writer - PASSED
- M4B: template + fixed message patch - PASSED
- M4C: strict `.arq` reader - PASSED
- M4D: clear `.arq` errors - PARTIAL PASS

Current plan:

- `M4_STATIC_EXE_WRITER_PLAN.md`

Current experiment:

- `Experiments/M4A_StaticExeWriter/EXPERIMENT_LOG.md`

M4A result:

```text
arqen_generator_m4a.exe -> output/generated_hello.exe
generated_hello.exe matches M2 bytes
generated_hello.exe exits with 0
```

M4B result:

```text
arqen_generator_m4b.exe -> output/generated_hello_m4b.exe
message patched to "Hello from M4B"
generated_hello_m4b.exe exits with 0
```

M4C result:

```text
arqen_generator_m4c.exe reads input/hello_m4c.arq
message extracted as "Hello from M4C"
generated_hello_m4c.exe exits with 0
```

M4D-A004 result:

```text
missing message -> arqen_error.txt
generator exits with 4
```

M4D additional results:

```text
missing title -> arqen_error.txt, exit 3
missing exit -> arqen_error.txt, exit 5
```

Post-M4 roadmap:

- `POST_M4_ROADMAP.md`

## Milestone 5: Minimal CLI

Status:

```text
PASSED
```

Goal:

- `arqc_m5.exe hello_m5.arq` writes `hello_m5.exe`.
- This is a CLI milestone, not the later token-stream parser milestone.

Supported source:

```text
program Name:
    show message "text"
    exit 0
```

M5 CLI result:

```text
arqc_m5.exe hello_m5.arq
-> hello_m5.exe
-> MessageBoxW "Hello from M5!"
-> exit 0
```

Experiment:

- `Experiments/M5_CLI_Minimal/EXPERIMENT_LOG.md`

## Milestone 6: Lexer v1

Status:

```text
PASSED
```

Result:

```text
hello_m6.arq -> hello_m6.tokens.txt
```

Token stream:

```text
KEYWORD IDENT NEWLINE KEYWORD STRING NEWLINE KEYWORD STRING NEWLINE KEYWORD INT NEWLINE EOF
```

M6B token stream:

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

M6C token stream:

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

M6D lexer errors:

```text
valid_ok              -> exit 0
unknown_character     -> L001 line 1 col 1, exit 1
unterminated_string   -> L002 line 1 col 7, exit 2
invalid_integer       -> L003 line 1 col 6, exit 3
unexpected_control    -> L004 line 1 col 9, exit 4
```

Experiment:

- `Experiments/M6_LexerV1/EXPERIMENT_LOG.md`

Completion plan:

- `M6_LEXER_COMPLETION_PLAN.md`

Note:

- M6A and M6B passed as probes.
- M6C passed with token values, line/column, and stable token dump.
- M6D passed with lexer errors including line/column.
- M6 is complete enough for M7B parser-from-token-stream.

## Milestone 7: Minimal AST + Semantic Check

Status:

```text
PASSED, M7B TOKEN STREAM PARSER PASSED
```

Result:

```text
hello_m7.arq -> hello_m7.ast.txt
Semantic: OK
```

Experiment:

- `Experiments/M7_AST_Minimal/EXPERIMENT_LOG.md`

## Milestone 7B: Parser on Real Token Stream

Status:

```text
PASSED
```

Goal:

- Replace fixed-format source parsing with parser logic based on M6 token dump.
- Do not scan `.arq` source directly.
- Do not generate an executable yet.

Input:

```text
program "Hello"
title "Arqen Byte Zero"
message text "Hello from Arqen"
exit 0
end program "Hello"
```

Pipeline:

```text
hello_m7b.arq
-> arq_lexer_m7b_tokens.exe
-> hello_m7b.tokens.txt
-> arq_parser_m7b.exe
-> hello_m7b.ast.txt
```

AST:

```text
Program:
    name: Hello
    title: Arqen Byte Zero
    message: Hello from Arqen
    exit_code: 0
Semantic: OK
```

Pass/fail:

```text
LEX_EXIT: 0
PARSE_EXIT: 0
BAD_PARSE_EXIT: 1
```

Experiment:

- `Experiments/M7B_TokenStreamParser/EXPERIMENT_LOG.md`

Known limitations:

- strict M7B grammar only
- generic parser error `P001`
- no codegen

## Milestone 8: Codegen From AST

Status:

```text
PASSED
```

Goal:

- Use AST as the source for PE generation.
- Keep malformed source from reaching codegen.
- Generate a MessageBoxW executable from the AST.

Pipeline:

```text
hello_m8.arq
-> arq_lexer_m8_tokens.exe
-> hello_m8.tokens.txt
-> arq_parser_m8.exe
-> hello_m8.ast.txt
-> arqc_m8.exe
-> hello_m8.exe
```

Command:

```text
.\arq_lexer_m8_tokens.exe
.\arq_parser_m8.exe
.\arqc_m8.exe
```

AST:

```text
Program:
    name: Hello
    title: Arqen Byte Zero
    message: Hello from M8
    exit_code: 0
Semantic: OK
```

Generated EXE:

```text
MessageBoxW title: Arqen Byte Zero
MessageBoxW text: Hello from M8
RUN_DONE: True
EXIT: 0
```

Pass/fail:

```text
LEX_EXIT: 0
PARSE_EXIT: 0
GEN_EXIT: 0
BAD_PARSE_EXIT: 1
bad source produced no AST and no EXE
```

Experiment:

- `Experiments/M8_AST_Codegen/EXPERIMENT_LOG.md`

Known limitations:

- three explicit tools, not a single automatic driver yet
- codegen reads `hello_m8.ast.txt`
- local PE template file is required
- exit code is still only `0`
- no M9+ language features

## Bootstrap Emitter Boundary

Status:

```text
DOCUMENTED
```

Temporary Codex-side byte emitters:

```text
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m6d.js
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m7b.js
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m8.js
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m9.js
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m9b.js
C:\Users\Sqweek\Documents\Arqen\Codex\emit_m10.js
```

These JavaScript files may patch or emit PE files during bootstrap, but they are not the final Arqen compiler implementation.

Node.js is required only to build or refresh the bootstrap `.exe` artifacts. The milestone artifacts are the generated `.exe` files, and those run standalone as Windows PE executables.

Standalone verification:

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
```

Current doc:

- `Docs\BOOTSTRAP_BYTE_EMITTERS.md`

## Milestone 9: Let Variables

Status:

```text
PASSED
```

Goal:

- Add initial `let` variable declarations.
- Support string/text and int literal values.
- Emit `Let` nodes in AST.
- Keep this milestone parser-only; no message expressions and no codegen changes.

Input:

```text
program "Hello"
let name be "Sqweek"
let number be 0
title "Arqen Byte Zero"
message text "Hello from Arqen"
exit 0
end program "Hello"
```

Pipeline:

```text
hello_m9.arq
-> arq_lexer_m9_tokens.exe
-> hello_m9.tokens.txt
-> arq_parser_m9.exe
-> hello_m9.ast.txt
```

Command:

```text
.\arq_lexer_m9_tokens.exe
.\arq_parser_m9.exe
```

AST:

```text
Program:
    name: Hello
    Let:
        name: name
        type: text
        value: Sqweek
    Let:
        name: number
        type: int
        value: 0
    title: Arqen Byte Zero
    message: Hello from Arqen
    exit_code: 0
Semantic: OK
```

Pass/fail:

```text
LEX_EXIT: 0
PARSE_EXIT: 0
AST_MATCH: True
DUP_PARSE_EXIT: 1
UNKNOWN_PARSE_EXIT: 1
```

Experiment:

- `Experiments\M9_LetVariables\EXPERIMENT_LOG.md`

Known limitations:

- strict initial variables `name` and `number`
- general symbol table not complete yet
- no variable references or message expressions yet
- no codegen changes

## Milestone 9B: Let Variables Complete

Status:

```text
PASSED
```

Goal:

- Support initial `let <identifier> be <literal>` declarations.
- Infer type from text, int, and bool literals.
- Emit a `Variables:` AST section.
- Provide clear errors for common `let` failures.
- Do not add expressions, if/else, or codegen changes.

Input:

```text
program "Hello"

let name be "Sqweek"
let number be 0
let active be true

title "Arqen Byte Zero"
message text "Hello from M9"
exit 0

end program "Hello"
```

Pipeline:

```text
hello_m9b.arq
-> arq_lexer_m9b_tokens.exe
-> hello_m9b.tokens.txt
-> arq_parser_m9b.exe
-> hello_m9b.ast.txt
```

Command:

```text
.\arq_lexer_m9b_tokens.exe
.\arq_parser_m9b.exe
```

AST:

```text
Program:
    name: Hello

Variables:
    name: text = Sqweek
    number: int = 0
    active: bool = true

title: Arqen Byte Zero
message: Hello from M9
exit_code: 0

Semantic: OK
```

Pass/fail:

```text
LEX_EXIT: 0
PARSE_EXIT: 0
AST_MATCH: True
duplicate_name       -> Error S001, no AST
missing_value        -> Error P012, no AST
unknown_variable     -> Error S003, no AST
unknown_type         -> Error T001, no AST
invalid_name         -> Error S002, no AST
unterminated_string  -> Error L002, no AST
```

Experiment:

- `Experiments\M9B_LetVariablesComplete\EXPERIMENT_LOG.md`

Known limitations:

- bool literal is tokenized as `KEYWORD(true)` for now
- `end program "Hello"` is present but not fully validated by M9B parser yet
- symbol table is still target-shaped
- no M10 expressions yet

## M10 - Simple Expressions

Status: PASSED

Goal:

- Add expression support for `message text`.
- Support string literals, variable references, and binary `+`.
- Fold supported text expressions at compile time.
- Generate a working MessageBox `.exe` from the folded AST message.

Input:

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

Pipeline:

```text
m10.arq
-> arq_lexer_m10_tokens.exe
-> m10.tokens.txt
-> arq_parser_m10.exe
-> m10.ast.txt
-> arqc_m10.exe
-> m10.exe
```

Command:

```text
.\arq_lexer_m10_tokens.exe
.\arq_parser_m10.exe
.\arqc_m10.exe
.\m10.exe
```

Pass/fail:

```text
LEX_EXIT: 0
PARSE_EXIT: 0
CODEGEN_EXIT: 0
M10_EXE_EXIT: 0
valid_name_concat      -> PASS
valid_string_concat    -> PASS
unknown_variable       -> Error S010, no exe
type_mismatch_bool     -> Error S011, no exe
message_expects_text   -> Error S012, no exe
broken_plus            -> Error P011, no exe
```

Experiment:

- `Experiments\M10_SimpleExpressions\EXPERIMENT_LOG.md`

Known limitations:

- `let` values are still literals only
- parser is still target-shaped for the M10 fixtures
- only `message text` accepts expressions
- `+` is text concatenation only
- no if/else, functions, runtime string allocation, math, UI, or window syntax

## M10F - Foundation Hardening

Status: PASSED

Goal:

- Stabilize the current M10 compiler pipeline.
- Add snapshot safety.
- Document tools, token dumps, AST dumps, error codes, and command implementation rules.
- Add a repeatable smoke test harness.
- Archive old failed artifacts without deleting them.
- Do not add new language syntax.

Created:

```text
Docs\TOOL_MAP.md
Docs\TOKEN_DUMP_FORMAT.md
Docs\AST_DUMP_FORMAT.md
Docs\COMMAND_IMPLEMENTATION_TEMPLATE.md
Docs\ERROR_CODES.md
Docs\SINGLE_ARQC_DRIVER_PLAN.md
Tools\run_all_tests.ps1
Samples\hello_m10.arq
Samples\README.md
Experiments_Archive_FailedArtifacts
```

Git:

```text
Initial snapshot: M10 working compiler pipeline
Remote: https://github.com/Sqweek858/Arqen.git
```

Pass/fail:

```text
Tools\run_all_tests.ps1 -> Total: 29/29 passed
M10 fixtures -> 6/6 passed
```

Known limitations:

- M10 parser is still target-shaped
- token dump migration is documented but not implemented
- single `arqc` driver is planned but not implemented
- Codex emitters remain temporary bootstrap tooling

## M10G - Core Pipeline Upgrade

Status: PASSED

Goal:

- Provide a single driver workflow.
- Keep M10 language behavior unchanged.
- Add stable token and AST formats for the new driver path.
- Add predictable `Build` folder output.
- Support arbitrary variable names in the M10 grammar.

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

Stage result:

```text
[LEX] PASS -> Build\Tokens\hello_m10.tokens
[PARSE] PASS -> syntax OK
[SEMANTIC] PASS -> Build\AST\hello_m10.ast
[CODEGEN] PASS -> Build\EXE\hello_m10.exe
[BUILD] PASS
```

Stable token format:

```text
TYPE|VALUE|LINE|COLUMN
```

Stable AST format:

```text
PROGRAM|Hello
LET|name|text|Sqweek
TITLE|Arqen Byte Zero
MESSAGE|Hello, Sqweek
MESSAGE_EXPR|plus(str("Hello, "),var(name))
EXIT|0
SEMANTIC|OK
```

Pass/fail:

```text
Tools\run_all_tests.ps1 -> Total: 39/39 passed
M10G arbitrary variables -> PASS
M10G error routing -> PASS
M10 legacy smoke -> PASS
```

Experiment:

- `Experiments\M10G_CorePipelineUpgrade\EXPERIMENT_LOG.md`

Known limitations:

- driver is a bootstrap .NET tool, not final self-hosted compiler
- generated PE still uses the M8 MessageBox template
- no new language syntax was added
- `let` values are still literals only
- `message text` remains the only expression-enabled field

## M10H - Command System Upgrade

Status: PASSED

Goal:

- Create infrastructure for adding future Arqen commands predictably.
- Keep current language behavior unchanged.
- Add command registry, machine-readable command specs, scaffold generator, command tests, and system contracts.

Created:

```text
Docs\COMMAND_REGISTRY.md
Docs\COMMAND_IMPLEMENTATION_CHECKLIST.md
Docs\PARSER_RECOVERY_PLAN.md
Docs\SYMBOL_TABLE_FORMAT.md
Docs\EXPRESSION_SYSTEM_M10.md
Docs\CODEGEN_CONTRACT_M10.md
Specs\Commands\*.command.txt
Tools\new_command_scaffold.ps1
Tests\CommandTests\...
Experiments\CommandDrafts\BlendMixToCode\...
```

Command scaffold:

```powershell
.\Tools\new_command_scaffold.ps1 BlendMixToCode
```

Pass/fail:

```text
Tools\run_all_tests.ps1 -> Total: 52/52 passed
Command tests -> PASS
M10/M10G regression -> PASS
```

Known limitations:

- specs do not generate compiler code yet
- command tests use the M10G driver
- BlendMixToCode is only a draft, not implemented
- no new language syntax was added

## M10I - Backend Architecture

Status: PASSED

Goal:

- Insert an explicit IR and backend boundary into the current compiler pipeline.
- Keep language behavior unchanged.
- Produce ARQIR v0 before backend generation.
- Allow backend-only artifact generation from `.arqir`.

Pipeline:

```text
Source
-> Lexer
-> Tokens
-> Parser
-> AST
-> Semantic
-> IR
-> Backend
-> Artifact
```

Command:

```powershell
.\Tools\arqc_m10g.exe .\Samples\hello_m10.arq
.\Tools\arqc_m10g.exe --backend-only .\Build\IR\hello_m10.arqir -o .\Build\EXE\hello_m10_from_ir.exe
```

Created:

```text
IR\Formats\ARQIR_V0.md
IR\Samples\hello_m10.arqir
Docs\IR_FORMAT_ARQIR_V0.md
Docs\BACKEND_ARCHITECTURE.md
Docs\BACKEND_CONTRACT.md
Backends\WindowsX64PE\README.md
Backends\WindowsX64PE\PE_BACKEND_CONTRACT.md
Experiments\M10I_BackendArchitecture\EXPERIMENT_LOG.md
Build\IR\.gitkeep
Build\Manifests\.gitkeep
Build\Diagnostics\*\.gitkeep
```

Output:

```text
Build\Tokens\hello_m10.tokens
Build\AST\hello_m10.ast
Build\IR\hello_m10.arqir
Build\EXE\hello_m10.exe
Build\EXE\hello_m10_from_ir.exe
Build\Manifests\hello_m10.manifest.txt
Build\Manifests\hello_m10_from_ir.manifest.txt
```

Stage result:

```text
[LEX] PASS -> Build\Tokens\hello_m10.tokens
[PARSE] PASS -> syntax OK
[SEMANTIC] PASS -> Build\AST\hello_m10.ast
[IR] PASS -> Build\IR\hello_m10.arqir
[BACKEND] PASS -> Build\EXE\hello_m10.exe
[ARTIFACT] PASS -> Build\Manifests\hello_m10.manifest.txt
[BUILD] PASS
```

Pass/fail:

```text
Tools\run_all_tests.ps1 -> Total: 61/61 passed
Backend-only from ARQIR -> PASS
Generated backend-only EXE -> PASS
M10/M10G/M10H regressions -> PASS
```

Known limitations:

- driver is still a bootstrap .NET tool, not the final self-hosted compiler
- backend still uses the M8 MessageBox PE template
- ARQIR v0 supports only `show_message` and `exit`
- backend supports only exit code `0`
- no if/else, blend mix implementation, functions, loops, UI/window/style, or new operators were added

## M22 - DX12 Mini Scene

M22A-M22I turns the M21 animated triangle into a generated crystal mini scene: bible/docs, deterministic crystal sample generator, larger vertex-buffer samples, M22I wrapper, keep-open runtime mode, Escape/Q close handling, manifest/config markers, validation, and the official `dx12_crystal_scene_m22i.arq` demo.

## M23 - DX12 Real Scene Objects and Multi-Draw

- M23A: documents the public object syntax: `define object called "CrystalA"`.
- M23B: emits real object metadata: `DX12_OBJECT`, `DX12_OBJECT_BIND`, `DX12_DRAW_OBJECT`.
- M23C: lowers multiple object draw calls into native draw-call tables and runtime `DrawInstanced` loops.

## M24/M25/M26 - DX12 Runtime Scene Controls

- M24 adds per-object transform metadata and runtime vertex-buffer transform application.
- M25 adds orthographic camera metadata and runtime camera application.
- M26 adds keyboard input runtime bindings for camera movement/reset and animation toggle.
- Official sample: `Samples\DX12\dx12_interactive_camera_scene_m26c.arq`.

## M27 - DX12 Perspective Camera + Depth Buffer

M27A defines the real 3D/depth/perspective camera contract and documents the public syntax. M27B adds native DX12 depth buffer support through a DSV heap, D32_FLOAT depth resource, depth-stencil state, and per-frame depth clear. M27C lowers perspective camera metadata into generated config/manifest markers and provides the official perspective/depth runtime sample.

Public syntax added:

```arq
set camera "MainCamera" projection to perspective
set rotation of camera "MainCamera" to [0.0, 0.0, 0.0]
set field of view of camera "MainCamera" to 70 deg
set near plane of camera "MainCamera" to 0.1
set far plane of camera "MainCamera" to 100.0
```

Validation:

```powershell
.\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail
.\Tools\validate_m27_dx12_perspective_depth.ps1
.\Tools\build_m27c_dx12_perspective_depth_scene.ps1 -BuildNative -RunNative -KeepOpen
```

Boundary: no scene graph, no UI DX12, no mouse input, no materials/textures, no lighting, no mesh import, and no M27D/E in this milestone.


## M27D/M28A - Native Window Style + Box Primitive

- M27D adds a tiny native window style bridge through existing Arqen style blocks: `title bar color` and `title text color` for defined windows.
- M28A adds `define box called "CubeA"` as the first generated 3D primitive/object contract.
- Box primitives lower to generated 36-vertex position/color geometry and reuse the existing renderer/pipeline/object/draw/depth/perspective path.
- Official sample: `Samples\DX12\dx12_window_style_box_scene_m28a.arq`.

Validation:

```powershell
.\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail
.\Tools\validate_m27d_m28a_dx12_window_style_box.ps1
.\Tools\build_m28a_dx12_window_style_box_scene.ps1 -BuildNative -RunNative -KeepOpen
```

Boundary: no custom title bar, no DX12 UI, no scene graph, no lighting, no materials/textures, no mesh import, and no M28B/C in this milestone.

## M28B - DX12 full peripheral input

M28B adds mouse capture, mouse look, mouse buttons, mouse wheel, and Q/E vertical camera movement for the DX12 perspective scene path. It keeps the scope deliberately small: no key remapping, controller input, collision, physics, UI widgets, mouse picking, lighting, scene graph, or mesh import.
