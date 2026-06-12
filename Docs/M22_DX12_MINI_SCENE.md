# M22 DX12 Mini Scene

M22 turns the M21 animated triangle path into a small, visible DX12 mini scene without promoting DX12 to the main backend capability table. It deliberately reuses the existing public syntax: renderer/window parenting, style-derived clear color, shader/pipeline metadata, vertex buffer metadata, draw metadata, constant-buffer tint metadata, and color animation metadata.

The point of M22 is not a scene graph yet. The point is to make the current vertical slice feel alive: generated crystal-cluster geometry, a bigger vertex buffer, animated tint, a reusable wrapper, and a native window that can stay open until the user closes it.

## M22A - Mini scene bible

The mini-scene path stays inside the current M20/M21 contract. A mini scene is one renderer, one window, one pipeline, one vertex buffer, one draw call, and optional animated tint. The visual richness comes from generated vertex data, not from new grammar.

## M22B - Crystal generator

`Tools/new_m22b_dx12_crystal_cluster_sample.ps1` generates `.arq` samples using the existing DX12 syntax. It creates deterministic crystal shards as triangle-list geometry and writes a valid vertex buffer plus draw count.

## M22C - Crystal cluster sample

`Samples/DX12/dx12_crystal_cluster_m22a.arq` is the small official smoke sample. It draws 60 generated vertices through the existing triangle path.

## M22D - Mini scene wrapper

`Tools/build_m22i_dx12_crystal_scene.ps1` compiles and lowers the official crystal scene. Native build/run remains optional and Windows-only, exactly like the M21D/M21H wrappers. The wrapper checks M22 manifest/config markers and requires a larger generated vertex buffer.

## M22E - Keep-open runtime mode

The lowerer accepts `-KeepOpen`. In this mode it emits `FRAME_COUNT|0`, `FRAME_LOOP_MODE|keep_open_until_close`, `M22_KEEP_OPEN|True`, and `ARQEN_M22_KEEP_OPEN 1`. The runtime treats frame count zero as an infinite render loop that stops only when the window quits.

This fixes the old smoke behavior where the native window stayed open for only a fixed frame/hold duration.

## M22F - Minimal input close

The generated native window procedure handles Escape and Q as close shortcuts. The close box still works. This is not a full input system, just a controlled smoke-path exit so keep-open does not trap the user inside a tiny GPU terrarium.

## M22G - M22 manifest/config markers

The lowerer emits:

```text
M22_MINI_SCENE|True
M22_KEEP_OPEN|True/False
M22_FRAME_MODE|fixed_frame_count|keep_open_until_close
M22_VERTEX_CLUSTER|vertices=N|draw=N
```

and config macros:

```c
#define ARQEN_M22_MINI_SCENE 1
#define ARQEN_M22_KEEP_OPEN 0/1
#define ARQEN_M22_FRAME_MODE "..."
#define ARQEN_M22_VERTEX_CLUSTER_COUNT N
```

## M22H - Validation

`Tools/validate_m22_dx12_mini_scene_contract.ps1` checks docs, samples, generator, wrapper, lowerer markers, native keep-open source, compile/lower output, keep-open output, and the unsupported DX12 backend capability boundary.

## M22I - Official crystal mini scene

`Samples/DX12/dx12_crystal_scene_m22i.arq` is the final M22 visible demo. It draws 108 generated vertices, uses animated tint, and can be launched with fixed duration or keep-open mode.

Recommended fixed run:

```powershell
.\Toolsuild_m22i_dx12_crystal_scene.ps1 -BuildNative -RunNative -Frames 480 -Fps 60 -Hold 8000
```

Recommended indefinite run:

```powershell
.\Toolsuild_m22i_dx12_crystal_scene.ps1 -BuildNative -RunNative -KeepOpen
```

Close with the window X, Escape, or Q.

## Non-goals

M22 does not add textures, materials, object metadata, transforms, cameras, depth, scene graphs, model import, ECS, editor UI, or general input actions. Those become separate milestones after the mini-scene smoke path is stable.
