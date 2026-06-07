# M18H/M18I/M18J Pre-DX12 Hardening

This pass closes the main reliability gaps found after the compiler/frontend/backend/parser split.

## M18H - Repo and selective test runner hygiene

- `.gitattributes` and `.gitignore` are pinned to LF so the files that control line endings do not become line-ending noise themselves.
- `run_test_slice.ps1 -Changed` includes both tracked changes and untracked files.
- `run_test_slice.ps1 -Case` fails if a case filter matches no command tests.
- `flow`, `m18h`, `m18i`, and `m18j` groups exist for focused validation.

## M18I - Strict IR validation

ARQIR v0 is no longer treated as a loose key/value bag. The C# backend parser now rejects:

- unknown top-level IR line kinds
- duplicate `ARQIR`, `TARGET`, `CONST`, `ACTION`, or `ENTRY` where applicable
- `ACTION` without `id` or `op`
- missing `ENTRY`
- `ENTRY` references to missing actions
- unsupported backend actions such as reserved DX12 ops

The backend also validates actions against a C# supported-action gate, so direct `--backend-only` use cannot bypass the PowerShell wrapper capability checks.

## M18J - Keyword and parser registry hardening

- `validate_keyword_registry.ps1` verifies that command-spec keywords are recognized by the lexer.
- `validate_parser_statement_map.ps1` checks parser statement map generation and core dispatch wiring.
- DX12/runtime reserved actions stay documented but unsupported until real runtime/backend work lands.

## Why this matters before style/DX12

Style and DX12 will add new grammar, resources, runtime actions, and backend actions. These checks make it harder to accidentally get a false green state from missing test slices, loose IR parsing, or forgotten lexer keywords.
