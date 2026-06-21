# Tools Reference

## Root health console

`run_me.ps1` is the central repository health entrypoint. By default it opens an interactive menu. Choose option `1` for the standard health check.

```powershell
.\run_me.ps1
```

For a direct standard run without the menu:

```powershell
.\run_me.ps1 -Run
```

Useful variants:

```powershell
.\run_me.ps1 -List
.\run_me.ps1 -Run -NoAnimation
.\run_me.ps1 -Deep
.\run_me.ps1 -AbsolutelyEverything
.\run_me.ps1 -NoAnimation
.\run_me.ps1 -NoColor
.\run_me.ps1 -NoEmoji
```

`-Deep` opts into slower or historical surfaces. `-AbsolutelyEverything` also includes native/DX12 build scripts and may require external Windows build tooling. These audit modes may fail while the standard health path is green.

## Root wrappers

Run these from the repository root. These wrappers are the public tooling surface; scripts under `Tools/Internal/` are implementation details and should not be called directly during normal work.

| Tool | Purpose |
| --- | --- |
| `run_me.ps1` | Root health console and interactive report wrapper around the key checks. |
| `Tools/arqc.ps1` | Forwards to the active M10G compiler executable. Supports `-BuildDriver`. |
| `Tools/build.ps1` | Finds and runs a build script from `Tools/Build/`. Supports `-List`. |
| `Tools/generate.ps1` | Finds and runs a generator from `Tools/Generate/`. Supports `-List`. |
| `Tools/validate.ps1` | Finds and runs a validator from `Tools/Validate/`. Supports `-List`. |
| `Tools/test.ps1` | Main test entrypoint. Supports `-List`, `-AllCommand`, `-Folder`, `-Group`, `-Tool`, `-Changed`, and `-Everything` for the full repository test sweep. `-Everything` can opt into `-IncludeBuildScripts`, `-IncludeScaffoldScripts`, `-IncludeHistoricalValidators`, `-IncludeSpecCoverageValidators`, and `-IncludeExpectedIr`. |
| `Tools/run_test_slice.ps1` | Compatibility wrapper for targeted command-test slices. Prefer `Tools/test.ps1` for normal testing. |
| `Tools/verify_expected_ir.ps1` | Verifies expected IR fixtures against the active compiler wrapper. ExpectedIR is opt-in from the full sweep. |
| `Tools/verify_repo.ps1` | Final repository/toolchain verifier with a structured report. |
| `Tools/clean.ps1` | Removes local generated output and checks documentation/script placement. |
| `Tools/lower_m20e1_dx12_clear_from_ir.ps1` | Compatibility wrapper for the DX12 lowering helper. |

## Official full test command

Use `run_me.ps1` for the central report. Use this direct command when you want only the raw official test sweep:

```powershell
.\Tools\test.ps1 -Everything -StopOnFail
```

This delegates to `Tools/Internal/Test/run_everything.ps1` and runs clean checks, tool-surface checks, trash checks, repository verification, generators, runtime registry/catalog validation, backend docs validation, all command-test folders, active validators, backend fixtures, cache fixtures, diagnostics fixtures, and sample compiles.

Historical validators, spec/coverage validators, ExpectedIR fixtures, scaffold scripts, and native/DX12 build scripts remain opt-in because they can be stale, slow, or require external Windows build tooling.

## Showcase and Visual Studio helper scripts

| Path | Purpose |
| --- | --- |
| `What_I_Can_Do/Build/build_all.ps1` | Builds the showcase demos and optionally launches console/DX12 demos. |
| `VisualStudio/Scripts/vs_build_what_i_can_do.ps1` | Visual Studio build wrapper for the showcase project. Writes a detailed log under `VisualStudio/Trash/`. |
| `VisualStudio/Scripts/vs_clean_what_i_can_do.ps1` | Visual Studio clean helper for showcase/local VS output. |

The preferred DX12 showcase path is:

```text
1. Open VisualStudio\Arqen.sln.
2. Run Build > Build Solution.
3. Open What_I_Can_Do\Exe\06_dx12_ui_scene_max_metadata.exe.
```

## Optional sweeps

```powershell
.\Tools\test.ps1 -Everything -IncludeHistoricalValidators -IncludeSpecCoverageValidators -IncludeExpectedIr -StopOnFail
.\Tools\test.ps1 -Everything -IncludeBuildScripts -StopOnFail
.\Tools\test.ps1 -Everything -IncludeScaffoldScripts -StopOnFail
```

Use these only when intentionally auditing old milestone validators, ExpectedIR fixtures, scaffold scripts, or native/DX12 build scripts.

## Tool folders

| Folder | Purpose |
| --- | --- |
| `Tools/M10GDriver/` | Active C# compiler/driver source. |
| `Tools/Build/` | Build scripts, mainly DX12/native smoke builds. |
| `Tools/Generate/` | Registry and documentation generators. |
| `Tools/Validate/` | Validation scripts grouped by area, including `validate_trash.ps1` for generated/local garbage guards. |
| `Tools/Internal/Test/` | Internal test runners used by `Tools/test.ps1` and `Tools/run_test_slice.ps1`. Do not call these directly. |
| `Tools/Test/` | Public test folder intentionally kept without active `.ps1` engines. Active runners belong in `Tools/Internal/Test/`; the public entrypoint is `Tools/test.ps1`. |
| `Tools/Lowering/` | Lowering helpers, currently including DX12 helpers. |
| `Tools/Scaffold/` | Scripts for new command/sample scaffolding. |
| `Tools/Common/` | Shared PowerShell modules/helpers. |
| `Tools/Legacy/` | Retired script holding area. No active `.ps1` tooling is allowed here. |

## Shared helper module

`Tools/Common/ArqenTooling.psm1` provides common helper functions used by the root wrappers:

- repository root discovery without relying only on Git;
- relative path formatting;
- build/generate/validate script discovery;
- script listing for wrapper `-List` commands.

## Generated output rule

Tools may write into `Build/`, `What_I_Can_Do/Build/`, `What_I_Can_Do/Exe/`, and `VisualStudio/Trash/`, but generated output should not be committed unless a specific test fixture intentionally requires it under `Tests/`.
