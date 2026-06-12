# M23 DX12 Real Scene Objects

M23 turns the M22 mini-scene smoke layer into a real object/multi-draw scene contract. The goal is intentionally narrow: keep the existing DX12 renderer/window/shader/pipeline/vertex-buffer path, but add named objects and multiple draw calls that lower to native DX12.

## M23A - Public syntax contract

The public object syntax is deliberately small:

```arq
define object called "CrystalA"
```

A scene object can bind to existing DX12 resources:

```arq
use renderer "MainRenderer" for object "CrystalA"
use pipeline "CrystalPipeline" for object "CrystalA"
use vertex buffer "CrystalAVertices" for object "CrystalA"
draw 12 vertices for object "CrystalA"
```

The draw syntax is intentionally simple:

```arq
draw "CrystalA"
```

M23C also supports explicit public multi-draw syntax for low-level tests:

```arq
draw 3 vertices from buffer "ShardA" with pipeline "CrystalPipeline" using renderer "MainRenderer"
```

## M23B - Object metadata

The compiler emits real object metadata:

```txt
DX12_OBJECT
DX12_OBJECT_BIND
DX12_DRAW_OBJECT
```

Object metadata is not a comment-only layer. It is consumed by the M20E1/M21/M22/M23 lowerer and contributes to the generated native draw-call table.

Semantic guards:

- duplicate object names are rejected;
- unknown objects are rejected;
- renderer/pipeline/vertex-buffer object bindings must reference known DX12 resources;
- object draw counts must be at least 3 and cannot exceed the bound vertex buffer;
- `draw "Object"` must happen inside a cleared active frame;
- duplicate draw calls for the same object in one frame are rejected.

## M23C - Multi-draw lowering/runtime

The native lowering path now supports a list of draw calls. For M23C, the native smoke runtime still requires one selected renderer and one pipeline for the lowered scene, but can draw multiple object vertex ranges from a merged vertex buffer.

Generated config markers:

```txt
ARQEN_M23_OBJECT_METADATA
ARQEN_M23_OBJECT_COUNT
ARQEN_M23_OBJECT_MODE
ARQEN_M23_MULTI_DRAW_ENABLED
ARQEN_M23_DRAW_CALL_COUNT
ARQEN_M23_DRAW_CALL_DATA
```

Generated manifest markers:

```txt
M23_SCENE_OBJECTS
M23_OBJECT_BINDINGS
M23_DRAW_CALLS
M23_OBJECT_MODE
M23_MULTI_DRAW
OBJECT
OBJECT_BIND
DRAW_CALL_N
```

## Boundary

M23 does not introduce transforms, cameras, input actions, materials, depth, scene graph parenting, or multiple native pipelines in one scene. Those belong to later milestones. M23 is the first real scene object/multi-draw layer, not the whole engine wearing a fake mustache.

## Official samples/tools

- `Samples/DX12/dx12_multi_object_scene_m23c.arq`
- `Samples/DX12/dx12_explicit_multi_draw_m23c.arq`
- `Tools/build_m23c_dx12_multi_object_scene.ps1`
- `Tools/validate_m23_dx12_scene_objects.ps1`
