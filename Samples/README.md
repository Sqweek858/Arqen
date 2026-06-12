# Arqen Samples

## Current Canonical Sample

```text
Samples\hello_m10.arq
```

Source:

```text
program "Hello"

let name be "Sqweek"
let number be 0
let active be true

title "Arqen Byte Zero"
message text "Hello, " + name
exit 0

end program "Hello"
```

## How To Compile Today

Current normal workflow:

```powershell
cd C:\Users\Sqweek\Documents\Arqen\Arqen
.\Tools\arqc_m10g.exe .\Samples\hello_m10.arq
.\Build\EXE\hello_m10.exe
```

Expected output:

```text
MessageBoxW title: Arqen Byte Zero
MessageBoxW text:  Hello, Sqweek
Exit code: 0
```

## Current Limitations

- Current driver is `Tools\arqc_m10g.exe`, not final `arqc.exe`.
- `let` values are literals only.
- `message text` is the only expression-enabled field.
- `+` supports text concatenation only.
- No if/else, functions, loops, UI/window/style, or non-zero exit code support yet.

Debug-only old M10 manual stages remain in:

```text
Experiments\M10_SimpleExpressions
```

## M22 crystal mini scene samples

- `DX12/dx12_crystal_cluster_m22a.arq` - smaller 60-vertex crystal-cluster smoke sample.
- `DX12/dx12_crystal_scene_m22i.arq` - official 108-vertex M22 crystal mini scene with animated tint.

Run/lower/build with:

```powershell
.\Tools\build_m22i_dx12_crystal_scene.ps1 -BuildNative -RunNative -Frames 480 -Fps 60 -Hold 8000
```

Keep the native window open indefinitely with:

```powershell
.\Tools\build_m22i_dx12_crystal_scene.ps1 -BuildNative -RunNative -KeepOpen
```

## M23 real scene object samples

- `DX12/dx12_multi_object_scene_m23c.arq` - official M23C sample with real objects, object bindings, and `draw "CrystalA"` style draws.
- `DX12/dx12_explicit_multi_draw_m23c.arq` - low-level explicit multi-draw syntax sample.

Run/lower/build the official M23C object scene with:

```powershell
.\Tools\build_m23c_dx12_multi_object_scene.ps1 -BuildNative -RunNative -KeepOpen
```

## M26 interactive DX12 camera scene

- `DX12/dx12_interactive_camera_scene_m26c.arq` - M24/M25/M26 sample with real objects, per-object transforms, orthographic camera, keyboard camera movement, reset, and animation toggle.

Run it with:

```powershell
.\Tools\build_m26c_dx12_interactive_camera_scene.ps1 -BuildNative -RunNative -KeepOpen
```

Controls: `W/A/S/D` move the camera, `R` resets it, `Space` toggles color animation, `Escape`/`Q`/window close exits.

## DX12 M27 perspective/depth sample

`Samples\DX12\dx12_perspective_depth_scene_m27c.arq` is the official M27C perspective camera and depth-buffer smoke scene. It uses the existing object/draw/transform path plus:

```arq
set camera "MainCamera" projection to perspective
set position of camera "MainCamera" to [0.0, 0.0, -3.0]
set rotation of camera "MainCamera" to [0.0, 0.0, 0.0]
set field of view of camera "MainCamera" to 70 deg
set near plane of camera "MainCamera" to 0.1
set far plane of camera "MainCamera" to 100.0
```

Build/lower/native-run wrapper:

```powershell
.\Tools\build_m27c_dx12_perspective_depth_scene.ps1 -BuildNative -RunNative -KeepOpen
```


## DX12 M27D/M28A native window style + box primitive sample

- `DX12/dx12_window_style_box_scene_m28a.arq`
  - Demonstrates Arqen-driven native title bar colors on `MainWindow`.
  - Demonstrates `define box called "CubeA"` / `define box called "CubeB"` generated primitives.
  - Uses the M27 perspective/depth path, but does not add lighting, materials, mesh import, or scene graph support.

Run locally:

```powershell
.\Tools\build_m28a_dx12_window_style_box_scene.ps1 -BuildNative -RunNative -KeepOpen
```

### DX12 M28B full peripheral input

- `Samples/DX12/dx12_full_peripheral_input_scene_m28b.arq`
- Demonstrates M27D dark native title bar, M28A generated boxes, M27 perspective/depth, M26 keyboard input, and M28B mouse capture/look/buttons/wheel.

## DX12 M28C/M29A rotation + fake lighting

- `Samples/DX12/dx12_rotation3d_fake_light_scene_m29a.arq` demonstrates full 3D object rotation and fake directional lighting on generated box primitives.

- `Samples/DX12/dx12_ue_style_viewport_navigation_scene_m29b.arq` - M29B perspective DX12 sample using dark window chrome, boxes, fake lighting, RMB-held UE-style viewport navigation, and camera-relative WASD/QE movement.

- `Samples/DX12/dx12_object_selector_rotate_scene_m29c.arq` - M29C minimal object selector + selected-object Y rotate tool on top of M29B UE-style viewport navigation.
