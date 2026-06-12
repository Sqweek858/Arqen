# Arqen M20 DX12 Mini Bible

Status: M20B draft, partially implemented as metadata syntax.

This document defines the public DX12 syntax direction before the backend is promoted. The goal is to make the language shape explicit first, then implement small vertical slices without fake support.

## Non-negotiable rule

A DX12 feature is not supported just because the parser accepts a sentence.

A feature becomes supported only after it has:

```text
syntax
AST
IR
semantic validation
backend/runtime implementation
capability gate update
docs
tests proportional to the command surface
```

Until that happens, these families remain unsupported:

```text
dx12
shader
render_pass
frame_update
```

## Naming style

DX12 syntax must follow Arqen language style:

```arqen
define dx12 renderer called "MainRenderer"
parent renderer "MainRenderer" to window "MainWindow"
```

The `parent renderer ... to window ...` form is preferred over `attach renderer ... to window ...` because it matches the existing UI/layout direction.

## M20B implemented metadata syntax

### Define a renderer

```arqen
define dx12 renderer called "MainRenderer"
```

Meaning: declares a named DX12 renderer metadata object.

Rules:

- renderer name must be a non-empty string
- renderer name must be unique
- renderer name must not collide with an existing window or UI object name
- metadata only in M20B

AST:

```text
DX12_RENDERER|name=MainRenderer
```

IR:

```text
DX12_RENDERER|name=MainRenderer
```

### Parent renderer to window

```arqen
parent renderer "MainRenderer" to window "MainWindow"
```

Meaning: records that a renderer belongs to a runtime window.

Rules:

- renderer must exist
- window must exist
- renderer may only have one parent window in M20B
- metadata only in M20B

AST:

```text
DX12_PARENT|renderer=MainRenderer|window=MainWindow
```

IR:

```text
DX12_PARENT|renderer=MainRenderer|window=MainWindow
```

## Clear color / background color

M20B does not add this command as public syntax:

```arqen
set clear color of "MainRenderer" to color "#101820"
```

Reason: Arqen already has style metadata. Renderer clear/background color should be style-derived, not a duplicate property system.

Preferred syntax:

```arqen
with style for "MainRenderer"
    background color: color "#101820"
end style
```

A later backend slice may consume renderer style metadata and map `background color` to the DX12 clear color.

## Minimal M20B program

```arqen
program "Dx12RendererMetadataDemo"
set title to string "DX12 metadata"

define window called "MainWindow"
define dx12 renderer called "MainRenderer"
parent renderer "MainRenderer" to window "MainWindow"

with style for "MainRenderer"
    background color: color "#101820"
end style

show message "dx12 metadata"
blend mix to code 0
end program "Dx12RendererMetadataDemo"
```

## Reserved future syntax

These are not implemented in M20B.

```arqen
set vsync of "MainRenderer" to true
set buffer count of "MainRenderer" to 3
set debug layer of "MainRenderer" to true
resize renderer "MainRenderer" to window "MainWindow"
wait renderer "MainRenderer" idle

begin frame of "MainRenderer"
clear renderer "MainRenderer"
end frame of "MainRenderer"
present frame of "MainRenderer"

set viewport of "MainRenderer" to 0 0 1280 720
set scissor of "MainRenderer" to 0 0 1280 720
enable depth buffer for "MainRenderer"
clear depth of "MainRenderer"

define shader called "BasicVertexShader" from file "Shaders/basic.hlsl"
compile shader "BasicVertexShader" as vertex entry "VSMain" profile "vs_6_0"
define pipeline called "BasicPipeline"
bind pipeline "BasicPipeline" to renderer "MainRenderer"
define vertex buffer called "TriangleVertices"
bind vertex buffer "TriangleVertices" to renderer "MainRenderer"
draw 3 vertices with renderer "MainRenderer"
```

Every future command needs at least one positive and one negative command test, plus semantic/IR/backend tests where relevant.
## M20C style-derived clear metadata

M20C keeps renderer clear color in the existing style system. It does not add `set clear color ...` as a public DX12 command.

Direct renderer style:

```arqen
with style for "MainRenderer"
    background color: color "#101820"
end style
```

Preset renderer style:

```arqen
define style called "RendererClear"
    background color: color "#101820"
end style

use style "RendererClear" for "MainRenderer"
```

Both forms lower to metadata only:

```text
DX12_CLEAR_STYLE|renderer=MainRenderer|state=default|kind=color|value=#101820|unit=|source=style.background_color
```

Semantic boundary:

- renderer style state must be `default`
- renderer styles may only contain `background color` in M20C
- only one default clear/background style source is allowed per renderer
- `DX12_CLEAR_STYLE` is not an executable action
- DX12 capability remains unsupported until the backend consumes this metadata and performs real runtime work

## M20D semantic hardening

M20D does not add new syntax. It tightens the renderer symbol rules so that a DX12 renderer is treated as a real named metadata object, not just a string in an IR line.

Additional rules:

- a DX12 renderer name may not collide with an existing variable, window, or UI object
- a variable may not later reuse a DX12 renderer name
- a window may not later reuse a DX12 renderer name
- `parent renderer "R" to window "W"` requires `R` to be a DX12 renderer and `W` to be a window
- a UI object name in the `window` slot is rejected because it is not a runtime window

No capability is promoted in M20D.

## M20E0 clear-readiness metadata

M20E0 derives readiness metadata from existing M20B/M20C metadata. It adds no public command.

A renderer is clear-ready when it has:

```text
DX12_RENDERER
DX12_PARENT
DX12_CLEAR_STYLE
```

The compiler may then emit:

```text
DX12_CLEAR_READY|renderer=MainRenderer|window=MainWindow|kind=color|value=#101820|unit=|source=style.background_color
```

This line is a backend integration gate. It means a later slice can connect the metadata to the native DX12 clear bridge without guessing which window, renderer, or clear color should be used.

It is still metadata-only:

- no frame loop exists yet
- no `clear renderer` command exists yet
- no `present renderer` command exists yet
- no `dx12` capability is supported yet


## M20E1 experimental clear lowering

M20E1 does not add new syntax. It uses the existing M20B/M20C/M20E0 program shape:

```arqen
define window called "MainWindow"
set title of "MainWindow" to string "Arqen M20E1 DX12 Clear"
set resolution of "MainWindow" to 1280 x 720
show window "MainWindow"

define dx12 renderer called "MainRenderer"
parent renderer "MainRenderer" to window "MainWindow"

with style for "MainRenderer"
    background color: color "#101820"
end style
```

The lowering tool is explicit:

```powershell
.\Tools\lower_m20e1_dx12_clear_from_ir.ps1 -IrPath .\Build\IR\dx12_clear_m20e1.arqir
```

It produces:

```text
Build\M20E1\dx12_clear_manifest.generated.txt
Build\M20E1\dx12_clear_config.generated.h
```

The optional native bridge smoke builder is:

```powershell
.\Backends\DX12\Runtimeuild_m20e1_dx12_clear_from_ir.ps1 -IrPath .\Build\IR\dx12_clear_m20e1.arqir
```

M20E1 is still experimental lowering, not public runtime support. `dx12`, `shader`, `render_pass`, and `frame_update` remain unsupported.
## M20F clear smoke path

M20F does not add syntax. It adds an official smoke wrapper for the M20E1 lowering flow:

```powershell
.\Tools\build_m20f_dx12_clear_smoke.ps1
```

The wrapper compiles `Samples/DX12/dx12_clear_smoke_m20f.arq`, verifies `DX12_CLEAR_READY`, runs the lowerer, and checks the generated manifest/header markers.

Native DX12 build/run is optional:

```powershell
.\Tools\build_m20f_dx12_clear_smoke.ps1 -BuildNative -Run
```

## M20G frame metadata syntax

Reserved public syntax for the first explicit frame metadata slice:

```arqen
begin frame of "MainRenderer"
clear renderer "MainRenderer"
end frame of "MainRenderer"
present frame of "MainRenderer"
```

These commands produce metadata:

```text
DX12_FRAME|command=begin|renderer=MainRenderer
DX12_FRAME|command=clear|renderer=MainRenderer
DX12_FRAME|command=end|renderer=MainRenderer
DX12_FRAME|command=present|renderer=MainRenderer
```

The frame commands require an existing renderer, an existing parent window, and style-derived clear/background color before `clear renderer`. This is still metadata-only and does not promote DX12 runtime support.

## M20H frame-aware lowering

M20H consumes the M20G frame metadata in the explicit lowering tool. It adds no new syntax.

Valid frame lowering sequence:

```arqen
begin frame of "MainRenderer"
clear renderer "MainRenderer"
end frame of "MainRenderer"
present frame of "MainRenderer"
```

The lowerer is invoked with `-RequireFrame` for frame-aware smoke paths:

```powershell
.\Tools\lower_m20e1_dx12_clear_from_ir.ps1 -IrPath .\Build\IR\dx12_frame_clear_smoke_m20h.arqir -RequireFrame
```

The generated manifest records:

```text
FRAME_MODE|oneshot_clear_frame
FRAME_SEQUENCE|begin,clear,end,present
```

Invalid frame lowering cases include missing commands, wrong command order, unknown frame renderer, duplicate frame sequence, or selecting a renderer that has no frame sequence.

## M20I native smoke polish

M20I provides `Tools\build_m20i_dx12_frame_clear_smoke.ps1` as the safe frame-aware smoke wrapper.

Default mode:

```powershell
.\Tools\build_m20i_dx12_frame_clear_smoke.ps1
```

Default mode compiles and lowers only. It does not build or run native DX12.

Optional native modes:

```powershell
.\Tools\build_m20i_dx12_frame_clear_smoke.ps1 -BuildNative
.\Tools\build_m20i_dx12_frame_clear_smoke.ps1 -BuildNative -Run
```

M20I still does not promote DX12 capability support.
