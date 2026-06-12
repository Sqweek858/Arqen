# M20F DX12 Clear Smoke Path

M20F is an explicit smoke path that proves the M20E1 lowering flow can start from an Arqen sample and produce native DX12 bridge config.

It does not add syntax. It does not promote DX12 capability support. It does not require a GPU in standard regression.

## Default command

```powershell
.\Tools\build_m20f_dx12_clear_smoke.ps1
```

This performs:

```text
Arqen sample -> arqc_m10g.exe -> ARQIR -> M20E1 lowerer -> manifest/config header
```

## Optional native validation

```powershell
.\Tools\build_m20f_dx12_clear_smoke.ps1 -BuildNative
.\Tools\build_m20f_dx12_clear_smoke.ps1 -BuildNative -Run
```

These modes require Visual Studio Developer PowerShell, Windows SDK, and DX12 runtime availability.

## Boundary

M20F is a smoke wrapper around existing metadata and the native bridge. It is not a normal generated backend path yet.
