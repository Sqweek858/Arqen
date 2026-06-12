# M28C + M29A DX12 object rotation and fake lighting

M28C adds full 3D object rotation metadata for generated DX12 scene objects. M29A adds a minimal directional fake-light contract / fake directional lighting contract for the DX12 runtime. This milestone intentionally stays small: it does not add gizmos, editor camera overhaul, mesh import, materials, textures, shadows, normal maps, or a real lighting system.

## M28C syntax

Existing M24 syntax remains valid:

```arq
set rotation z of object "CubeA" to 35 deg
```

M28C adds full vector rotation in degrees:

```arq
set rotation of object "CubeA" to [20.0, 35.0, 10.0]
```

M28C also accepts individual axes:

```arq
set rotation x of object "CubeA" to 20 deg
set rotation y of object "CubeA" to 35 deg
set rotation z of object "CubeA" to 10 deg
```

The vector form is `[pitch/x, yaw/y, roll/z]` in degrees. The runtime applies scale, then X/Y/Z rotation, then translation, then camera projection.

## M29A syntax

```arq
define directional light called "KeyLight"
use light "KeyLight" for renderer "MainRenderer"
set direction of light "KeyLight" to [-0.35, -0.70, -0.60]
set intensity of light "KeyLight" to 0.95
set ambient of light "KeyLight" to 0.16
```

The light direction must be a non-zero vec3. Intensity is clamped by the contract to 0..4, ambient to 0..1. M29A supports one directional light per renderer.

## Runtime contract

M29A is fake lighting. The runtime CPU-shades generated scene vertices before upload using a simple directional factor and an estimated local normal. This is enough to make generated boxes read as 3D without introducing real materials, normal buffers, shadow maps, or shader lighting.

## Official sample

```text
Samples/DX12/dx12_rotation3d_fake_light_scene_m29a.arq
```

## Wrapper and validator

```powershell
.\Tools\build_m29a_dx12_rotation3d_fake_light_scene.ps1 -BuildNative -RunNative -KeepOpen
.\Tools\validate_m28c_m29a_dx12_rotation_light.ps1
```

## Explicitly out of scope

- No mesh import
- No material system
- No textures
- No shadows
- No normal maps
- No gizmo
- No editor camera overhaul
- No scene graph changes
