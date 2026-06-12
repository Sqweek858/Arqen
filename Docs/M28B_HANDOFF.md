# M28B Handoff

M28B completes the first native DX12 peripheral input slice.

## Added

- `capture mouse for window "MainWindow"`
- `when mouse moves rotate camera "MainCamera" by [x, y]`
- `when mouse wheel moves move camera "MainCamera" by [x, y, z]`
- `when mouse button "Left" is held move camera "MainCamera" by [x, y, z]`
- `when mouse button "Right" is pressed reset camera "MainCamera"`
- `when mouse button "Middle" is pressed toggle animation`
- Q/E keyboard bindings remain regular M26 key bindings and are now documented for vertical perspective movement.

## Files to run

```powershell
.\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail
.\Tools\validate_m28b_dx12_full_peripheral_input.ps1
.\Tools\build_m28b_dx12_full_peripheral_input_scene.ps1 -BuildNative -RunNative -KeepOpen
```

## Important runtime note

Before M28B, generated DX12 windows allowed `Q` to close. M28B disables Q-close only when `ARQEN_M28B_PERIPHERAL_INPUT_ENABLED` is true, so Q can act as vertical down movement. Esc still closes.

## Not included

No key remapping, controller input, collision, physics, UI widgets, mouse picking, material system, lighting, scene graph, or mesh import.
