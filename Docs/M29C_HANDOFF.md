# M29C Handoff

## Goal

Add a minimal object selector and selected-object rotate tool without introducing a full editor UI/gizmo system.

## Added syntax

```arq
define object selector called "PrimarySelector"
use object selector "PrimarySelector" for renderer "MainRenderer"
when mouse button "Left" is pressed select object using "PrimarySelector"
when key "R" is held rotate selected object around y by mouse x sensitivity 0.35
```

## Sample

`Samples/DX12/dx12_object_selector_rotate_scene_m29c.arq`

Controls:

- Hold RMB: viewport navigation.
- LMB: select nearest cube.
- Hold R + move mouse X: rotate selected cube around Y.

## Tools

- `Tools/build_m29c_dx12_object_selector_rotate_scene.ps1`
- `Tools/validate_m29c_dx12_object_selector_rotate.ps1`

## Validation

```powershell
.\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail
.\Tools\validate_m29c_dx12_object_selector_rotate.ps1
.\Tools\build_m29c_dx12_object_selector_rotate_scene.ps1 -BuildNative -RunNative -KeepOpen
```


## Hotfix/QOL note

- LMB selection uses projected object bounds instead of center-only picking.
- Click in empty space deselects the selected object.
- Selected objects receive a small runtime tint feedback.
- Runtime input is ignored when the demo window is not foreground, preventing RMB/WASD leakage through other windows.
