# M21D DX12 Triangle Smoke

M21D is the first optional native path intended to draw a real triangle from Arqen-authored metadata.

## Pipeline

```text
Arqen source
-> arqc_m10g.exe
-> ARQIR with DX12 shader/pipeline/vertex/draw metadata
-> lower_m20e1_dx12_clear_from_ir.ps1 -RequireFrame -RequireTriangle
-> Build/M21D/dx12_clear_manifest.generated.txt
-> Build/M21D/dx12_clear_config.generated.h
-> optional native C++ build
-> D3DCompileFromFile + PSO + vertex upload + DrawInstanced
```

## Manual commands

```powershell
.\Tools\build_m21d_dx12_triangle_smoke.ps1
.\Tools\build_m21d_dx12_triangle_smoke.ps1 -BuildNative
.\Tools\build_m21d_dx12_triangle_smoke.ps1 -BuildNative -Run
```

Native build/run requires Visual Studio Developer PowerShell, D3D12, DXGI, and D3DCompiler availability. Normal regression does not require those.

## Boundary

This is not a full renderer. M21D supports one generated triangle-list draw for smoke validation. General draw loops, buffers, textures, root parameters, constant buffers, and render passes remain future work.


## M21E/M21F follow-up

M21E hardens the generated executable with shader fallback, `Build\EXE\Shaders` copying, runtime log output, and MessageBox diagnostics. M21F adds a fixed-frame native loop through `ArqenDx12TriangleWindowRunFrames`; this keeps the triangle presented across multiple frames and avoids a fragile one-shot draw after window creation.
