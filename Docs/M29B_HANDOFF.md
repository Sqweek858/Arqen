# M29B handoff - UE-style viewport navigation

## Summary

M29B updates DX12 perspective camera input so viewport navigation behaves like a lightweight Unreal-style editor viewport:

- RMB hold activates mouse look and camera movement.
- Releasing RMB frees the mouse.
- WASD movement is camera-relative.
- Q/E remain vertical movement.
- `R` is not bound in the official demo.

No public syntax was added. Existing M28B syntax is reused.

## Important files

```text
Backends/DX12/Runtime/ArqenDx12ClearWindow.cpp
Backends/DX12/Runtime/build_m20e1_dx12_clear_from_ir.ps1
Tools/lower_m20e1_dx12_clear_from_ir.ps1
Samples/DX12/dx12_ue_style_viewport_navigation_scene_m29b.arq
Tools/build_m29b_dx12_ue_style_viewport_navigation_scene.ps1
Tools/validate_m29b_dx12_ue_style_viewport_navigation.ps1
Docs/M29B_DX12_UE_STYLE_VIEWPORT_NAVIGATION.md
```

## Run locally

```powershell
Set-Location "C:\Users\Sqweek\Documents\Arqen\Arqen"
.\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail
.\Tools\validate_m29b_dx12_ue_style_viewport_navigation.ps1
.\Tools\build_m29b_dx12_ue_style_viewport_navigation_scene.ps1 -BuildNative -RunNative -KeepOpen
```

## Expected behavior

Start the demo. The cursor should remain free. Hold RMB to enter viewport navigation. While RMB is held, mouse movement rotates the perspective camera and WASD/QE move relative to the camera. Release RMB and the cursor should become free again.

## Non-scope

No gizmo, no selection, no object rotate tool, no key remapping, no physics/collision, and no editor UI were added.
