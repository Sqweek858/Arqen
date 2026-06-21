# Repository Layout

```text
Backends/         native/runtime backend source and backend-specific assets
Build/            local generated output only
Docs/             main Markdown/text documentation surface
IR/               IR samples or non-document IR assets
Tests/            command tests, diagnostics, expected IR and samples
Tools/            compiler driver source and PowerShell tooling
What_I_Can_Do/    showcase demos for current language/toolchain capabilities
VisualStudio/     contained Visual Studio solution and local VS trash area
run_me.ps1        root health console; only allowed root PowerShell exception
```

## Tooling layout

```text
run_me.ps1                  root health console and interactive menu
Tools/test.ps1              main public test entrypoint
Tools/run_test_slice.ps1    compatibility wrapper for targeted slices
Tools/Internal/Test/        internal test runners used by the public wrappers
Tools/Test/                 intentionally no active public .ps1 engines
Tools/Legacy/               retired script holding area; no active .ps1 scripts
```

The central interactive command is:

```powershell
.\run_me.ps1
```

The direct standard health run is:

```powershell
.\run_me.ps1 -Run
```

The raw public command for a full local sweep is:

```powershell
.\Tools\test.ps1 -Everything -StopOnFail
```

## Documentation placement rule

Most `.md` and `.txt` files must live under either:

```text
Docs/
Tests/
```

Approved README exceptions:

```text
README.md
What_I_Can_Do/README.md
VisualStudio/README.md
```

Generated output folders such as `Build/`, `What_I_Can_Do/Build/`, `What_I_Can_Do/Exe/`, and `VisualStudio/Trash/` may contain local generated text/log artifacts, but those artifacts should not be committed.

If source-adjacent explanation is needed outside the approved README exceptions, add it to the appropriate `Docs/Reference/` or `Docs/Info/` file.

## PowerShell placement rule

Source `.ps1` files belong under `Tools/`, except root `run_me.ps1`, which is intentionally allowed as the main health-console entrypoint. Visual Studio helper scripts live under `VisualStudio/Scripts/` because they are part of the contained Visual Studio shell.
