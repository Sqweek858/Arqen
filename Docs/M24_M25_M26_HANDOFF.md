# M24/M25/M26 Handoff

## Completed scope

- M24: per-object transform metadata and runtime transform application.
- M25: orthographic camera metadata and runtime camera application.
- M26: keyboard input metadata and runtime keyboard handling.

## Public syntax covered

```arq
set position of object "Core" to [0.0, 0.0, 0.0]
set rotation z of object "Core" to 45 deg
set scale of object "Core" to [1.25, 1.25, 1.0]

define camera called "MainCamera"
use camera "MainCamera" for renderer "MainRenderer"
set position of camera "MainCamera" to [0.0, 0.0, 0.0]
set zoom of camera "MainCamera" to 1.0

when key "W" is held move camera "MainCamera" by [0.0, 0.75, 0.0]
when key "R" is pressed reset camera "MainCamera"
when key "Space" is pressed toggle animation
```

## Tools

- `Tools\build_m26c_dx12_interactive_camera_scene.ps1`
- `Tools\validate_m24_m25_m26_dx12_runtime_scene.ps1`

## Official sample

- `Samples\DX12\dx12_interactive_camera_scene_m26c.arq`

## Validation

```powershell
.\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail
.\Tools\validate_m24_m25_m26_dx12_runtime_scene.ps1
```

## Runtime test

```powershell
.\Tools\build_m26c_dx12_interactive_camera_scene.ps1 -BuildNative -RunNative -KeepOpen
```

## Boundary

This milestone intentionally stops before scene graph parenting, DX12 UI widgets, text rendering, mouse picking, and material/texture systems. Those should be introduced as later milestones with their own samples and validators.
