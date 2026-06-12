# M29B - DX12 UE-style viewport navigation QoL

M29B is a runtime/QoL milestone layered on top of M28B/M28C/M29A. It does not add new public syntax. It changes the runtime contract for the existing `capture mouse for window` + perspective camera input path so the demo behaves more like an Unreal-style viewport.

## User-facing behavior

When a DX12 perspective scene uses:

```arq
capture mouse for window "MainWindow"
when mouse moves rotate camera "MainCamera" by [0.10, 0.10]
when key "W" is held move camera "MainCamera" by [0.0, 0.0, 3.0]
when key "S" is held move camera "MainCamera" by [0.0, 0.0, -3.0]
when key "A" is held move camera "MainCamera" by [-3.0, 0.0, 0.0]
when key "D" is held move camera "MainCamera" by [3.0, 0.0, 0.0]
when key "Q" is held move camera "MainCamera" by [0.0, -3.0, 0.0]
when key "E" is held move camera "MainCamera" by [0.0, 3.0, 0.0]
```

runtime behavior is:

- RMB held: mouse look is active.
- RMB held: WASD/QE movement is active.
- RMB held: movement is camera-relative for the perspective camera.
- RMB released: mouse look is inactive.
- RMB released: WASD/QE camera movement is ignored.
- RMB released: cursor is visible/free and can be used to move the window, click elsewhere, or take screenshots.

This replaces the old permanent capture behavior where entering the window could lock/warp the cursor continuously. Humanity survives another input bug. Barely.

## Camera-relative movement

For perspective cameras, local input vectors are interpreted as:

- local X = camera right/left;
- local Z = camera forward/back;
- Y = vertical world up/down for Q/E style movement.

This keeps Q/E as clean vertical movement while W/S and A/D follow the current mouse look direction.

## Official sample

```text
Samples/DX12/dx12_ue_style_viewport_navigation_scene_m29b.arq
```

Controls:

```text
Hold RMB  -> enable viewport navigation
Mouse     -> look while RMB is held
W/S       -> camera-relative forward/back while RMB is held
A/D       -> camera-relative left/right while RMB is held
Q/E       -> down/up while RMB is held
Mouse wheel -> camera dolly while RMB is held
Space     -> toggle color animation
Release RMB -> free cursor
```

`R` is intentionally not bound in this sample. Reset is not hardcoded and remains regular Arqen keybind syntax if a later sample wants it.

## Explicit non-scope

M29B does not implement:

- No gizmo.
- No selection.
- No object picking.
- No key remapping.
- No editor UI.
- No collision.
- No physics.
- No camera smoothing.
- No controller/gamepad.

A rotate tool can be added in a later milestone once object selection/pivot/gizmo contracts exist. For now M29B only fixes viewport navigation feeling.

## Validation

```powershell
.\Tools\validate_m29b_dx12_ue_style_viewport_navigation.ps1
Get-Content .\Build\Generated\m29b_dx12_ue_style_viewport_navigation_validation.txt
```

Demo:

```powershell
.\Tools\build_m29b_dx12_ue_style_viewport_navigation_scene.ps1 `
  -BuildNative `
  -RunNative `
  -KeepOpen
```
