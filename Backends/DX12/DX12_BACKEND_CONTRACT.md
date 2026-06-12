# DX12 Backend Contract (M18B Reservation)

Compiler-integrated DX12 support is not implemented yet. This file defines the contract that must exist before the backend is allowed to become `supported` in `Backends/WindowsX64PE/Config/capabilities_v0.txt`. M20A adds native bridge source only; the public compiler feature remains unsupported.

## Status

```text
backend: DX12
status: reserved / unsupported
current gate: M20A native clear bridge source present; compiler feature still unsupported
```


## M20A native clear bridge status

M20A starts implementation without exposing public Arqen syntax. The native bridge lives in:

```text
Backends/DX12/Runtime/ArqenDx12ClearWindow.h
Backends/DX12/Runtime/ArqenDx12ClearWindow.cpp
Backends/DX12/Runtime/ArqenDx12ClearSmoke.cpp
Backends/DX12/Runtime/build_m20a_dx12_clear.ps1
```

The bridge entry point is:

```text
ArqenDx12ClearWindowOnce
```

It accepts a caller-owned `HWND` plus clear color and dimensions. This is an implementation skeleton, not a public language feature, and not a compiler-emitted backend action yet.

The smoke executable may create a temporary Win32 window only to validate the bridge outside the compiler path. The compiler backend must still use an explicit window handoff and must not create hidden fake windows to pretend DX12 support exists.

## Required backend concepts

A real DX12 backend must own these concepts explicitly:

- window handle ownership or interop with the window backend
- adapter/device creation
- command queue
- command allocator
- command list
- swapchain
- render target views
- descriptor heaps
- root signature
- pipeline state objects
- shader compilation / shader bytecode loading
- resource barriers
- frame synchronization / fences
- resize handling
- artifact diagnostics

## Required IR/action families

The following operations are reserved but unsupported in M18B:

```text
dx12
shader
render_pass
frame_update
```

They must remain `unsupported` until the backend can validate and execute them.

## No fake support rule

Do not mark `dx12`, `shader`, `render_pass`, or `frame_update` as `supported` only because a parser accepts the words. Support means the backend and runtime can execute the action safely and produce diagnostics on failure.

## M20A skeleton entry criteria

The first DX12 skeleton patch is allowed to do only a real clear-color window path after M19A runtime loop rules are in place. It must prove:

- the backend receives a real window handle or documented handoff
- device/swapchain/command queue creation has diagnostics
- clear color is executed by a command list, not a fake message-box path
- the M20A bridge contains real `D3D12CreateDevice`, `CreateSwapChainForHwnd`, `ClearRenderTargetView`, `Present`, and fence synchronization calls
- `dx12`, `render_pass`, `shader`, and `frame_update` remain unsupported until each action family has IR, runtime, backend, and tests


## M20B public syntax reservation

M20B introduces renderer metadata syntax without promoting backend support:

```text
define dx12 renderer called "MainRenderer"
parent renderer "MainRenderer" to window "MainWindow"
```

This syntax records renderer identity and window ownership only. It does not execute DX12 work inside generated PE artifacts yet.

Clear color is not a separate M20B command. Renderer clear/background color is expected to come from existing style metadata:

```text
with style for "MainRenderer"
    background color: color "#101820"
end style
```

The backend must keep `dx12`, `shader`, `render_pass`, and `frame_update` unsupported until runtime/backend execution and tests exist.
## M20C style-derived clear metadata boundary

M20C adds compiler metadata for renderer clear/background style but does not add executable DX12 backend support.

Accepted metadata shape:

```text
DX12_CLEAR_STYLE|renderer=MainRenderer|state=default|kind=color|value=#101820|unit=|source=style.background_color
```

The backend may parse and ignore this metadata until a later slice consumes it to call the native DX12 bridge. This metadata does not promote `dx12`, `shader`, `render_pass`, or `frame_update` to supported.

## M20D/M20E0 semantic and readiness metadata

M20D treats DX12 renderer names as owned metadata object names and rejects collisions with variables, windows, and UI objects.

M20E0 adds `DX12_CLEAR_READY` as a derived metadata gate:

```text
DX12_CLEAR_READY|renderer=<name>|window=<window>|kind=<kind>|value=<value>|unit=<unit>|source=<source>
```

A backend may consume this line only after an explicit DX12 integration milestone defines the runtime path. Until then, the WindowsX64PE backend must continue to ignore DX12 metadata and keep `dx12`, `shader`, `render_pass`, and `frame_update` unsupported.


## M20E1 experimental clear lowering

M20E1 adds an explicit offline lowering path from `DX12_CLEAR_READY` metadata to generated native bridge config:

```text
Tools/lower_m20e1_dx12_clear_from_ir.ps1
Build/M20E1/dx12_clear_manifest.generated.txt
Build/M20E1/dx12_clear_config.generated.h
```

The optional build helper:

```text
Backends/DX12/Runtime/build_m20e1_dx12_clear_from_ir.ps1
```

generates a smoke executable that includes the generated config and calls `ArqenDx12ClearWindowOnce`.

This is not a public backend action family and not a capability promotion. `dx12`, `shader`, `render_pass`, and `frame_update` remain unsupported until a later milestone defines executable IR/runtime/backend behavior and proportional tests.
## M20F/M20G clear smoke and frame metadata

M20F defines an explicit smoke wrapper from Arqen source to M20E1 generated native config. Standard regression may run the wrapper through config generation, but native build/run remains optional and Windows-only.

M20G introduces `DX12_FRAME` metadata:

```text
DX12_FRAME|command=begin|renderer=MainRenderer
DX12_FRAME|command=clear|renderer=MainRenderer
DX12_FRAME|command=end|renderer=MainRenderer
DX12_FRAME|command=present|renderer=MainRenderer
```

The DX12 backend may consume this metadata only in a later execution milestone. M20G does not make shader, render pass, frame update, draw, or general DX12 support active.

## M20H frame-aware lowering

M20H validates the M20G one-shot frame sequence in the explicit lowerer. This is not full DX12 backend support. It only proves that metadata can be lowered into a clear-smoke bridge configuration with frame intent preserved.

Required frame sequence for `-RequireFrame`:

```text
begin,clear,end,present
```

Generated artifacts record `FRAME_MODE|oneshot_clear_frame` and `FRAME_SEQUENCE|begin,clear,end,present`.

## M20I native smoke polish

M20I adds an optional frame-aware native smoke wrapper. Standard regression validates the wrapper and generated config path without requiring GPU/runtime execution. Native build/run remains opt-in.

## M21A/M21B shader and pipeline metadata

M21A/M21B introduces file-based shader and pipeline metadata for the DX12 track:

```text
DX12_SHADER|name=<shader>|vertex=<path>|pixel=<path>
DX12_PIPELINE|name=<pipeline>|renderer=<renderer>|shader=<shader>|topology=triangle_list
DX12_PIPELINE_BIND|pipeline=<pipeline>|renderer=<renderer>
```

The backend may parse and ignore this metadata until a later execution slice implements shader compilation, root signatures, PSO creation, resource binding, and draw submission.

M21B does not call DXC, does not validate HLSL files on disk, does not create a native pipeline state object, and does not promote `dx12`, `shader`, `render_pass`, or `frame_update` support.

## M21C/M21D triangle smoke boundary

M21C introduces vertex/draw metadata: `DX12_VERTEX_BUFFER`, `DX12_VERTEX`, `DX12_VERTEX_BUFFER_BIND`, and `DX12_DRAW`.

M21D extends the experimental smoke lowerer with `-RequireTriangle`. The optional native helper may compile file-based HLSL with `D3DCompileFromFile`, create a minimal root signature and triangle-list PSO, upload generated position/color vertices, and call `DrawInstanced` for one smoke triangle.

This remains a smoke path, not general DX12 backend support. `dx12`, `shader`, `render_pass`, and `frame_update` remain unsupported capability families.

## M21G/M21H tint and animation smoke path

The experimental DX12 native smoke bridge accepts generated tint constant buffer data and optional frame-index color sequence data. This is limited to the M21D/M21F triangle smoke path and does not make the DX12 backend generally supported.
