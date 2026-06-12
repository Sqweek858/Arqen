# M21G/M21H DX12 Constant Buffer and Color Animation

Status: experimental smoke-path metadata only. General DX12, shader, render pass, and frame update capabilities remain unsupported.

## M21G scope

M21G adds a deliberately tiny constant-buffer surface for the existing M21D triangle smoke path:

```arqen
define constant buffer called "TriangleParams"
    color tint: color "#38FFC0"
end constant buffer

use constant buffer "TriangleParams" for pipeline "TrianglePipeline"
```

The compiler emits:

```text
DX12_CONSTANT_BUFFER|name=TriangleParams|field=tint|type=color4|value=#38FFC0
DX12_CONSTANT_BUFFER_BIND|buffer=TriangleParams|pipeline=TrianglePipeline
```

The M21D lowerer turns that into generated config macros such as:

```text
ARQEN_M21G_TINT_ENABLED
ARQEN_M21G_TINT_COLOR
```

The native DX12 smoke bridge creates a small upload constant buffer and binds it as pixel shader register `b0` when tint is enabled.

## M21H scope

M21H adds a color sequence plus frame-based animation for `TriangleParams.tint`:

```arqen
define color sequence called "TriangleColors"
    color "#FF4040"
    color "#38FFC0"
    color "#4080FF"
    color "#FFD040"
end color sequence

animate color "TriangleParams.tint"
    using sequence "TriangleColors"
    every 12 frames
end animate
```

The compiler emits:

```text
DX12_COLOR_SEQUENCE|name=TriangleColors
DX12_COLOR_KEY|sequence=TriangleColors|index=0|value=#FF4040
DX12_ANIMATE_COLOR|target=TriangleParams.tint|buffer=TriangleParams|field=tint|sequence=TriangleColors|every_frames=12
```

The native bridge does not hardcode colors. It consumes generated `ARQEN_M21H_COLOR_DATA`, `ARQEN_M21H_COLOR_COUNT`, and `ARQEN_M21H_COLOR_EVERY_FRAMES` macros and updates the tint constant buffer from the current frame number.

## Official sample

`Samples/DX12/dx12_animated_triangle_m21h.arq` is the official M21H animated triangle sample. It compiles to IR, lowers through the M21D/M21F path, and can optionally be built natively through:

```powershell
.\Tools\build_m21h_dx12_animated_triangle_smoke.ps1 -FrameCount 240 -TargetFps 60 -BuildNative -Run
```

## Boundaries

M21G/M21H do not add a general material system, arbitrary constant buffer layouts, texture binding, descriptor heaps, or a general frame-update language. The only supported dynamic value is `TriangleParams.tint` for the triangle smoke path.

## M21I smoke polish

M21I keeps the M21H public syntax unchanged and polishes the smoke path around it. The wrapper is:

```powershell
.\Tools\build_m21i_dx12_color_animation_smoke_polish.ps1 -Frames 240 -Fps 60 -Hold 4000
```

The wrapper delegates to the M21H animated triangle path, writes to `Build\M21I` by default, and exposes friendly runtime knobs for frame count, target FPS, hold time, renderer selection, output directory, and optional native run. The generated manifest/config also include explicit `M21I_SMOKE_POLISH`, `M21I_RUNTIME_KNOBS`, and color tick markers so validators do not have to infer runtime behavior from older M21F fields. This is smoke polish, not new language syntax.

## M21J metadata hardening

M21J tightens color animation metadata without adding new rendering features. `animate color` remains limited to `TriangleParams.tint`-style constant-buffer color targets for the triangle smoke path, but the source-level parser contract now requires the target constant buffer to be bound to exactly one pipeline before animation. The lowerer also rejects ambiguous or non-selected animation targets for the selected renderer tint path.

M21J does not add easing, transform animation, materials, textures, cameras, scene graphs, or a general frame-update language. It only makes the existing M21H color animation path harder to misuse.
