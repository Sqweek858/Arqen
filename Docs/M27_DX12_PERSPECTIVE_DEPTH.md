# M27 DX12 Perspective Camera + Depth Buffer

M27 turns the M24/M25/M26 scene slice from flat 2.5D into the first controlled 3D runtime path. It is still deliberately small. No scene graph, no mouse input, no lighting, no materials/textures, and no mesh import are included here. Those stay out so M27 does not mutate into a hydra with a renderer attached.

## M27A - bible / contracts

M27A defines the public syntax and the metadata contract for perspective camera support.

Public syntax:

```arq
define camera called "MainCamera"
use camera "MainCamera" for renderer "MainRenderer"
set camera "MainCamera" projection to perspective
set position of camera "MainCamera" to [0.0, 0.0, -3.0]
set rotation of camera "MainCamera" to [0.0, 0.0, 0.0]
set field of view of camera "MainCamera" to 70 deg
set near plane of camera "MainCamera" to 0.1
set far plane of camera "MainCamera" to 100.0
```

Projection can be `orthographic` or `perspective`. If no projection is specified, the lowerer keeps the existing orthographic path for compatibility with M25/M26 samples.

Compiler metadata:

```text
DX12_CAMERA|name=MainCamera
DX12_CAMERA_USE|camera=MainCamera|renderer=MainRenderer
DX12_CAMERA_PROJECTION|camera=MainCamera|projection=perspective
DX12_CAMERA_TRANSFORM|camera=MainCamera|property=position|value=[0.000000,0.000000,-3.000000]
DX12_CAMERA_TRANSFORM|camera=MainCamera|property=rotation|value=[0.000000,0.000000,0.000000]
DX12_CAMERA_TRANSFORM|camera=MainCamera|property=fov_y_degrees|value=70.000000
DX12_CAMERA_TRANSFORM|camera=MainCamera|property=near_plane|value=0.100000
DX12_CAMERA_TRANSFORM|camera=MainCamera|property=far_plane|value=100.000000
```

Semantic rules:

- Camera must be defined before projection/transform/use statements.
- A camera can have only one projection statement.
- Perspective projection requires FOV, near plane, and far plane in lowering.
- FOV must be greater than 1 and less than 179 degrees.
- Near and far planes must be positive.
- Far plane must be greater than near plane.
- Orthographic camera syntax from M25 remains valid.

## M27B - depth buffer runtime

M27B adds native DX12 depth support only when the generated config enables it.

Runtime contract:

- Create a DSV heap.
- Create a `DXGI_FORMAT_D32_FLOAT` depth stencil resource.
- Enable PSO depth testing with `D3D12_DEPTH_WRITE_MASK_ALL` and `D3D12_COMPARISON_FUNC_LESS_EQUAL`.
- Bind the DSV with the render target.
- Clear depth every frame with `ClearDepthStencilView(..., 1.0f, ...)`.
- Keep the old orthographic path working when perspective/depth is disabled.

## M27C - lowering/runtime/sample

M27C lowers perspective metadata into generated config markers and feeds the native runtime descriptor.

Generated manifest markers:

```text
M27_DEPTH_BUFFER|True
M27_CAMERA_PROJECTION|perspective
M27_PERSPECTIVE_CAMERA|True
M27_CAMERA_ROTATION|0.000000f,0.000000f,0.000000f
M27_CAMERA_FOV|70.000000f
M27_CAMERA_NEAR|0.100000f
M27_CAMERA_FAR|100.000000f
```

Generated config markers:

```c
#define ARQEN_M27_DEPTH_BUFFER 1
#define ARQEN_M27_DEPTH_BUFFER_ENABLED 1
#define ARQEN_M27_CAMERA_PROJECTION "perspective"
#define ARQEN_M27_PERSPECTIVE_CAMERA_ENABLED 1
#define ARQEN_M27_PERSPECTIVE_CAMERA_DATA { ... }
```

Official sample:

```text
Samples\DX12\dx12_perspective_depth_scene_m27c.arq
```

Run sample:

```powershell
.\Tools\build_m27c_dx12_perspective_depth_scene.ps1 -BuildNative -RunNative -KeepOpen
```

Validate M27:

```powershell
.\Tools\validate_m27_dx12_perspective_depth.ps1
Get-Content .\Build\Generated\m27_dx12_perspective_depth_validation.txt
```

## Explicit non-goals

- No scene graph parenting.
- No UI DX12 rendering.
- No mouse input.
- No materials/textures.
- No lighting.
- No mesh import.
- No M27D/M27E scope creep.

M27 is just camera projection + depth buffer + one official perspective/depth scene. Revolutionary restraint, apparently still legal.
