# ARQIR V0 Contract

ARQIR V0 is the current text IR boundary between the Arqen front-end and backend artifact generation.

## Required header

```text
ARQIR|version=0
TARGET|kind=program|name=<program>
META|source=<relative source path>
```


## Style metadata

M19B can emit style metadata lines before constants/actions:

```text
STYLE|target=<ui-object>|state=<default-or-state>|property=<style-property>|kind=<value-kind>|value=<escaped-value>|unit=<optional-unit>
STYLE_PRESET|name=<style-preset>|property=<style-property>|kind=<value-kind>|value=<escaped-value>|unit=<optional-unit>
STYLE_APPLY|style=<style-preset>|target=<ui-object>|state=<default-or-state>
```

`STYLE`, `STYLE_PRESET`, and `STYLE_APPLY` lines are metadata, not executable backend actions. The WindowsX64PE backend must parse and preserve the strict IR boundary by accepting well-formed style metadata while ignoring it for current executable generation. Rendering these styles belongs to later UI/DX12 milestones.

M19B value kinds include `enum`, `bool`, `number`, `dimension`, `duration`, `angle`, `integer`, `string`, `font_weight`, `named_color`, `color`, and `vec4`. Units are intentionally explicit (`px`, `ms`, `sec`, `deg`, `rad`) so later UI/DX12 work does not inherit implicit layout guesses.


## UI object metadata

M19C can emit UI object metadata lines before constants/actions:

```text
UI_OBJECT|type=<shape/text/button/slider/input field/checkbox/dropdown>|name=<ui-object>
UI_SET|target=<ui-object>|property=<content/range/value/placeholder/checked/option>|kind=<value-kind>|value=<escaped-value>
```

`UI_OBJECT` and `UI_SET` lines are metadata, not executable backend actions. They define the UI object graph inputs that later layout, events, and renderer milestones may consume. The WindowsX64PE backend accepts well-formed UI metadata while ignoring it for current executable generation.

M19C value kinds include `text`, `number`, `range`, and `bool`. Dropdown entries are represented as `UI_SET` with `property=option`.

## UI hierarchy/layout metadata

M19D can emit UI hierarchy and layout metadata lines before constants/actions:

```text
UI_PARENT|child=<ui-object>|parent=<ui-object-or-window>
UI_DOCK|target=<ui-object>|side=<top/right/bottom/left/fill/center>|parent=<ui-object-or-window>
UI_LAYOUT|target=<ui-object>|property=<layout-property>|kind=<value-kind>|value=<escaped-value>|unit=<optional-unit>
```

`UI_PARENT`, `UI_DOCK`, and `UI_LAYOUT` lines are metadata, not executable backend actions. They describe UI graph relationships and layout intent for later layout/hit-test/render milestones. The WindowsX64PE backend accepts well-formed metadata while ignoring it for current executable generation.

### UI final metadata (M19E/F/G/H)

```text
UI_EVENT|event=<clicked/hovered/pressed/released/focused/unfocused/changed/value changed/text changed/dragged/dropped/loaded/resized>|target=<ui-object-or-window>|target_kind=<ui/window>|body_lines=<count>
UI_BIND|target=<ui-object>|property=<content/width/height/visibility/visible/enabled/checked/selected/value/color/background color/foreground color/border color/opacity>|source=<symbol>|source_type=<symbol-type>
UI_STATE|target=<ui-object>|property=<enabled/visible/selected/focused/hovered/pressed/loading/visibility/state>|kind=<bool/state>|value=<value>
UI_RESOURCE|type=<texture/font/sound>|name=<resource>|path=<file-path>
UI_RESOURCE_USE|target=<ui-object>|property=<texture/font/sound>|resource=<resource>|resource_type=<texture/font/sound>
```

`UI_EVENT`, `UI_BIND`, `UI_STATE`, `UI_RESOURCE`, and `UI_RESOURCE_USE` are metadata-only lines. They complete the UI language-side contract for events, data binding, state, and resource references. They do not perform input dispatch, file loading, font loading, audio playback, hit testing, layout solving, or rendering.

M19D layout value kinds include `dimension`, `enum`, and `track`. Dimension units are currently explicit `px`; grid tracks may use positive integers or `auto`.

## Constants

```text
CONST|id=<id>|type=<type>|value=<escaped value>
```

Current backend-supported constant types are:

```text
text
int
```

Compile-time-only math types may appear in AST output, but should not be required by the current WindowsX64PE backend until a backend explicitly supports them.

## Actions

```text
ACTION|id=<id>|op=<operation>|<fields>
```

Every action `op` must be present in the backend capability table. Unsupported operations must be rejected before backend artifact writing.

## Entry

```text
ENTRY|actions=<comma-separated action ids>
END
```

## DX12 rule

DX12 actions are reserved but unsupported in M18B. `dx12`, `shader`, `render_pass`, and `frame_update` must be rejected by backend capability validation until the DX12 backend exists.

## Pipeline boundary

ARQIR v0 sits between the lexer/parser/semantic pipeline and the backend, so every backend action must stay visible as a capability-checked IR action.

## Strict validation rules

M18I makes ARQIR v0 strict enough for pre-DX12 work:

- `ARQIR`, `TARGET`, `ENTRY`, and `END` are required.
- `ARQIR`, `TARGET`, and `ENTRY` may appear only once.
- Unknown top-level line kinds are invalid; currently recognized top-level metadata includes `META`, `SYMBOL`, `STYLE`, `STYLE_PRESET`, `STYLE_APPLY`, `UI_OBJECT`, `UI_SET`, `UI_PARENT`, `UI_DOCK`, `UI_LAYOUT`, `UI_EVENT`, `UI_BIND`, `UI_STATE`, `UI_RESOURCE`, and `UI_RESOURCE_USE`.
- Duplicate `CONST` ids are invalid.
- Duplicate `ACTION` ids are invalid.
- Every `ACTION` must include both `id` and `op`.
- `ENTRY|actions=...` must reference existing action ids.
- Every entry action must pass the C# backend capability gate, not only wrapper-side PowerShell checks.

These rules intentionally keep DX12, shader, render pass, and frame update operations rejected until a real runtime/backend implementation exists.


## M20A DX12 note

M20A does not add new ARQIR action kinds. The native DX12 clear bridge is source-level backend/runtime infrastructure only.

Reserved DX12-related operations remain rejected by backend capability validation:

```text
dx12
shader
render_pass
frame_update
```

A later M20 slice may add visible ARQIR actions only after parser syntax, AST nodes, semantic validation, backend execution, capability gates, and proportional command tests are all present.


## M20B DX12 renderer metadata

ARQIR v0 accepts DX12 renderer metadata lines beginning in M20B:

```text
DX12_RENDERER|name=MainRenderer
DX12_PARENT|renderer=MainRenderer|window=MainWindow
```

These are metadata records, not executable actions. They may appear before constants/actions and are ignored by the WindowsX64PE backend until a DX12 backend slice consumes them.

Required fields:

```text
DX12_RENDERER: name
DX12_PARENT: renderer, window
```

Capability status remains unsupported for executable DX12 action families.
## M20C DX12 style-derived clear metadata

M20C adds one DX12 renderer style metadata line:

```text
DX12_CLEAR_STYLE|renderer=MainRenderer|state=default|kind=color|value=#101820|unit=|source=style.background_color
```

`DX12_CLEAR_STYLE` is metadata, not an executable `ACTION`. It may appear before constants/actions and is accepted by strict IR parsing so a later DX12 backend slice can consume style-derived clear/background color without adding a duplicate public `set clear color` command.

Required fields:

```text
DX12_CLEAR_STYLE: renderer, state, kind, value, source
```

Capability status remains unsupported for executable DX12 action families.

## M20E0 DX12 clear-readiness metadata

`DX12_CLEAR_READY` is a derived metadata line produced only when the compiler sees a renderer definition, parent window relationship, and style-derived clear/background color for the same renderer.

Format:

```text
DX12_CLEAR_READY|renderer=<name>|window=<window>|kind=<kind>|value=<value>|unit=<unit>|source=<source>
```

It is not an executable action. The WindowsX64PE backend accepts it through strict IR validation but must ignore it until a later DX12 integration milestone consumes it.


## M20E1 DX12 clear lowering note

M20E1 does not add a new ARQIR action kind. It consumes existing metadata lines offline:

```text
DX12_RENDERER
DX12_PARENT
DX12_CLEAR_STYLE
DX12_CLEAR_READY
```

`Tools/lower_m20e1_dx12_clear_from_ir.ps1` also reads normal window runtime actions such as `window_create`, `window_set_title`, and `window_set_resolution` to generate a native clear bridge config. This is an explicit tooling path, not normal WindowsX64PE backend execution.
## M20G DX12 frame metadata

M20G adds a metadata-only frame record:

```text
DX12_FRAME|command=<begin|clear|end|present>|renderer=<name>
```

`DX12_FRAME` is not an executable `ACTION`. It records public frame syntax after semantic validation, while WindowsX64PE continues to ignore DX12 metadata during normal executable generation.

Required fields:

```text
DX12_FRAME: command, renderer
```

Capability status remains unsupported for executable DX12 action families.

## M20H frame-aware DX12 lowering metadata

M20H does not add new ARQIR line types. It constrains existing `DX12_FRAME` metadata when the explicit lowerer is run with `-RequireFrame`.

The selected renderer must contain the ordered sequence:

```text
DX12_FRAME|command=begin|renderer=MainRenderer
DX12_FRAME|command=clear|renderer=MainRenderer
DX12_FRAME|command=end|renderer=MainRenderer
DX12_FRAME|command=present|renderer=MainRenderer
```

The lowerer may generate manifest/config metadata such as `FRAME_MODE`, `FRAME_SEQUENCE`, and smoke hold settings. These are generated artifacts, not ARQIR runtime actions.

## M21B DX12 shader/pipeline metadata

ARQIR v0 accepts the following metadata-only lines:

```text
DX12_SHADER|name=<shader>|vertex=<path>|pixel=<path>
DX12_PIPELINE|name=<pipeline>|renderer=<renderer>|shader=<shader>|topology=triangle_list
DX12_PIPELINE_BIND|pipeline=<pipeline>|renderer=<renderer>
```

These lines are not ACTION records and do not imply backend support.

## M21C/M21D DX12 vertex/draw metadata

Accepted metadata records:

```text
DX12_VERTEX_BUFFER|name=<buffer>
DX12_VERTEX|buffer=<buffer>|index=<n>|position=[x,y,z]|color=[r,g,b,a]
DX12_VERTEX_BUFFER_BIND|buffer=<buffer>|renderer=<renderer>
DX12_DRAW|renderer=<renderer>|vertices=<n>|buffer=<buffer>|pipeline=<pipeline>
```

M21D lowerer can consume these with `DX12_SHADER`, `DX12_PIPELINE`, `DX12_PIPELINE_BIND`, `DX12_CLEAR_READY`, and `DX12_FRAME` to produce a native triangle smoke config.

## M21G/M21H DX12 tint animation metadata

M21G introduces metadata-only constant buffer lines:

```text
DX12_CONSTANT_BUFFER|name=TriangleParams|field=tint|type=color4|value=#38FFC0
DX12_CONSTANT_BUFFER_BIND|buffer=TriangleParams|pipeline=TrianglePipeline
```

M21H introduces metadata-only color sequence and animation lines:

```text
DX12_COLOR_SEQUENCE|name=TriangleColors
DX12_COLOR_KEY|sequence=TriangleColors|index=0|value=#FF4040
DX12_ANIMATE_COLOR|target=TriangleParams.tint|buffer=TriangleParams|field=tint|sequence=TriangleColors|every_frames=12
```

These records are consumed only by explicit DX12 smoke tooling. They do not promote general DX12 support.

## M27 DX12 camera projection metadata

`DX12_CAMERA_PROJECTION|camera=<name>|projection=<orthographic|perspective>` records the selected projection mode for a defined DX12 camera. Strict IR requires both `camera` and `projection`. If omitted, lowering keeps M25 orthographic compatibility.


## M27D/M28A DX12 metadata

M27D native window title-bar style is represented as ordinary runtime actions:

```text
ACTION|op=window_style_title_bar_color|target=MainWindow|kind=color|value=#000000
ACTION|op=window_style_title_text_color|target=MainWindow|kind=color|value=#FFFFFF
```

M28A generated primitive boxes use:

```text
DX12_OBJECT|name=CubeA
DX12_OBJECT_PRIMITIVE|object=CubeA|kind=box
```

Strict IR requires `object` and `kind` fields for `DX12_OBJECT_PRIMITIVE`. M28A only accepts `kind=box` in the lowerer/runtime contract.

## M28B DX12 peripheral input metadata

```text
DX12_MOUSE_CAPTURE|window=MainWindow
DX12_MOUSE_MOVE|target=MainCamera|sensitivity=[0.12,0.12]
DX12_MOUSE_BUTTON|button=Left|action=move_camera_held|target=MainCamera|delta=[0,0,3]
DX12_MOUSE_WHEEL|action=move_camera_wheel|target=MainCamera|delta=[0,0,1.25]
```
