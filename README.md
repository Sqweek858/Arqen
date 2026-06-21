# Arqen

Arqen is an experimental programming language and compiler/toolchain developed incrementally through milestone-based slices. The repository contains the language frontend, semantic and IR pipeline, Windows x64 backend, runtime feature tests, repository validation tools, DX12/UI experiments, and a small showcase area that demonstrates the current capabilities of the project.

Arqen is not presented as a finished production language. It is a research and prototype codebase with strict validation scripts, generated artifacts, and a growing set of compiler/runtime demonstrations.

## Quick start

From the repository root, the main entrypoint is:

```powershell
.\run_me.ps1
```

This opens the interactive health menu. Choose `1` for the normal repository health check.

For a direct standard run without the menu:

```powershell
.\run_me.ps1 -Run
```

For a calmer output mode:

```powershell
.\run_me.ps1 -Run -NoAnimation
```

The standard run performs the main preflight checks, repository validators, trash/tool-surface checks, and the official full test path.

## Repository layout

| Path | Purpose |
|---|---|
| `Backends/` | Backend implementations and runtime-related backend code. |
| `Docs/` | Main documentation surface: milestones, language notes, technical contracts, and repository rules. |
| `IR/` | Intermediate representation contracts and related project files. |
| `Tests/` | Command samples, validation samples, and test assets used by the tooling. |
| `Tools/` | Public wrappers, internal test runners, validators, generators, build helpers, and DX12 build scripts. |
| `What_I_Can_Do/` | Showcase demos for the current language/toolchain capabilities. |
| `VisualStudio/` | Visual Studio solution and helper scripts kept separate from the repository root. |
| `Build/` | Generated build outputs, logs, reports, tokens, AST, IR, manifests, and native build products. |
| `run_me.ps1` | Root health console and interactive validation menu. |

Root-level documentation and tooling are intentionally limited. `README.md` and `run_me.ps1` are the only expected root documentation/tooling entrypoints.

## What Arqen currently demonstrates

The current toolchain line includes:

- lexer, parser, semantic validation, IR generation, and backend emission;
- Windows x64 PE output;
- runtime integer, boolean, and string state;
- runtime control flow with `if`, `while`, `break`, and `continue`;
- functions with parameters, returns, local scope, and call graph validation;
- arrays, local arrays, array parameters, fill/copy helpers, and length support;
- records, record parameters, record arrays, copy/reset helpers, and enum fields;
- enums, enum arrays, enum returns, and runtime switch support;
- math, geometry, vector, quaternion, and related typed examples;
- file I/O and command-argument examples;
- experimental DX12/UI metadata and native DX12 sample generation.

The language and toolchain remain under active development. Some historical, optional, or deep audit surfaces may fail while the normal health path remains green.

## Showcase demos

The `What_I_Can_Do/` folder is intended as a practical demonstration area for the current feature set.

```text
What_I_Can_Do/
  Source/   .arq showcase sources and local shaders
  Build/    build script and showcase build logs
  Exe/      generated demo executables
```

To build the showcase from PowerShell:

```powershell
.\What_I_Can_Do\Build\build_all.ps1 -Clean
```

To run the console demos after build:

```powershell
.\What_I_Can_Do\Build\build_all.ps1 -Clean -RunConsoleSamples
```

To build and run the DX12 demo from the command line, use a Visual Studio Developer PowerShell or another environment where `cl.exe` is available:

```powershell
.\What_I_Can_Do\Build\build_all.ps1 -Clean -RunDx12
```

For the DX12 showcase, the preferred path is:

1. Open `VisualStudio\Arqen.sln`.
2. Run `Build > Build Solution`.
3. Open `What_I_Can_Do\Exe\06_dx12_ui_scene_max_metadata.exe`.

The DX12 demo requires the Visual Studio C++ toolchain because it builds native C++/DX12 code.

## Visual Studio usage

Open the solution file directly:

```text
VisualStudio\Arqen.sln
```

Do not open the repository root as a Visual Studio folder if the goal is to keep the root clean. The `VisualStudio/` folder contains its own helper scripts and a dedicated `Trash/` area for Visual Studio logs and generated local files.

The Visual Studio project builds the `What_I_Can_Do` showcase by calling:

```text
VisualStudio\Scripts\vs_build_what_i_can_do.ps1
```

Build logs are written to:

```text
VisualStudio\Trash\Arqen.WhatICanDo\last_build.log
```

## Validation commands

Common validation commands:

```powershell
.\run_me.ps1 -Run -NoAnimation
.\Tools\test.ps1 -Everything -StopOnFail
.\Tools\verify_repo.ps1 -RunValidators
.\Tools\validate.ps1 tool_surface
.\Tools\validate.ps1 trash
```

Useful report/log locations:

```text
Build\Generated\run_me_report.txt
Build\Generated\everything_test_report.txt
Build\Logs\
VisualStudio\Trash\Arqen.WhatICanDo\last_build.log
What_I_Can_Do\Build\
```

## Generated files and cleanup

Generated files are expected under `Build/`, `What_I_Can_Do/Build/`, `What_I_Can_Do/Exe/`, and `VisualStudio/Trash/`. Native intermediate files such as `.obj`, `.pdb`, `.ilk`, `.exp`, and `.lib` should not be left in the repository root.

To check for root-level native leftovers:

```powershell
Get-ChildItem . -File | Where-Object { $_.Extension -in ".obj", ".pdb", ".ilk", ".exp", ".lib" }
```

To remove accidental root-level native leftovers:

```powershell
Remove-Item .\*.obj, .\*.pdb, .\*.ilk, .\*.exp, .\*.lib -Force -ErrorAction SilentlyContinue
```

## Documentation policy

The main documentation surface is `Docs/`. New milestone notes, technical contracts, language references, and repository policies should be added there unless the file is specifically part of a showcase or tool surface.

The root `README.md` should stay high-level and practical: project overview, quick start, repository layout, validation commands, Visual Studio usage, and current capability summary.
