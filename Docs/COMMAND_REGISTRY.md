# Command Registry

Status: M10H command system infrastructure

This registry documents the current Arqen constructs. It is the human-readable companion to `Specs\Commands\*.command.txt`.

M10H does not add new syntax.

## program / end program

Canonical syntax:

```text
program "Hello"
...
end program "Hello"
```

Token pattern:

```text
KEYWORD(program) STRING
...
KEYWORD(end) KEYWORD(program) STRING
```

Parser rule:

```text
Program := program Name Statements end program Name
```

AST:

```text
PROGRAM|Hello
```

Semantic:

- program name is required
- end program name must match

Codegen:

- no direct codegen yet

Tests:

- `Tests\CommandTests\program`

Limitations:

- no modules or nested programs

## let / be

Canonical syntax:

```text
let name be "Sqweek"
let number be 0
let active be true
```

Token pattern:

```text
KEYWORD(let) IDENT KEYWORD(be) LITERAL
```

Parser rule:

```text
Let := let Identifier be Literal
```

AST:

```text
LET|name|text|Sqweek
LET|number|int|0
LET|active|bool|true
```

Semantic:

- declares a compile-time variable
- rejects duplicate names
- let values are literals only

Codegen:

- no direct codegen
- values can be folded into message expressions

Tests:

- `Tests\CommandTests\let`

Limitations:

- no reassignment
- no scopes
- no expression values in let

## title

Canonical syntax:

```text
title "Arqen Byte Zero"
```

Token pattern:

```text
KEYWORD(title) STRING
```

Parser rule:

```text
Title := title StringLiteral
```

AST:

```text
TITLE|Arqen Byte Zero
```

Semantic:

- title must be text
- title must fit current PE template buffer

Codegen:

- written as UTF-16LE into the MessageBox title buffer

Tests:

- covered by message/program smoke tests

Limitations:

- title expressions are not supported

## message text

Canonical syntax:

```text
message text "Hello, " + name
```

Token pattern:

```text
KEYWORD(message) KEYWORD(text) Expression
```

Parser rule:

```text
MessageText := message text TextExpression
```

AST:

```text
MESSAGE|Hello, Sqweek
MESSAGE_EXPR|plus(str("Hello, "),var(name))
```

Semantic:

- expression must resolve to text
- unknown variables are rejected
- text + text is allowed
- text + bool/int is rejected

Codegen:

- folded text is written as UTF-16LE into the MessageBox message buffer

Tests:

- `Tests\CommandTests\message_text`

Limitations:

- only compile-time folding
- no runtime string allocation

## exit

Canonical syntax:

```text
exit 0
```

Token pattern:

```text
KEYWORD(exit) INT
```

Parser rule:

```text
Exit := exit IntLiteral
```

AST:

```text
EXIT|0
```

Semantic:

- only `0` is currently supported

Codegen:

- generated PE calls `ExitProcess(0)`

Tests:

- covered by smoke tests

Limitations:

- no non-zero exit code support yet

## Literals

Canonical syntax:

```text
"text"
0
true
false
```

Token pattern:

```text
STRING
INT
BOOL
```

AST:

```text
text/int/bool values inside LET or expression nodes
```

Semantic:

- type inferred from literal kind

Codegen:

- only text values used in MessageBox output today

Limitations:

- no escape sequences in source strings yet

## Plus Expression

Canonical syntax:

```text
"Hello, " + name
```

Token pattern:

```text
Expression PLUS Expression
```

AST:

```text
MESSAGE_EXPR|plus(str("Hello, "),var(name))
```

Semantic:

- only text + text is supported

Codegen:

- folded at compile time

Tests:

- `Tests\CommandTests\message_text`

Limitations:

- no int math
- no bool logic
- no runtime expression evaluation

## style

Canonical direct syntax:

```text
with style for "Panel"
    type: rectangle
    color: black
    opacity: 0.8
    visibility: visible
    clip children: false
end style
```

State-specific style blocks:

```text
with style for "PlayButton" when hovered
    background color: light blue
end style
```

Reusable style presets:

```text
define style called "PrimaryButton"
    background color: blue
    foreground color: white
    corner radius: 8 px
end style

use style "PrimaryButton" for "PlayButton"
use style "PrimaryButton" for "PlayButton" when selected
```

Supported M19B properties:

```text
type
display
color
background color
foreground color
accent color
border color
border size
outline color
outline size
corner radius
padding
margin
opacity
visibility
clip children
font
size
font weight
font style
text align
vertical align
line height
letter spacing
wrap
shadow color
shadow opacity
shadow blur
shadow spread
shadow offset x
shadow offset y
cursor
transition duration
transition easing
blend mode
z index
min width
min height
max width
max height
preferred width
preferred height
aspect ratio
overflow
pointer events
interactable
scale
scale x
scale y
rotation
translate x
translate y
pivot
transition property
transition delay
animation duration
animation easing
```

Supported M19B state suffixes are `hovered`, `pressed`, `disabled`, `focused`, `unfocused`, `active`, `selected`, `checked`, `loading`, `visited`, `dragged`, `dropped`, `error`, `warning`, and `success`.

Style blocks emit `STYLE|...`, `STYLE_PRESET|...`, and `STYLE_APPLY|...` metadata in AST/IR. They are not executable runtime/render actions yet; later UI/DX12 milestones consume the metadata after UI object and renderer contracts exist.

Tests:

- `Tests\CommandTests\style`

## ui_objects

Canonical syntax:

```text
define shape called "Panel"
define text called "Title"
define button called "PlayButton"
define slider called "VolumeSlider"
define input field called "NameInput"
define checkbox called "FullscreenCheck"
define dropdown called "QualityDropdown"

set content of "Title" to string "Hello world"
set range of "VolumeSlider" to 0, 100
set value of "VolumeSlider" to 50
set placeholder of "NameInput" to string "Enter name"
set checked of "FullscreenCheck" to false
add string "High" to "QualityDropdown"
```

Parser rule:

```text
UiObject := define UiObjectType called Name
UiSet := set UiProperty of Name to UiValue
UiDropdownOption := add string StringLiteral to Name
```

AST/IR metadata:

```text
UI_OBJECT|type=button|name=PlayButton
UI_SET|target=PlayButton|property=content|kind=text|value=Play
```

Semantic:

- rejects duplicate UI object names and collisions with existing symbols/windows
- validates target existence for UI setters
- validates property support per UI object type
- validates slider range/value as numeric
- validates checkbox checked state as boolean
- validates duplicate property assignment and duplicate dropdown options

Backend:

- metadata only in M19C
- accepted by strict IR parser
- ignored by WindowsX64PE executable generation until UI/DX12 consumes it

Tests:

- `Tests\CommandTests\ui_objects`


## ui_layout

Canonical forms:

```arq
parent "Title" to "Panel"

with layout for "Panel"
    x: 100 px
    y: 50 px
    width: 300 px
    height: 80 px
end layout

dock "Toolbar" to top of "Window"
```

AST/IR metadata:

```text
UI_PARENT|child=Title|parent=Panel
UI_DOCK|target=Toolbar|side=top|parent=Window
UI_LAYOUT|target=Panel|property=width|kind=dimension|value=300|unit=px
```

Backend: metadata only in M19D; strict IR accepts it but WindowsX64PE ignores it until UI layout/render milestones consume it.

Tests: `Tests\CommandTests\ui_layout`.

- `ui_final` - M19E/F/G/H UI final foundation: UI event metadata, binding/link metadata, state metadata, and UI resource metadata.


## dx12 renderer metadata

Canonical syntax:

```text
define dx12 renderer called "MainRenderer"
parent renderer "MainRenderer" to window "MainWindow"
```

Renderer background/clear color should be provided through existing style metadata:

```text
with style for "MainRenderer"
    background color: color "#101820"
end style
```

Parser rule:

```text
Dx12Renderer := define dx12 renderer called String
Dx12Parent := parent renderer String to window String
```

AST:

```text
DX12_RENDERER|name=MainRenderer
DX12_PARENT|renderer=MainRenderer|window=MainWindow
```

IR:

```text
DX12_RENDERER|name=MainRenderer
DX12_PARENT|renderer=MainRenderer|window=MainWindow
```

Semantic:

- renderer name must be non-empty and unique
- renderer name must not conflict with existing window/UI object names
- parent relationship requires a known renderer and known window
- renderer may only have one parent window in M20B

Codegen:

- metadata only in M20B
- WindowsX64PE strict IR accepts the metadata but does not execute DX12 work yet

Tests:

- `Tests\CommandTests\dx12`

Limitations:

- no runtime renderer creation from generated PE yet
- no frame begin/end, clear, present, shader, render pass, pipeline, or draw syntax is supported yet
- DX12 capabilities remain unsupported until backend/runtime execution exists
## DX12 renderer style bridge metadata (M20C)

Public syntax remains the existing style syntax:

```text
with style for "MainRenderer"
    background color: color "#101820"
end style
```

M20C adds semantic validation for DX12 renderer style targets and emits:

```text
DX12_CLEAR_STYLE|renderer=MainRenderer|state=default|kind=color|value=#101820|unit=|source=style.background_color
```

Semantic:

- renderer styles support only default state in M20C
- renderer styles support only `background color` in M20C
- renderer clear/background style cannot be declared twice

Tests:

- `Tests\CommandTests\dx12`

Limitations:

- metadata only
- no public `set clear color` DX12 command
- no runtime/backend clear from generated PE yet

## M20D/M20E0 DX12 semantic/readiness notes

- `define dx12 renderer called "Name"` now participates in object-name collision checks against variables, windows, and UI objects.
- `parent renderer "Renderer" to window "Window"` remains metadata-only and requires a defined runtime window.
- style-derived `background color` for a renderer can produce `DX12_CLEAR_STYLE`.
- when renderer, parent, and clear style metadata are complete, the compiler derives `DX12_CLEAR_READY` metadata.
- no DX12 runtime command is supported yet.


## M20E1 DX12 lowering registry note

M20E1 adds no public command syntax. It registers an explicit tooling path that consumes existing DX12 metadata:

```text
DX12_CLEAR_READY -> Tools/lower_m20e1_dx12_clear_from_ir.ps1 -> Build/M20E1/dx12_clear_config.generated.h
```

The public syntax remains the M20B/M20C renderer + style form. Capability status remains unsupported.
## M20F/M20G DX12 smoke and frame metadata

M20F adds no public syntax. It adds `Tools/build_m20f_dx12_clear_smoke.ps1`, a safe wrapper that compiles the official DX12 clear smoke sample, verifies `DX12_CLEAR_READY`, and runs the M20E1 lowerer into `Build/M20F`.

M20G adds frame metadata syntax:

```arqen
begin frame of "MainRenderer"
clear renderer "MainRenderer"
end frame of "MainRenderer"
present frame of "MainRenderer"
```

The compiler emits:

```text
DX12_FRAME|command=begin|renderer=MainRenderer
DX12_FRAME|command=clear|renderer=MainRenderer
DX12_FRAME|command=end|renderer=MainRenderer
DX12_FRAME|command=present|renderer=MainRenderer
```

These are metadata records, not executable runtime actions. Capability status remains unsupported.

## M20H/M20I DX12 lowering/smoke notes

M20H/M20I add no public command syntax. They consume the existing M20G `DX12_FRAME` metadata in explicit tooling:

```text
Tools\lower_m20e1_dx12_clear_from_ir.ps1 -RequireFrame
Tools\build_m20i_dx12_frame_clear_smoke.ps1
```

Frame-aware lowering is considered a tool milestone, not a supported backend capability promotion.

## M21A/M21B DX12 shader/pipeline metadata

```text
define shader called "TriangleShader"
    vertex source file "Shaders/triangle_vs.hlsl"
    pixel source file "Shaders/triangle_ps.hlsl"
end shader

define dx12 pipeline called "TrianglePipeline"
    renderer: "MainRenderer"
    shader: "TriangleShader"
    topology: triangle list
end pipeline

use pipeline "TrianglePipeline" for renderer "MainRenderer"
```

M21B emits `DX12_SHADER`, `DX12_PIPELINE`, and `DX12_PIPELINE_BIND` metadata. No HLSL compilation, PSO creation, root signature, vertex buffer, or draw call is implemented in M21B.

## M21C/M21D DX12 vertex/draw metadata and triangle smoke

M21C adds metadata-only vertex buffers, vertex-buffer binding, and one-shot draw commands:

```arqen
define vertex buffer called "TriangleVertices"
    vertex position [-0.5, -0.5, 0.0] color [1.0, 0.0, 0.0, 1.0]
    vertex position [0.0, 0.5, 0.0] color [0.0, 1.0, 0.0, 1.0]
    vertex position [0.5, -0.5, 0.0] color [0.0, 0.0, 1.0, 1.0]
end vertex buffer

use vertex buffer "TriangleVertices" for renderer "MainRenderer"
draw 3 vertices with renderer "MainRenderer"
```

M21C emits `DX12_VERTEX_BUFFER`, `DX12_VERTEX`, `DX12_VERTEX_BUFFER_BIND`, and `DX12_DRAW`. M21D extends the lowering/native smoke path with `-RequireTriangle` and optional `DrawInstanced` execution. Capabilities remain unsupported until a general backend/runtime renderer exists.

## M21G/M21H DX12 constant tint and color animation metadata

M21G adds metadata-only constant buffer syntax for the existing triangle pipeline:

```arqen
define constant buffer called "TriangleParams"
    color tint: color "#38FFC0"
end constant buffer

use constant buffer "TriangleParams" for pipeline "TrianglePipeline"
```

M21H adds color sequence animation metadata:

```arqen
define color sequence called "TriangleColors"
    color "#FF4040"
    color "#38FFC0"
end color sequence

animate color "TriangleParams.tint"
    using sequence "TriangleColors"
    every 12 frames
end animate
```

The smoke-path lowerer emits `DX12_CONSTANT_BUFFER`, `DX12_CONSTANT_BUFFER_BIND`, `DX12_COLOR_SEQUENCE`, `DX12_COLOR_KEY`, and `DX12_ANIMATE_COLOR` metadata. Native execution remains limited to the M21D/M21F triangle smoke path.

### M21I/M21J DX12 color animation polish and hardening

M21I adds tooling/runtime-marker polish for the existing M21H animated triangle smoke path. M21J hardens `DX12_ANIMATE_COLOR` metadata by requiring selected tint-only animation, a positive frame interval, a known color sequence with at least two contiguous keys, and a constant-buffer target bound to exactly one pipeline before animation.

## M27 DX12 perspective camera commands

- `set camera "Name" projection to perspective|orthographic`
- `set rotation of camera "Name" to [pitch,yaw,roll]`
- `set field of view of camera "Name" to N deg`
- `set near plane of camera "Name" to N`
- `set far plane of camera "Name" to N`


## M27D/M28A DX12 additions

```text
with style for "MainWindow"
    title bar color: color "#000000"
    title text color: color "#FFFFFF"
end style
```

- M27D adds native window chrome style properties for defined windows only.
- Metadata lowers through runtime actions `window_style_title_bar_color` and `window_style_title_text_color`.

```text
define box called "CubeA"
draw "CubeA"
```

- M28A adds one generated primitive object command: `define box called`.
- Metadata: `DX12_OBJECT_PRIMITIVE|object=CubeA|kind=box`.
- Box primitives own generated 36-vertex data and reject manual vertex-buffer binding.

## M28B DX12 full peripheral input commands

```arq
capture mouse for window "MainWindow"
when mouse moves rotate camera "MainCamera" by [0.12, 0.12]
when mouse wheel moves move camera "MainCamera" by [0.0, 0.0, 1.25]
when mouse button "Left" is held move camera "MainCamera" by [0.0, 0.0, 3.0]
when mouse button "Right" is pressed reset camera "MainCamera"
when mouse button "Middle" is pressed toggle animation
```

M28B does not add key remapping. Q/E are normal M26 key bindings and may be used for vertical movement.
