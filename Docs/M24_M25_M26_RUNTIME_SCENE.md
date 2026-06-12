# M24/M25/M26 DX12 Runtime Scene Controls

M24/M25/M26 extends the M23 real object path into an interactive runtime scene slice.

## M24 - object transform runtime

M24 adds per-object transform metadata and runtime vertex-buffer transform application.

Public syntax:

```arq
set position of object "ShardA" to [0.35, 0.10, 0.0]
set rotation z of object "ShardA" to 35 deg
set scale of object "ShardA" to [0.8, 1.3, 1.0]
```

The compiler emits `DX12_OBJECT_TRANSFORM` metadata. The lowerer emits `ARQEN_M24_OBJECT_TRANSFORM_DATA` and enables `M24_TRANSFORM_RUNTIME`. The runtime applies position, rotation-z, and scale to the object draw vertices before camera conversion.

## M25 - orthographic camera

M25 adds camera metadata and a renderer camera binding.

Public syntax:

```arq
define camera called "MainCamera"
use camera "MainCamera" for renderer "MainRenderer"
set position of camera "MainCamera" to [0.0, 0.0, 0.0]
set zoom of camera "MainCamera" to 1.0
```

The compiler emits `DX12_CAMERA`, `DX12_CAMERA_USE`, and `DX12_CAMERA_TRANSFORM`. The lowerer emits `ARQEN_M25_CAMERA_DATA` and enables `M25_ORTHOGRAPHIC_CAMERA`. The runtime uses an orthographic camera only; perspective projection remains future work.

## M26 - keyboard input runtime

M26 adds keyboard input metadata consumed by the native DX12 runtime.

Public syntax:

```arq
when key "W" is held move camera "MainCamera" by [0.0, 0.75, 0.0]
when key "S" is held move camera "MainCamera" by [0.0, -0.75, 0.0]
when key "A" is held move camera "MainCamera" by [-0.75, 0.0, 0.0]
when key "D" is held move camera "MainCamera" by [0.75, 0.0, 0.0]
when key "R" is pressed reset camera "MainCamera"
when key "Space" is pressed toggle animation
```

The compiler emits `DX12_KEY_BINDING`. The lowerer emits `ARQEN_M26_KEY_BINDING_DATA` and enables keyboard handling in the native runtime.

## Official sample

`Samples\DX12\dx12_interactive_camera_scene_m26c.arq` is the official M26 scene sample. It contains real M23 objects, M24 object transforms, an M25 orthographic camera, and M26 keyboard input.

Run it with:

```powershell
.\Tools\build_m26c_dx12_interactive_camera_scene.ps1 -BuildNative -RunNative -KeepOpen
```

Controls:

- `W/A/S/D`: move camera
- `R`: reset camera
- `Space`: toggle color animation
- `Escape`, `Q`, or window close: exit

## Current boundary

M24/M25/M26 deliberately do not implement scene graph parenting, DX12 UI rendering, mouse hit testing, text rendering, texture-backed UI, or material systems. Those remain explicit future work so the runtime scene path stays testable instead of turning into a decorative swamp with shaders.
