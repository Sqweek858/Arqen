# Arqen DX12 Runtime Bridge (M20A)

This folder is the first DX12 implementation slice. It is intentionally native backend/runtime source, not public Arqen syntax.

## Files

```text
ArqenDx12ClearWindow.h
ArqenDx12ClearWindow.cpp
ArqenDx12ClearSmoke.cpp
build_m20a_dx12_clear.ps1
```

## Boundary

`ArqenDx12ClearWindowOnce` accepts a caller-owned `HWND`. This keeps the M20A bridge aligned with the runtime contract: DX12 must reuse or explicitly receive the window handle created by the window runtime.

The smoke executable may create a temporary Win32 window only to validate the bridge outside the compiler pipeline. That window is not compiler support and does not flip any capability flag.

## Current status

```text
native bridge: source present
compiler integration: not wired yet
Arqen grammar: unchanged
ARQIR actions: unchanged
capabilities: dx12/shader/render_pass/frame_update remain unsupported
```

## M20E1 generated clear smoke

M20E1 adds an optional generated smoke build path:

```powershell
.\Backends\DX12\Runtime\build_m20e1_dx12_clear_from_ir.ps1 -IrPath .\Build\IR\dx12_clear_m20e1.arqir
```

That script calls `Tools\lower_m20e1_dx12_clear_from_ir.ps1`, generates `Build\M20E1\dx12_clear_config.generated.h`, then builds a temporary smoke executable against `ArqenDx12ClearWindowOnce`.

This remains experimental/manual. Standard regression tests validate the lowering contract and generated config behavior, not GPU runtime execution.

## M20I frame-aware smoke wrapper

M20I adds:

```powershell
.\Tools\build_m20i_dx12_frame_clear_smoke.ps1
```

Default mode compiles the M20H frame-clear sample and lowers it with `-RequireFrame` into `Build\M20I` manifest/config artifacts. Native DX12 build/run is optional behind `-BuildNative` and `-Run`.
