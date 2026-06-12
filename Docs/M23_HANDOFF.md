# M23 Handoff - DX12 Real Scene Objects

## Status

M23A/M23B/M23C add real DX12 scene object metadata and multi-draw native lowering.

## Public syntax

Preferred simple object syntax:

```arq
define object called "CrystalA"
draw "CrystalA"
```

Object bindings:

```arq
use renderer "MainRenderer" for object "CrystalA"
use pipeline "CrystalPipeline" for object "CrystalA"
use vertex buffer "CrystalAVertices" for object "CrystalA"
draw 12 vertices for object "CrystalA"
```

Explicit low-level multi-draw syntax:

```arq
draw 3 vertices from buffer "ShardA" with pipeline "CrystalPipeline" using renderer "MainRenderer"
```

## Implementation map

- Parser: `Tools/M10GDriver/Parser/Parser.Dx12.cs`
- Models: `Tools/M10GDriver/Core/Models.cs`
- AST/IR emit: `Tools/M10GDriver/Frontend/AstEmit.cs`, `Tools/M10GDriver/Frontend/IrEmit.cs`
- Lowering: `Tools/lower_m20e1_dx12_clear_from_ir.ps1`
- Native runtime: `Backends/DX12/Runtime/ArqenDx12ClearWindow.*`
- Native build helper: `Backends/DX12/Runtime/build_m20e1_dx12_clear_from_ir.ps1`

## Validation

Run after applying M23 and rebuilding the driver:

```powershell
.\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -Case m23
.\Tools\validate_m23_dx12_scene_objects.ps1
.\Tools\build_m23c_dx12_multi_object_scene.ps1 -BuildNative -RunNative -KeepOpen
```

## Known limits

M23C native scene lowering supports multiple draw calls with one selected renderer and one native pipeline. It merges source vertex buffers into a generated native vertex buffer and emits per-object draw ranges. Multiple pipelines, transforms, camera, input and scene graph are intentionally left for M24+.
