# M21 Handoff - Shader, Pipeline, Vertex Buffer, and Triangle Smoke

M21A/M21B added shader and pipeline metadata on top of the M20 DX12 renderer/frame path. M21C/M21D adds source-controlled vertex/draw metadata and an optional native triangle smoke path.

## Implemented in M21A/M21B

```arqen
define shader called "TriangleShader"
    vertex source file "path_vs.hlsl"
    pixel source file "path_ps.hlsl"
end shader

define dx12 pipeline called "TrianglePipeline"
    renderer: "MainRenderer"
    shader: "TriangleShader"
    topology: triangle list
end pipeline

use pipeline "TrianglePipeline" for renderer "MainRenderer"
```

## Implemented in M21C

```arqen
define vertex buffer called "TriangleVertices"
    vertex position [-0.5, -0.5, 0.0] color [1.0, 0.0, 0.0, 1.0]
    vertex position [0.0, 0.5, 0.0] color [0.0, 1.0, 0.0, 1.0]
    vertex position [0.5, -0.5, 0.0] color [0.0, 0.0, 1.0, 1.0]
end vertex buffer

use vertex buffer "TriangleVertices" for renderer "MainRenderer"

draw 3 vertices with renderer "MainRenderer"
```

Emitted metadata:

```text
DX12_VERTEX_BUFFER
DX12_VERTEX
DX12_VERTEX_BUFFER_BIND
DX12_DRAW
```

## Implemented in M21D

`Tools/lower_m20e1_dx12_clear_from_ir.ps1 -RequireTriangle` now requires a complete first-triangle metadata set:

```text
DX12_CLEAR_READY
DX12_FRAME begin,clear,end,present
DX12_SHADER
DX12_PIPELINE
DX12_PIPELINE_BIND
DX12_VERTEX_BUFFER
DX12_VERTEX_BUFFER_BIND
DX12_DRAW
```

The wrapper:

```powershell
.\Tools\build_m21d_dx12_triangle_smoke.ps1
```

compiles the Arqen sample, lowers IR to `Build\M21D\dx12_clear_config.generated.h`, and can optionally build/run the native DX12 smoke executable.

## Capability boundary

`dx12`, `shader`, `render_pass`, and `frame_update` remain unsupported. M21D provides an optional smoke path, not general backend support.

## Implemented in M21E/M21F

M21E hardens the optional native executable boundary:

```text
Build/EXE/<smoke>.exe
Build/EXE/Shaders/<copied shader sources>
Build/EXE/arqen_dx12_runtime.log
MessageBox on runtime failure
shader fallback through exe-dir Shaders
```

M21F adds a persistent fixed-frame native loop controlled by build/lowering flags, not public syntax:

```powershell
.\Tools\build_m21f_dx12_triangle_loop_smoke.ps1 -FrameCount 180 -TargetFps 60
```

Generated config includes:

```text
ARQEN_M21E_STANDALONE_EXE
ARQEN_M21E_SHADER_FALLBACK_ENABLED
ARQEN_M21F_FRAME_LOOP_ENABLED
ARQEN_M21F_FRAME_COUNT
ARQEN_M21F_TARGET_FPS
```

## Suggested next step

M21G should add constant buffer/uniform metadata only after M21E/M21F standalone frame-loop behavior is stable on Windows. Do not add textures, camera, or render passes before uniform color animation is validated.

## M21G/M21H constant tint + color animation

M21G adds metadata for a tiny DX12 constant buffer surface:

```text
DX12_CONSTANT_BUFFER|name=TriangleParams|field=tint|type=color4|value=#38FFC0
DX12_CONSTANT_BUFFER_BIND|buffer=TriangleParams|pipeline=TrianglePipeline
```

M21H adds color sequence animation metadata:

```text
DX12_COLOR_SEQUENCE|name=TriangleColors
DX12_COLOR_KEY|sequence=TriangleColors|index=0|value=#FF4040
DX12_ANIMATE_COLOR|target=TriangleParams.tint|buffer=TriangleParams|field=tint|sequence=TriangleColors|every_frames=12
```

The native triangle smoke bridge consumes generated tint/color sequence arrays and updates the tint constant buffer per frame. This remains an experimental smoke path; `dx12`, `shader`, `render_pass`, and `frame_update` capabilities remain unsupported.

## M21I/M21J color animation follow-up

M21I is a smoke-path polish milestone for the M21H animated triangle path. It keeps public syntax unchanged and adds a `build_m21i_dx12_color_animation_smoke_polish.ps1` wrapper with explicit frame/FPS/hold/output/native-run knobs plus generated manifest/config markers.

M21J is metadata hardening. It keeps animation limited to selected tint constant-buffer metadata and tightens both parser source and lowerer checks around binding ambiguity, missing bindings, duplicate animation targets, bad color sequences, and unsupported non-selected animation targets. It does not promote DX12 families out of the unsupported backend capability boundary.
