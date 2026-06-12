# M20I DX12 Native Smoke Polish

M20I is a polishing slice for the frame-aware DX12 smoke path.

It does not add public syntax and does not promote DX12 capabilities.

## Default flow

```powershell
.\Tools\build_m20i_dx12_frame_clear_smoke.ps1
```

Default mode performs:

```text
Samples\DX12\dx12_frame_clear_smoke_m20h.arq
-> arqc_m10g.exe
-> Build\IR\dx12_frame_clear_smoke_m20h.arqir
-> lower_m20e1_dx12_clear_from_ir.ps1 -RequireFrame
-> Build\M20I\dx12_clear_manifest.generated.txt
-> Build\M20I\dx12_clear_config.generated.h
```

## Optional native flow

```powershell
.\Tools\build_m20i_dx12_frame_clear_smoke.ps1 -BuildNative
.\Tools\build_m20i_dx12_frame_clear_smoke.ps1 -BuildNative -Run
```

These modes require a Visual Studio Developer PowerShell or Command Prompt and DX12 runtime availability.

## Boundary

M20I validates the explicit smoke bridge path only. It is not normal compiler-emitted DX12 execution.

The following remain unsupported:

```text
dx12
shader
render_pass
frame_update
```
