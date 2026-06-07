# M18A DX12 Readiness Audit

This milestone hardens the compiler/tooling surface before style and DX12 work.

## Current green areas

- Command regression framework is strong and broad.
- Compile-time math coverage is extensive.
- The direct `arqc_m10g.exe` driver supports lexer, parser, semantic, IR, PE backend, file I/O, stdout, and basic window output.
- The wrapper/cache driver exists and records staged manifests, diagnostics, cache keys, and artifact state.

## M18A hardening added

- `.gitattributes` now pins C# and project file line endings so future patches do not pretend the whole compiler changed because of CRLF/LF chaos.
- `.gitignore` now blocks local publish/debug/patch artifacts from becoming accidental commits.
- `capabilities_v0.txt` now names real supported runtime/backend operations instead of hiding window support behind a stale generic `window|unsupported` entry.
- `WindowsX64PE.psm1` now recognizes window PE artifacts separately from MessageBox/stdout/file artifacts.
- Tooling validators now generate machine-readable reports under `Build/Generated`.
- Regression now includes wrapper-window build checks, not just direct-driver command tests.

## New tools

| Tool | Purpose |
| --- | --- |
| `Tools/validate_repo_hygiene.ps1` | Checks line-ending policy, ignore rules, required hardening tools, and tracked junk guards. |
| `Tools/validate_backend_capabilities.ps1` | Checks backend capability registry against known supported and reserved operations. |
| `Tools/generate_error_code_registry.ps1` | Scans source/tools/docs for error code references and writes a generated registry. |
| `Tools/validate_command_test_coverage.ps1` | Verifies every command test folder has expected entries and both valid/invalid coverage. |

## Still not DX12-ready

These are intentionally not solved in M18A:

- Parser and semantic are still heavily coupled inside the bootstrap driver.
- IR v0 is still string-line based and should become typed before serious DX12 resources/pipelines.
- Runtime has no update/render loop, delta time, frame count, swapchain lifecycle, or resize lifecycle yet.
- DX12 should not be emitted as raw bytes inside the monolithic bootstrap driver.

## Recommended next gates

1. M18B: compiler boundary hardening: AST/semantic/IR separation, type registry, command registry consistency.
2. M18C: runtime foundation: update/render event model, frame timing symbols reserved but not implemented until DX12 loop exists.
3. Style system.
4. DX12 window/runtime.
5. DX12 render primitives.
