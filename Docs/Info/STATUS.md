# Project Status

## Current line

Arqen is around M70 on the tooling/workflow line. The active compiler is still the M10G driver line, but it now supports many language/runtime features added long after the original M10 bootstrap.

M63-M70 are cleanup, tooling, documentation and workflow milestones rather than major language-syntax milestones. Their main results are a cleaner public tool surface, a root health console, a showcase area and a contained Visual Studio solution:

```powershell
.\run_me.ps1
.\run_me.ps1 -Run
.\Tools\test.ps1 -Everything -StopOnFail
```

`run_me.ps1` opens an interactive health menu by default. `run_me.ps1 -Run` starts the standard health check directly. `Tools/test.ps1 -Everything -StopOnFail` remains the official full local sweep underneath it. Internal test runners live under `Tools/Internal/Test/`; `Tools/Test/` must not contain active public engine scripts.

## Working areas

- Lexer/parser/semantic pipeline in C#.
- ARQIR-style intermediate output.
- Windows x64 PE backend path.
- Runtime state and control flow.
- Functions with params, returns and local scope.
- Runtime arrays, records, enums and switch control.
- Experimental DX12/window/UI branch.
- Unified PowerShell tooling wrappers for build, generate, validate and test flows.
- Root `run_me.ps1` health console with ASCII-safe UI, colored reporting, light terminal animations, cause extraction and log-tail printing.
- `What_I_Can_Do/` showcase demos for console/runtime features and the DX12/UI path.
- `VisualStudio/Arqen.sln` contained solution for building the showcase with MSVC/DX12 support.
- Trash/repository/tool-surface validators for keeping generated output and stale scripts out of the repo.

## Not finished

- No clean driver v2 yet.
- No full package/module system.
- No mature optimizer.
- No public standard library.
- No production-grade engine integration.
- No array returns, push/pop, slices or packed memory structs yet.

## Technical debt to keep visible

- M10G is an active legacy driver and should eventually be replaced by a cleaner driver.
- Some validators still encode milestone-era assumptions.
- Runtime slot lowering is pragmatic and not a final memory model.
- Some error codes are still broad or reused in ways that should be normalized later.
- Native/DX12 build scripts remain opt-in because they depend on external Windows build tooling.
