# M20 Handoff: DX12 Skeleton Discipline

M20 starts the DX12 phase without changing the public Arqen language surface yet.

The M20 rule is simple: DX12 must become real from the backend/runtime side first, then the parser/IR surface can be added in a later slice. A parsed keyword without a device, swapchain, command list, fence, diagnostics, and tests is not support.

## Current M20A scope

M20A is the first native DX12 skeleton slice. It adds a small, explicit DX12 clear-color runtime bridge source under `Backends/DX12/Runtime`.

M20A may add:

```text
native DX12 source files
native build/smoke helper script
static contract validator
DX12/backend/runtime docs
```

M20A must not add yet:

```text
new Arqen grammar
new AST nodes
new ARQIR actions
new supported capability flags
shader language
render pass language
frame_update language/runtime values
UI drawing
render graph
material system
mesh/texture pipeline
```

## Why no public command in M20A

The current compiler emits Windows PE artifacts directly through `WindowsX64PE` backend code. Injecting a real D3D12 runtime into that generated PE is a larger backend milestone than a safe first DX12 slice.

M20A therefore proves the native DX12 path separately, with a callable bridge that accepts a real `HWND` handoff:

```text
ArqenDx12ClearWindowOnce(HWND + clear color + dimensions)
```

Later M20 slices can wire this into the generated backend after the handoff, build strategy, and diagnostics are stable.

## Native bridge requirements

The M20A native bridge must contain real DX12 calls, not a fake GDI clear:

```text
D3D12GetDebugInterface / optional debug layer
CreateDXGIFactory2
D3D12CreateDevice
ID3D12CommandQueue
IDXGISwapChain for HWND
RTV descriptor heap
ID3D12CommandAllocator
ID3D12GraphicsCommandList
resource barriers
ClearRenderTargetView
Present
ID3D12Fence + wait event
```

## Capability rule

These entries remain unsupported in `Backends/WindowsX64PE/Config/capabilities_v0.txt` during M20A:

```text
dx12|unsupported
shader|unsupported
render_pass|unsupported
frame_update|unsupported
```

If any of those become supported before a compiler-emitted ARQIR action has a real backend/runtime path and tests, the milestone is invalid.

## Test discipline

Because M20A adds no public Arqen command, it does not add command syntax tests.

Instead, M20A adds static/backend contract validation:

```powershell
.\Tools\validate_m20a_dx12_contract.ps1
```

When a later M20 slice adds language commands, every new command needs proportional positive and negative tests. Minimum rule:

```text
1 valid syntax/semantic test per command
1 invalid syntax/parser/semantic test per command
```

Ten new commands means at least twenty new command tests. Tiny green lies are still lies, even if they wear a cute compiler hat.

## M20A done means

```text
DX12 bridge source exists
bridge accepts HWND instead of creating hidden fake compiler windows
bridge contains real D3D12 clear path
static validator passes
existing DX12 reserved unsupported gate still passes
no parser/lexer changes were required
no capability flags were promoted
full regression still passes on Windows
```

## Next likely slice

M20B should choose one integration path before adding grammar:

```text
Option A: generated PE imports a native DX12 support DLL/static runtime
Option B: compiler emits a native host project for DX12 targets
Option C: backend grows direct PE emission for DX12 imports/COM calls
```

M20B deliberately adds only metadata parser work to lock the public renderer syntax. It does not choose the compiler-emitted DX12 runtime integration path and does not promote backend support.


## M20B DX12 renderer metadata syntax

M20B saves the first public DX12 language surface as metadata only. It does not promote `dx12`, `shader`, `render_pass`, or `frame_update` capabilities.

Implemented M20B syntax:

```text
define dx12 renderer called "MainRenderer"
parent renderer "MainRenderer" to window "MainWindow"
```

Renderer clear/background color is intentionally style-derived instead of adding a duplicate `set clear color` command:

```text
with style for "MainRenderer"
    background color: color "#101820"
end style
```

M20B emits metadata lines only:

```text
DX12_RENDERER|name=MainRenderer
DX12_PARENT|renderer=MainRenderer|window=MainWindow
```

The WindowsX64PE backend accepts these metadata lines through strict IR parsing but ignores them until a later DX12 backend slice consumes renderer metadata and style-derived clear color.
## M20C DX12 style bridge metadata

M20C keeps the same public DX12 syntax from M20B and adds the first compiler-visible bridge between renderer metadata and existing style metadata.

No new public DX12 command is introduced in M20C.

The clear/background color path remains style-derived:

```text
with style for "MainRenderer"
    background color: color "#101820"
end style
```

M20C emits one additional metadata line when a default renderer style provides `background color`:

```text
DX12_CLEAR_STYLE|renderer=MainRenderer|state=default|kind=color|value=#101820|unit=|source=style.background_color
```

Style presets may also provide the renderer clear color:

```text
define style called "RendererClear"
    background color: color "#101820"
end style

use style "RendererClear" for "MainRenderer"
```

M20C semantic rules:

```text
renderer style state must be default
renderer style may only use background color
only one default clear/background source is allowed per renderer
style-derived clear remains metadata-only
```

M20C still does not emit a DX12 runtime action and still does not promote `dx12`, `shader`, `render_pass`, or `frame_update` capabilities.

## M20D DX12 semantic hardening

M20D strengthens the M20B/M20C renderer metadata rules without adding new public DX12 commands and without promoting backend capability support.

M20D keeps this syntax as the public renderer surface:

```text
define dx12 renderer called "MainRenderer"
parent renderer "MainRenderer" to window "MainWindow"

with style for "MainRenderer"
    background color: color "#101820"
end style
```

M20D adds stricter name ownership and semantic hygiene:

```text
DX12 renderer names conflict with variables, windows, and UI objects
variables may not reuse DX12 renderer names after renderer definition
windows may not reuse DX12 renderer names after renderer definition
parent renderer still requires a known renderer and a known window
parenting to a UI object name through the window slot remains invalid
renderer style stays default-state background-color-only
```

M20D still does not add frame commands, clear/present commands, shaders, render passes, or public runtime execution.

## M20E0 DX12 clear-readiness metadata gate

M20E0 adds derived readiness metadata. It does not add public syntax.

When a renderer has all required metadata for a future clear-color slice:

```text
DX12_RENDERER
DX12_PARENT
DX12_CLEAR_STYLE
```

compiler output also emits:

```text
DX12_CLEAR_READY|renderer=MainRenderer|window=MainWindow|kind=color|value=#101820|unit=|source=style.background_color
```

This line means only that the compiler has enough metadata for a later backend slice to wire the renderer to the native DX12 clear bridge. It is not an executable runtime action and it does not make `dx12` supported.

M20E0 readiness is metadata-only:

```text
no ACTION line is emitted
no capability flag is promoted
WindowsX64PE still ignores DX12 metadata
native DX12 bridge remains separate until an explicit integration milestone
```

M20E0 sample programs:

```text
Samples/DX12/dx12_clear_ready_m20e0.arq
Samples/DX12/dx12_renderer_style_metadata_only_m20e0.arq
```


## M20E1 DX12 experimental clear lowering

M20E1 connects the M20E0 `DX12_CLEAR_READY` metadata to the native M20A DX12 clear bridge through an explicit lowering tool. It still does not add public frame commands and it still does not promote `dx12` support.

M20E1 consumes existing IR metadata:

```text
DX12_RENDERER
DX12_PARENT
DX12_CLEAR_STYLE
DX12_CLEAR_READY
ACTION|op=window_create
ACTION|op=window_set_title      optional
ACTION|op=window_set_resolution optional
```

The lowering path is:

```text
Arqen source -> ARQIR metadata -> Tools/lower_m20e1_dx12_clear_from_ir.ps1 -> generated native bridge config
```

The generated files are:

```text
Build/M20E1/dx12_clear_manifest.generated.txt
Build/M20E1/dx12_clear_config.generated.h
```

The manifest/config are inputs for the optional Windows-only native smoke builder:

```powershell
.\Backends\DX12\Runtimeuild_m20e1_dx12_clear_from_ir.ps1 -IrPath .\Build\IR\dx12_clear_m20e1.arqir
```

This path means only `DX12_CLEAR_READY -> generated native bridge config`. It is not a general renderer, not a frame loop, and not a supported public DX12 runtime action.

M20E1 keeps these boundaries:

```text
no new public syntax
no clear renderer command
no present renderer command
no frame_update support
no shader/render_pass support
WindowsX64PE still ignores DX12 metadata during normal backend emission
```

M20E1 sample:

```text
Samples/DX12/dx12_clear_m20e1.arq
```
## M20F DX12 clear smoke path

M20F adds an explicit end-to-end smoke wrapper around the existing M20E1 lowering path. It still does not add new public syntax and does not promote DX12 capability support.

The smoke path is:

```text
Samples/DX12/dx12_clear_smoke_m20f.arq
-> Tools/arqc_m10g.exe
-> Build/IR/dx12_clear_smoke_m20f.arqir
-> Tools/lower_m20e1_dx12_clear_from_ir.ps1
-> Build/M20F/dx12_clear_manifest.generated.txt
-> Build/M20F/dx12_clear_config.generated.h
```

The wrapper is:

```powershell
.\Tools\build_m20f_dx12_clear_smoke.ps1
```

Optional Windows-only native validation is gated behind switches:

```powershell
.\Tools\build_m20f_dx12_clear_smoke.ps1 -BuildNative
.\Tools\build_m20f_dx12_clear_smoke.ps1 -BuildNative -Run
```

Standard regression must not require MSVC, a GPU, or DX12 runtime execution.

## M20G DX12 frame metadata syntax

M20G introduces the first public frame metadata commands:

```arqen
begin frame of "MainRenderer"
clear renderer "MainRenderer"
end frame of "MainRenderer"
present frame of "MainRenderer"
```

These commands emit `DX12_FRAME` metadata only. They do not create runtime `ACTION` lines and do not make the normal WindowsX64PE backend render or present DX12 frames.

M20G semantic rules:

```text
renderer must exist
renderer must be parented to a window before frame commands
clear renderer requires an active frame
clear renderer requires a default background color style
end frame requires an active frame and a prior clear
present frame requires an ended frame
only one M20G one-shot frame sequence per renderer is accepted
```

The emitted IR line shape is:

```text
DX12_FRAME|command=begin|renderer=MainRenderer
DX12_FRAME|command=clear|renderer=MainRenderer
DX12_FRAME|command=end|renderer=MainRenderer
DX12_FRAME|command=present|renderer=MainRenderer
```

`dx12`, `shader`, `render_pass`, and `frame_update` remain unsupported until a later runtime/backend milestone consumes these metadata lines with real execution and tests.

## M20H DX12 frame-aware lowering

M20H keeps the M20G frame commands metadata-only, but teaches the explicit M20E1 lowerer to understand the one-shot frame sequence:

```text
DX12_FRAME|command=begin|renderer=MainRenderer
DX12_FRAME|command=clear|renderer=MainRenderer
DX12_FRAME|command=end|renderer=MainRenderer
DX12_FRAME|command=present|renderer=MainRenderer
```

The lowerer gains `-RequireFrame`. When that switch is used, the selected renderer must have exactly one ordered frame sequence:

```text
begin,clear,end,present
```

Generated manifests include:

```text
FRAME_MODE|oneshot_clear_frame
FRAME_SEQUENCE|begin,clear,end,present
```

M20H does not make frame commands executable in the normal backend and does not promote `dx12`, `shader`, `render_pass`, or `frame_update` capabilities.

## M20I DX12 native smoke polish

M20I adds a safer wrapper for the frame-aware smoke path:

```powershell
.\Tools\build_m20i_dx12_frame_clear_smoke.ps1
.\Tools\build_m20i_dx12_frame_clear_smoke.ps1 -BuildNative
.\Tools\build_m20i_dx12_frame_clear_smoke.ps1 -BuildNative -Run
```

The default mode compiles the Arqen sample, verifies `DX12_CLEAR_READY` and `DX12_FRAME`, and lowers to generated manifest/config under `Build\M20I` without requiring native DX12 runtime.

Native build/run stays optional. Standard regression must not require MSVC, Visual Studio Developer PowerShell, a GPU, or a DX12 runtime.

## M21A/M21B bridge note

M20 is closed as the clear/frame metadata and smoke path milestone. M21 opens shader/pipeline metadata without changing the M20 support boundary.

M21B adds:

```text
DX12_SHADER
DX12_PIPELINE
DX12_PIPELINE_BIND
```

These lines are metadata-only and do not promote `dx12`, `shader`, `render_pass`, or `frame_update` capabilities.
