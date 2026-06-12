# M27 Handoff - DX12 Perspective + Depth

## Scope completed

M27A/B/C introduces the first real 3D camera/depth slice on top of the M23 object draw path and M24 transform runtime.

Included:

- Perspective camera syntax and metadata.
- Strict IR support for `DX12_CAMERA_PROJECTION`.
- Lowerer config/manifest markers for perspective camera and depth buffer.
- Native DX12 DSV/depth resource creation, clearing, and depth-stencil PSO state.
- Runtime CPU-side perspective projection for generated scene vertices.
- Official sample: `Samples\DX12\dx12_perspective_depth_scene_m27c.arq`.
- Wrapper: `Tools\build_m27c_dx12_perspective_depth_scene.ps1`.
- Validator: `Tools\validate_m27_dx12_perspective_depth.ps1`.
- Positive and negative command tests for perspective syntax.

## Local validation commands

Because parser C# changed, rebuild the driver during the slice test:

```powershell
Set-Location "C:\Users\Sqweek\Documents\Arqen\Arqen"
.\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail
.\Tools\validate_m27_dx12_perspective_depth.ps1
Get-Content .\Build\Generated\m27_dx12_perspective_depth_validation.txt
```

Native demo:

```powershell
.\Tools\build_m27c_dx12_perspective_depth_scene.ps1 `
  -BuildNative `
  -RunNative `
  -KeepOpen
```

## Syntax contract

```arq
set camera "MainCamera" projection to perspective
set rotation of camera "MainCamera" to [0.0, 0.0, 0.0]
set field of view of camera "MainCamera" to 70 deg
set near plane of camera "MainCamera" to 0.1
set far plane of camera "MainCamera" to 100.0
```

Existing orthographic syntax remains valid:

```arq
set position of camera "MainCamera" to [0.0, 0.0, 0.0]
set zoom of camera "MainCamera" to 1.0
```

## Next safe milestone candidates

Do not jump into scene graph, materials, lighting, mouse input, or mesh import from this patch. The sane next step would be a small M27D/M28 decision document and then one tiny vertical slice. Yes, restraint. Horrifying concept, but useful.
