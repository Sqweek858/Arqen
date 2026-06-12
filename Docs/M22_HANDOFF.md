# M22 Handoff - DX12 Mini Scene

M22 is complete when `validate_m22_dx12_mini_scene_contract.ps1` passes and the M22I wrapper can lower the crystal scene into manifest/config output.

## Added artifacts

- `Docs/M22_DX12_MINI_SCENE.md`
- `Docs/M22_HANDOFF.md`
- `Samples/DX12/dx12_crystal_cluster_m22a.arq`
- `Samples/DX12/dx12_crystal_scene_m22i.arq`
- `Tools/new_m22b_dx12_crystal_cluster_sample.ps1`
- `Tools/build_m22i_dx12_crystal_scene.ps1`
- `Tools/validate_m22_dx12_mini_scene_contract.ps1`

## Runtime change

The generated DX12 smoke executable now supports keep-open mode through `-KeepOpen` on the lowering/build wrappers. The lowerer emits frame count zero and the runtime interprets zero as render-until-window-quit. The generated WndProc also supports Escape and Q to close.

## Boundary

M22 still uses the existing experimental DX12 smoke bridge. It does not promote DX12 actions to the main WindowsX64PE backend capability table. The backend capability boundary remains unsupported for DX12 families.

## Recommended validation

```powershell
.\Toolsalidate_m21h_dx12_color_animation.ps1
.\Toolsalidate_m21i_dx12_color_animation_smoke_polish.ps1
.\Toolsalidate_m21j_dx12_color_animation_metadata_hardening.ps1
.\Toolsalidate_m22_dx12_mini_scene_contract.ps1
```

## Recommended visual smoke

```powershell
.\Toolsuild_m22i_dx12_crystal_scene.ps1 -BuildNative -RunNative -Frames 480 -Fps 60 -Hold 8000
```

For an indefinite window:

```powershell
.\Toolsuild_m22i_dx12_crystal_scene.ps1 -BuildNative -RunNative -KeepOpen
```

Close with Escape, Q, or the window close button.
