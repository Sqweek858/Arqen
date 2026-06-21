# What_I_Can_Do

This folder is an Arqen showcase area. It contains `.arq` samples that demonstrate the current language/toolchain surface without mixing demo files into the repository root.

## Folder layout

```text
What_I_Can_Do/
  Source/   .arq demo sources and local shader files
  Build/    build script, logs, generated demo artifacts
  Exe/      generated demo executables
```

## Recommended Visual Studio path

For the DX12 demo, use the Visual Studio solution so the MSVC environment is available.

Open:

```text
VisualStudio\Arqen.sln
```

Then run:

```text
Build > Build Solution
```

After the build finishes, open the DX12 demo executable manually:

```text
What_I_Can_Do\Exe\06_dx12_ui_scene_max_metadata.exe
```

The DX12 window is built in keep-open mode, so it should stay open until you close it.

## Console demos

The first five demos are console/runtime samples:

```text
01_runtime_state_control_strings.exe
02_functions_arrays_records_enums.exe
03_record_arrays_switch_simulation.exe
04_math_geometry_types_showcase.exe
05_file_io_command_args.exe
```

After a successful build, run them from the repository root:

```powershell
.\What_I_Can_Do\Exe\01_runtime_state_control_strings.exe
.\What_I_Can_Do\Exe\02_functions_arrays_records_enums.exe
.\What_I_Can_Do\Exe\03_record_arrays_switch_simulation.exe
.\What_I_Can_Do\Exe\04_math_geometry_types_showcase.exe
.\What_I_Can_Do\Exe\05_file_io_command_args.exe alpha beta gamma
```

Or run all non-DX12 samples after build:

```powershell
.\What_I_Can_Do\Build\build_all.ps1 -Clean -RunConsoleSamples -SkipDx12
```

## DX12 demo

DX12 requires native MSVC tools (`cl.exe`). The preferred path is Visual Studio:

```text
1. Open VisualStudio\Arqen.sln
2. Build > Build Solution
3. Run What_I_Can_Do\Exe\06_dx12_ui_scene_max_metadata.exe
```

Terminal alternative, only from Developer PowerShell / x64 Native Tools Prompt for VS:

```powershell
cd C:\Users\Sqweek\Documents\Arqen\Arqen
.\What_I_Can_Do\Build\build_all.ps1 -Clean
.\What_I_Can_Do\Exe\06_dx12_ui_scene_max_metadata.exe
```

To build and launch DX12 from the script:

```powershell
.\What_I_Can_Do\Build\build_all.ps1 -Clean -RunDx12
```

Use timed mode if you want it to close automatically:

```powershell
.\What_I_Can_Do\Build\build_all.ps1 -Clean -RunDx12 -Dx12Timed -Dx12Frames 900
```

## Logs and generated files

Build logs:

```text
What_I_Can_Do\Build\*.build.log
VisualStudio\Trash\Arqen.WhatICanDo\last_build.log
```

Generated intermediate artifacts:

```text
What_I_Can_Do\Build\Artifacts\
```

Final executables:

```text
What_I_Can_Do\Exe\
```

## Notes

- Do not open the repository root as a Visual Studio folder if the goal is a clean workspace. Open `VisualStudio\Arqen.sln` instead.
- Visual Studio trash/cache should stay under `VisualStudio\Trash` or `VisualStudio\.vs`, not in the repository root.
- The DX12 sample uses self-contained shaders under `What_I_Can_Do\Source\Shaders`.
- If `cl.exe` is missing, use Visual Studio or Developer PowerShell, because normal PowerShell usually does not load the MSVC toolchain.
