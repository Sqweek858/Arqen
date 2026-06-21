# Arqen Visual Studio Shell

Open this solution from Visual Studio:

```text
VisualStudio\Arqen.sln
```

Do not open the repository root as a loose Visual Studio folder if the goal is a clean workspace. The solution lives in `VisualStudio/`, and local Visual Studio state is expected under:

```text
VisualStudio\.vs\
VisualStudio\Trash\
```

Those paths are ignored by `VisualStudio/.gitignore`.

## What this solution contains

- `Arqen.WhatICanDo`: a Makefile-style utility project that runs the showcase build.
- Solution folders for important scripts and docs.
- Local Visual Studio cache/log output isolated under `VisualStudio/`.

Generated `.exe`, `.obj`, `.pdb`, `.suo`, `.vs` or build artifacts should not be committed.

## Build from Visual Studio

Build project:

```text
Arqen.WhatICanDo
```

That calls:

```powershell
..\What_I_Can_Do\Build\build_all.ps1 -Clean
```

DX12 native build needs MSVC tools, so building from Visual Studio or a VS Developer terminal is the recommended path. Normal PowerShell may not have `cl.exe` in `PATH`.

## Manual equivalent

From a Developer PowerShell / x64 Native Tools Prompt for VS:

```powershell
cd <repo-root>
.\What_I_Can_Do\Build\build_all.ps1 -Clean
```

To run the DX12 demo after build:

```powershell
.\What_I_Can_Do\Exe\06_dx12_ui_scene_max_metadata.exe
```

## Build diagnostics

The Visual Studio build wrapper writes a full build log to:

```text
VisualStudio\Trash\Arqen.WhatICanDo\last_build.log
```

If `cl.exe` is not already available, the wrapper tries to locate Visual Studio with `vswhere.exe` and bootstrap `vcvars64.bat` before running the `What_I_Can_Do` DX12 build.

## Cleanup

The solution-local `.gitignore` keeps common Visual Studio output ignored. Use the clean helper when needed:

```powershell
.\VisualStudio\Scripts\vs_clean_what_i_can_do.ps1
```
