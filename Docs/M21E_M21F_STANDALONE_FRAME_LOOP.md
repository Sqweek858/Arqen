# M21E/M21F DX12 Standalone Runtime and Frame Loop

M21E/M21F harden the native triangle smoke path after the first M21D triangle render.

## M21E boundary

M21E makes the generated optional native executable friendlier outside the exact build shell:

- generated runtime log beside the executable: `arqen_dx12_runtime.log`
- shader source fallback from configured absolute path to `Build\EXE\Shaders\<file>`
- build helper copies M21D shader files into `Build\EXE\Shaders`
- generated executable shows a MessageBox on DX12/HLSL/PSO failures
- generated window disables default white erase through `WM_ERASEBKGND`

This does not make DX12 generally supported. It only hardens the experimental smoke executable.

## M21F boundary

M21F adds a persistent fixed-frame smoke loop to the native bridge:

```text
Arqen IR + M21D triangle metadata
-> lowerer frame loop config
-> generated native smoke executable
-> ArqenDx12TriangleWindowRunFrames
-> repeat clear/draw/present for N frames at target FPS
```

M21F is configured through lowering/build flags, not new public Arqen syntax:

```powershell
.\Tools\build_m21f_dx12_triangle_loop_smoke.ps1 -FrameCount 180 -TargetFps 60
.\Tools\build_m21f_dx12_triangle_loop_smoke.ps1 -FrameCount 600 -TargetFps 60 -BuildNative -Run
```

Generated config markers:

```text
ARQEN_M21E_STANDALONE_EXE
ARQEN_M21E_SHADER_FALLBACK_ENABLED
ARQEN_M21F_FRAME_LOOP_ENABLED
ARQEN_M21F_FRAME_COUNT
ARQEN_M21F_TARGET_FPS
```

Generated manifest markers:

```text
STANDALONE_EXE|True
SHADER_FALLBACK|exe_dir_shaders
FRAME_LOOP_MODE|fixed_frame_count
FRAME_COUNT|...
TARGET_FPS|...
```

## Still not implemented

M21F is not animation syntax, not constant buffers, not UI rendering, and not a general frame update system. It is the native runtime loop needed before uniform/color animation work.

`dx12`, `shader`, `render_pass`, and `frame_update` remain unsupported in the capability table.
