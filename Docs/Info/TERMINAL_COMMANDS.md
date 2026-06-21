# Terminal Commands

Run commands from the repository root.

## Main health console

Use this when you want the central interactive health menu with colored output, ASCII banner, per-step logs, failure causes, log-tail printing and a final report:

```powershell
.\run_me.ps1
```

Choose option `1` for the standard health check. For a direct standard run without the menu:

```powershell
.\run_me.ps1 -Run
```

Report output:

```text
Build\Generated\run_me_report.txt
Build\Logs\run_me\
```

Useful variants:

```powershell
.\run_me.ps1 -List
.\run_me.ps1 -Deep
.\run_me.ps1 -AbsolutelyEverything
.\run_me.ps1 -StrictLocal
.\run_me.ps1 -StrictGit
.\run_me.ps1 -KeepGoing
.\run_me.ps1 -NoAnimation
.\run_me.ps1 -NoColor
.\run_me.ps1 -ReportOnly
```

`-Deep` opts into historical validators, spec coverage validators, ExpectedIR fixtures and scaffold scripts. `-AbsolutelyEverything` also opts into native/DX12 build scripts, which can require external Windows build tooling. These audit modes may fail while the standard health path is green. `-StrictGit` makes `git diff --check` fatal instead of report-only. `-NoAnimation` disables the small spinner/transition effects while keeping the report; `-NoColor` disables colored output for plain terminals/log captures.

## Compile / run a source file

```powershell
.\Tools\arqc.ps1 .\Tests\Backend\WindowsX64PE\valid_show_message_exit.arq
```

`Tools/arqc.ps1` forwards all arguments to `Tools/arqc_m10g.exe` when it exists. If the executable is missing, rebuild it:

```powershell
.\Tools\arqc.ps1 -BuildDriver
```

## Official full local test sweep

This is the underlying official full local test sweep. `run_me.ps1` calls it and adds a structured report around it:

```powershell
.\Tools\test.ps1 -Everything -StopOnFail
```

It writes the combined report to:

```text
Build\Generated\everything_test_report.txt
```

and per-step logs under:

```text
Build\Logs\
```

The default sweep includes clean checks, tool-surface checks, trash checks, repository verification, generators, runtime registry/catalog validation, backend docs validation, all command tests, active validators, backend fixtures, cache fixtures, diagnostics fixtures and sample compiles.

## Optional full-sweep extras

Use these only when deliberately auditing slower or legacy surfaces:

```powershell
.\Tools\test.ps1 -Everything -IncludeHistoricalValidators -IncludeSpecCoverageValidators -IncludeExpectedIr -StopOnFail
.\Tools\test.ps1 -Everything -IncludeBuildScripts -StopOnFail
.\Tools\test.ps1 -Everything -IncludeScaffoldScripts -StopOnFail
```

`-IncludeBuildScripts` can require native/DX12 Windows build tooling. ExpectedIR and historical validators are intentionally opt-in.

## List available build / generate / validate / test commands

```powershell
.\Tools\build.ps1 -List
.\Tools\generate.ps1 -List
.\Tools\validate.ps1 -List
.\Tools\test.ps1 -List
```

## Targeted command tests and validation slices

Main entrypoint:

```powershell
.\Tools\test.ps1 -AllCommand
.\Tools\test.ps1 -Folder scalar_math
.\Tools\test.ps1 -Group m61m62
.\Tools\test.ps1 -Tool runtime_action_catalog
.\Tools\test.ps1 -Changed
```

Compatibility wrapper:

```powershell
.\Tools\run_test_slice.ps1 -Folder scalar_math
```

`run_me.ps1` is the root health console. `Tools/test.ps1` is the public test entrypoint underneath it. Internal runners live under `Tools/Internal/Test/` and are not called directly. `Tools/Test/` is intentionally kept without active public `.ps1` engines.

## Build a named build script

```powershell
.\Tools\build.ps1 m21d_dx12_triangle_smoke
.\Tools\build.ps1 build_m21d_dx12_triangle_smoke.ps1
```

The wrapper searches under `Tools/Build/` and requires exactly one match.

## Run a validator

```powershell
.\Tools\validate.ps1 m61_m62_enum_scope_params
.\Tools\validate.ps1 validate_m61_m62_enum_scope_params.ps1
.\Tools\validate.ps1 runtime_action_catalog
.\Tools\validate.ps1 backend_docs
.\Tools\validate.ps1 tool_surface
.\Tools\validate.ps1 trash
```

The wrapper searches under `Tools/Validate/` and requires exactly one match.

## Generate registries / maps

```powershell
.\Tools\generate.ps1 command_status
.\Tools\generate.ps1 runtime_action_registry
.\Tools\generate.ps1 error_code_registry
```

The wrapper searches under `Tools/Generate/`.


## Showcase and DX12 demo

Build the current showcase demos:

```powershell
.\What_I_Can_Do\Build\build_all.ps1 -Clean
```

Run console showcase demos after build:

```powershell
.\What_I_Can_Do\Build\build_all.ps1 -Clean -RunConsoleSamples -SkipDx12
```

Preferred DX12 path:

```text
1. Open VisualStudio\Arqen.sln.
2. Run Build > Build Solution.
3. Open What_I_Can_Do\Exe\06_dx12_ui_scene_max_metadata.exe.
```

Command-line DX12 builds require a Visual Studio Developer PowerShell or another environment where `cl.exe` is available:

```powershell
.\What_I_Can_Do\Build\build_all.ps1 -Clean -RunDx12
```

## Clean local generated output and verify docs placement

```powershell
.\Tools\clean.ps1
.\Tools\clean.ps1 -CheckOnly
```

The clean script removes common local generated folders such as `.vs`, `Build` contents, `What_I_Can_Do` generated output, Visual Studio trash output and M10G `bin/obj/publish`, then verifies source documentation placement. Approved README entrypoints and generated/local output folders are ignored by the documentation-location check.

## Trash / generated-output checks

```powershell
.\Tools\validate.ps1 trash
.\Tools\validate.ps1 trash -StrictLocal
```

The default trash check guards tracked/generated garbage and visible untracked build leftovers. `-StrictLocal` also fails local archive/patch leftovers inside the repository tree.

## Final repository/toolchain verification

```powershell
.\Tools\verify_repo.ps1
```

For a stronger local check that also runs selected validators and a compiler smoke test:

```powershell
.\Tools\verify_repo.ps1 -BuildDriver -RunSmoke -RunValidators -RunAllCommandTests -StrictClean
```

The report is written to:

```text
Build\Generated\arqen_repo_verification_report.txt
```

## Verify expected IR

```powershell
.\Tools\verify_expected_ir.ps1
```

Compares `.expected.ir` cases under `Tests/ExpectedIR` against active compiler output. ExpectedIR is intentionally opt-in from the full suite. Run it directly or through:

```powershell
.\Tools\test.ps1 -Everything -IncludeExpectedIr -StopOnFail
```

## Milestone group behavior

Current pair groups such as `m45m46`, `m59m60`, and `m61m62` are targeted smoke groups. They run the validator for that milestone pair plus the runtime action catalog where relevant. Historical deep-chain aliases with `abc` are kept for broader regression sweeps and may be slower/noisier during cleanup.
