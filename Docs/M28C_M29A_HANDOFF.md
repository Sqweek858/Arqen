# M28C + M29A handoff

## Summary

M28C introduces full object rotation metadata for DX12 object transforms. M29A introduces a minimal directional fake-light contract that is lowered into native DX12 config and applied in the runtime CPU vertex update path.

## New sample

```text
Samples/DX12/dx12_rotation3d_fake_light_scene_m29a.arq
```

## New wrapper

```powershell
.\Tools\build_m29a_dx12_rotation3d_fake_light_scene.ps1 -BuildNative -RunNative -KeepOpen
```

## New validator

```powershell
.\Tools\validate_m28c_m29a_dx12_rotation_light.ps1
Get-Content .\Build\Generated\m28c_m29a_dx12_rotation_light_validation.txt
```

## Test slice

The parser changed, so run:

```powershell
.\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail
```

## Scope guard

M28C/M29A are not gizmo, mesh import, material, texture, shadow, or editor-camera milestones. They only make existing generated box scenes more spatially correct and easier to read.
