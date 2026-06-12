# M21 Shader/Pipeline Mini Bible

M21 starts the shader and pipeline foundation for the DX12 track. It extends the M20 renderer/frame metadata path, but it does **not** promote DX12 support.

## Status

```text
M21A = syntax/spec bible for shader + pipeline metadata
M21B = compiler metadata implementation for file-based shaders, DX12 pipelines, and pipeline binding
```

`dx12`, `shader`, `render_pass`, and `frame_update` remain unsupported capability families until native runtime/backend execution exists.

## Supported in M21B

### File-based shader metadata

```arqen
define shader called "TriangleShader"
    vertex source file "Shaders/triangle_vs.hlsl"
    pixel source file "Shaders/triangle_ps.hlsl"
end shader
```

Rules:

```text
shader name must be non-empty and unique
shader names must not collide with symbols, windows, UI objects, DX12 renderers, or DX12 pipelines
vertex source file is required exactly once
pixel source file is required exactly once
source paths must be non-empty strings
inline HLSL is not supported in M21B
```

Generated metadata:

```text
DX12_SHADER|name=TriangleShader|vertex=Shaders/triangle_vs.hlsl|pixel=Shaders/triangle_ps.hlsl
```

### DX12 pipeline metadata

```arqen
define dx12 pipeline called "TrianglePipeline"
    renderer: "MainRenderer"
    shader: "TriangleShader"
    topology: triangle list
end pipeline
```

Rules:

```text
pipeline name must be non-empty and unique
pipeline names must not collide with symbols, windows, UI objects, DX12 renderers, or DX12 shaders
renderer must be a known DX12 renderer
renderer must already be parented to a known window
shader must be a known shader
only topology supported in M21B: triangle list
```

Generated metadata:

```text
DX12_PIPELINE|name=TrianglePipeline|renderer=MainRenderer|shader=TriangleShader|topology=triangle_list
```

### Pipeline binding metadata

```arqen
use pipeline "TrianglePipeline" for renderer "MainRenderer"
```

Rules:

```text
pipeline must exist
renderer must exist
pipeline must have been defined for the same renderer
one pipeline binding per renderer in M21B
```

Generated metadata:

```text
DX12_PIPELINE_BIND|pipeline=TrianglePipeline|renderer=MainRenderer
```

## Reserved for later M21 passes

These are intentionally not implemented in M21B:

```arqen
draw 3 vertices with renderer "MainRenderer"
set vertex buffer of "MainRenderer" to "TriangleVertices"
set constant buffer of "MainRenderer" to "FrameConstants"
compile shader "TriangleShader"
```

The next pass should handle draw/buffer design only after shader/pipeline metadata is stable.

## No fake support boundary

M21B does not compile HLSL, does not call DXC, does not create a root signature, does not create a PSO, does not bind a vertex buffer, and does not issue a native draw call.

A backend may parse and ignore `DX12_SHADER`, `DX12_PIPELINE`, and `DX12_PIPELINE_BIND` metadata until a later execution milestone consumes it.

## M21C implemented: vertex buffer + draw metadata

M21C adds the minimum source-controlled geometry path needed for a future triangle smoke. It is still metadata at compiler level.

```arqen
define vertex buffer called "TriangleVertices"
    vertex position [-0.5, -0.5, 0.0] color [1.0, 0.0, 0.0, 1.0]
    vertex position [0.0, 0.5, 0.0] color [0.0, 1.0, 0.0, 1.0]
    vertex position [0.5, -0.5, 0.0] color [0.0, 0.0, 1.0, 1.0]
end vertex buffer

use vertex buffer "TriangleVertices" for renderer "MainRenderer"

draw 3 vertices with renderer "MainRenderer"
```

Generated metadata:

```text
DX12_VERTEX_BUFFER|name=TriangleVertices
DX12_VERTEX|buffer=TriangleVertices|index=0|position=[-0.5,-0.5,0]|color=[1,0,0,1]
DX12_VERTEX_BUFFER_BIND|buffer=TriangleVertices|renderer=MainRenderer
DX12_DRAW|renderer=MainRenderer|vertices=3|buffer=TriangleVertices|pipeline=TrianglePipeline
```

Rules:

```text
vertex buffer names are non-empty, unique, and collision-checked
position must be vec3
color must be vec4 with components in [0,1]
M21C vertex buffers require at least 3 vertices
one vertex buffer binding per renderer
Draw requires: active frame, clear before draw, pipeline binding, vertex buffer binding, and draw count <= buffer vertex count
```

## M21D implemented: native triangle smoke path

M21D extends the M20E1/M20H lowerer with `-RequireTriangle` and consumes the real M21B/M21C metadata. It generates a config header containing shader paths, pipeline metadata, vertex data, and draw count. The optional native helper compiles HLSL with `D3DCompileFromFile`, creates a root signature, creates a triangle-list PSO, uploads the generated vertex buffer, and issues `DrawInstanced`.

```powershell
.\Tools\build_m21d_dx12_triangle_smoke.ps1
.\Tools\build_m21d_dx12_triangle_smoke.ps1 -BuildNative
.\Tools\build_m21d_dx12_triangle_smoke.ps1 -BuildNative -Run
```

M21D is the first path intended to render a real triangle, but native build/run remains manual and optional. Standard regression must not require GPU, MSVC, DX12 runtime availability, or shader compilation.
