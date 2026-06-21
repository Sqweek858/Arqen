# Runtime Contract (M18B)

This contract documents the boundary between compile-time Arqen commands and runtime behavior.

## Current runtime actions

The compiler can emit runtime actions for:

```text
show_message
print_stdout
exit
file_write
file_append
file_load
print_runtime_slot
command_arg_count
command_arg_index
runtime_int_set
runtime_int_add
runtime_int_sub
runtime_bool_set
runtime_bool_not_set
runtime_bool_toggle
runtime_string_set
runtime_string_concat
runtime_string_substring
runtime_int_parse
runtime_if_int
runtime_if_bool
runtime_if_string
runtime_else
runtime_if_end
runtime_while_int
runtime_break
runtime_continue
runtime_while_end
function_call
function_call_assign
function_return
function_return_int
function_return_bool
function_return_string
window_create
window_set_title
window_set_resolution
window_set_resizable
window_style_title_bar_color
window_style_title_text_color
window_show
window_run
window_close
event_window_closed
event_key_pressed
event_end
```

These are represented in the current ARQIR action stream. Runtime state/control actions are intentionally listed here as backend-visible actions, not just parser conveniences, so capability validation can catch stale routing gates before clean builds drift into weirdness. M40 adds `function_return` as a function-only control action lowered to the function epilogue. M41 adds typed return storage actions and `function_call_assign`, which calls a no-param function and copies its typed return slot into a runtime int/bool/string slot. M42 adds typed function parameters without a new backend action: callers copy arguments into internal parameter runtime slots using existing `runtime_*_set` actions before `function_call` / `function_call_assign`.

## Reserved runtime concepts for DX12

The following concepts are intentionally reserved for the DX12/runtime stage and are not active language features yet:

```text
frame_update
delta time
elapsed time
frame count
render pass
shader
swapchain resize
```

## Timing rule

`delta time`, `elapsed time`, and `frame count` require a real frame pump. They must not be implemented as compile-time math helpers.

## Event rule

Current event blocks are intentionally limited. DX12 work should first introduce a runtime event model before adding rendering commands inside event blocks.

## M19A runtime loop boundary

M19A may introduce a runtime loop contract, but it must not pretend that frame rendering exists before the backend can actually execute it. The loop boundary is:

```text
compile source
validate emitted ARQIR actions against backend capabilities
initialize runtime resources
create/configure/show windows
enter the real message pump when run window is reached
dispatch supported runtime events
exit through an explicit exit action or window-close action
```

### No hidden frame simulation rule

`frame_update`, `delta time`, `elapsed time`, and `frame count` are runtime-provided values only after a real frame pump exists. They must not be faked with compile-time loops, scalar math, or silent backend defaults.

### Event execution rule

Current event blocks stay intentionally narrow until the runtime loop owns event dispatch. Adding design/UI/DX12 commands inside event blocks requires a visible ARQIR action, a capability entry, and a backend/runtime implementation.

### Window handoff rule

DX12 work must reuse or explicitly hand off the window handle created by the window runtime. Creating a second hidden window to fake render support is not allowed.


## M19B style/design boundary

`with style for` blocks, style presets, and style applications are frontend/IR metadata. They define visual intent for UI objects, including default and state-specific style values, but they are not runtime actions yet.

The style contract may describe states, text style, box style, shadows, transitions, cursors, blend mode, z-order, interaction flags, visual transforms, and reusable presets as data only. It must not schedule timers, animate values, test mouse state, or allocate renderer resources during M19B.

M19B must not add frame timing, hit testing, text rendering, or DX12 drawing. Later UI/runtime milestones may consume `STYLE`, `STYLE_PRESET`, and `STYLE_APPLY` metadata after UI object and renderer contracts exist.


## M19C UI object boundary

`define shape/text/button/slider/input field/checkbox/dropdown called` statements and basic UI property setters are frontend/IR metadata. They describe named UI objects and initial properties, but they are not runtime actions yet.

M19C may emit `UI_OBJECT` and `UI_SET` metadata for content, slider range/value, input placeholders/value, checkbox checked state, and dropdown options. It must not perform layout, hit testing, event dispatch, font rendering, or DX12 drawing. Later milestones can consume this metadata after hierarchy/layout/events and renderer contracts are explicit.

## M19D UI hierarchy/layout boundary

`parent`, `dock`, and `with layout for` statements are frontend/IR metadata only in M19D. They may emit `UI_PARENT`, `UI_DOCK`, and `UI_LAYOUT` metadata, but they are not runtime actions.

M19D may validate parent/child relationships, dock relationships, simple cycles, layout property names, px units, anchors, flex/grid modes, and grid tracks. It must not perform layout computation, hit testing, event dispatch, animation playback, font rendering, or DX12 drawing. Later milestones can consume this metadata after renderer/runtime ownership is explicit.

## M19E/F/G/H UI final boundary

UI events, bindings, state changes, and UI resource declarations are metadata only in the M19E/F/G/H combined UI final foundation.

Supported metadata statements may emit `UI_EVENT`, `UI_BIND`, `UI_STATE`, `UI_RESOURCE`, and `UI_RESOURCE_USE`, but they must not create runtime actions, load files, dispatch mouse/keyboard input, perform hit testing, evaluate bindings every frame, play audio, rasterize fonts, solve layout, or render through DX12. The renderer/runtime layer may consume this metadata only after the DX12/runtime bridge contract is explicit.


## M20A DX12 native bridge boundary

M20A may add a native DX12 clear-color bridge, but it does not change runtime action semantics yet. The bridge must accept a real caller-owned `HWND` and must not create hidden compiler-owned windows to fake renderer support.

The M20A native smoke host may create its own temporary validation window only outside the compiler pipeline. That smoke window is a backend validation tool, not Arqen runtime support.

The compiler runtime remains responsible for this ordering when DX12 is wired later:

```text
create/configure/show window
obtain/hand off HWND
initialize DX12 device/swapchain for that HWND
record command list
clear render target
present
fence/wait
run/exit through explicit runtime rules
```

`frame_update`, `delta time`, `elapsed time`, shader execution, render pass execution, hit testing, and UI drawing remain reserved until a later runtime slice adds visible ARQIR actions and backend support.


## M20B DX12 renderer metadata boundary

M20B DX12 renderer syntax is metadata-only. The runtime contract recognizes that a future DX12 runtime can consume:

```text
DX12_RENDERER
DX12_PARENT
STYLE background color for the renderer target
```

M20B does not add runtime actions for renderer creation, frame begin/end, clear, present, shader compilation, or render passes. Any generated WindowsX64PE artifact that contains M20B DX12 metadata must still execute only its existing supported runtime actions.
## M20C DX12 style metadata boundary

M20C introduces `DX12_CLEAR_STYLE` as metadata only. Runtime actions are not added.

The runtime must not create a renderer, clear a swapchain, or present a frame only because this metadata exists. A later DX12 runtime slice must explicitly consume renderer metadata, parent-window metadata, and style-derived clear metadata together before any capability is promoted.

## M20E0 DX12 clear-readiness boundary

`DX12_CLEAR_READY` is compiler/backend metadata only. It does not create a runtime action, does not run the native DX12 bridge, and does not require the window runtime to call D3D12 yet.

The runtime boundary remains unchanged until a later milestone explicitly wires clear-ready renderer metadata to a real DX12 execution path.


## M20E1 DX12 clear lowering runtime boundary

M20E1 remains outside the normal runtime action table. The lowering tool may read `window_create`, `window_set_title`, `window_set_resolution`, `window_style_title_bar_color`, and `window_style_title_text_color` actions from ARQIR to produce a generated native DX12 clear config/window-style bridge.

The optional native smoke builder creates a generated test executable from that config and the M20A `ArqenDx12ClearWindowOnce` bridge. This is Windows-only manual validation and must not be required by standard regression tests.
## M20F/M20G DX12 smoke and frame boundaries

M20F adds a tool wrapper that compiles an Arqen sample and lowers `DX12_CLEAR_READY` into generated bridge config. This wrapper is outside the normal runtime action table.

M20G frame syntax emits `DX12_FRAME` metadata for begin/clear/end/present ordering, but it does not register runtime actions, does not dispatch a frame loop, and does not call the DX12 bridge from generated WindowsX64PE artifacts.

A later runtime milestone must explicitly consume `DX12_FRAME` together with `DX12_CLEAR_READY` before any capability is promoted.

## M20H/M20I DX12 smoke boundary

M20H and M20I remain outside normal runtime execution. They provide an explicit offline lowering/smoke path from ARQIR metadata to generated native DX12 bridge config.

The normal generated PE backend must not treat `DX12_FRAME` as an executable runtime action yet. Native build/run is optional and manual.

## M21B DX12 shader/pipeline metadata boundary

M21B shader and pipeline commands emit metadata only:

```text
DX12_SHADER
DX12_PIPELINE
DX12_PIPELINE_BIND
```

They are not runtime actions. The runtime registry must not list them as executable operations until a later milestone defines native shader compilation, pipeline state creation, binding, and draw behavior.

## M21D DX12 triangle smoke

M21D native triangle execution is an optional smoke helper, not a public runtime action. The normal runtime registry is not promoted to general DX12 draw support. Native run remains manual through `Tools/build_m21d_dx12_triangle_smoke.ps1 -BuildNative -Run`.

## M21G/M21H DX12 smoke runtime note

The native DX12 triangle smoke bridge may consume generated tint constant buffer and color animation arrays from M21G/M21H config headers. This path remains optional/manual and outside the general WindowsX64PE runtime support contract.

## M28B DX12 peripheral input runtime contract

The DX12 runtime may consume the following generated input data for native scene windows:

- keyboard movement bindings from M26;
- mouse capture from `DX12_MOUSE_CAPTURE`;
- mouse look from `DX12_MOUSE_MOVE`;
- mouse buttons from `DX12_MOUSE_BUTTON`;
- mouse wheel deltas from `DX12_MOUSE_WHEEL`.

M28B is limited to camera movement/rotation, camera reset, and animation toggle. It does not define key remapping, controller input, collision, physics, UI widgets, mouse picking, or editor viewport behavior.

## M29C DX12 object selector runtime contract

M29C runtime data enables one renderer-bound object selector for approximate center picking of drawn DX12 objects. The selected object transform is mutable at runtime, and `R` + mouse X rotates the selected object around Y at its transform center. This does not add screen gizmo UI, outline rendering, multi-select, undo, or mesh triangle picking.

## M30A DX12 UI overlay controls

The DX12 native runtime accepts generated UI overlay draw calls and `ArqenDx12UiControl` data from the M30A lowerer. Controls can toggle animation and fake-light state. The runtime does not implement general UI layout solving, font files, input text, sliders, dropdown popups, textures, drag/drop, or editor docking in M30A.

## M30B/M30C DX12 UI layout bridge

The DX12 runtime bridge consumes generated UI overlay vertices from the lowerer. M30B/M30C improves the lowerer/runtime contract without new syntax:

- UI text is clipped to its layout rectangle.
- Button text is centered and clipped.
- Checkbox labels reserve room for the knob.
- Style `size`, `padding`, and `z index` affect generated overlay geometry.
- Parent-relative positioning and parent clipping are resolved before native runtime handoff.
- Clickable UI controls remain represented by `ArqenDx12UiControl`; generic UI event body execution is not part of this runtime slice.

## M30D/M31A/M31B DX12 UI controls

The DX12 runtime supports hover/pressed/focus/disabled feedback for UI controls and slider value updates. Input fields and dropdowns are rendered/focusable skeletons; editable text and popup dropdown menus are future work.


### M31C UI computed layout / control rect QOL
- `M31C_UI_COMPUTED_LAYOUT_RECTS`: runtime/lowerer bridge computes parent content rects, centered child labels, and unified visual/hit regions without new public syntax.
- `M31C_UI_PARENT_CONTAINMENT`: `parent "Child" to "Parent"` now means local content-space containment for UI: children resolve inside the parent content rect, text children of controls honor their own padding, and child geometry/text is clipped to the parent content box by default unless overflow is explicitly made visible.
- `M31C_UI_TEXT_PADDING_DEFAULTS`: standalone `text` objects now default to `padding: 0 px` while controls keep the old 8px default. This keeps small labels from collapsing into clipped dash fragments; authored text padding still works, and `font size` is accepted as a `size` alias by the DX12 lowerer.
- `M31C_UI_STYLE_BOX_MODEL`: DX12 UI style resolution now has one box-model path for defaults, disabled-state overlays, padding, border inset, and parent content rects. Parent-child layout and control text now consume the same content-space math instead of duplicating padding/border logic.
- `M31C_UI_SLIDER_TRACK_RECT`: slider value updates use the same track rect that is drawn on screen, so the visual track and drag math stay aligned across window sizes.
- `M31C_UI_SLIDER_RUNTIME_VISUALS`: slider fill and knob draw calls get dedicated runtime roles, so dragging updates the visible fill/knob geometry instead of only changing the stored value.
- `M31C_UI_STABLE_CLIENT_PIXEL_SPACE`: generated DX12 smoke windows are DPI-aware, non-resizable, and created with an exact authored client rect; runtime UI mouse input is normalized back into authored client pixels so hover/click/slider behavior does not drift between windowed/fullscreen or DPI-scaled modes.
- A `text` object parented to a `button`, `checkbox`, `input field`, `dropdown`, or `slider` acts as control content by default and is centered/clipped inside the parent content rect unless explicit layout overrides are supplied.

## M45/M46 runtime int array contract

Runtime int arrays are fixed-size global runtime collections lowered to internal runtime int element slots.

Public syntax:

```arq
define runtime int array called "values" size 3
set runtime int array "values" at 0 to 42
set runtime int array "values" at runtime int "i" to 42
set runtime int "out" to runtime int array "values" at 0
set runtime int "out" to runtime int array "values" at runtime int "i"
```

Static indexes are validated at compile time. Dynamic runtime-int indexes lower to branch dispatch over valid indexes. If no branch matches, the generated `runtime_trap_if_bool_false` action exits through the backend fail path.

New backend action:

```txt
runtime_trap_if_bool_false
```

This action checks a runtime bool slot for textual `true`; if it is not true, execution traps to backend failure exit code `1`.

## M47/M48 runtime bool/string array contract

M47 extends global runtime arrays to bool and string element types. M48 adds a fixed-size array length helper.

Supported forms:

```arq
define runtime bool array called "flags" size 2
set runtime bool array "flags" at 0 to true
set runtime bool array "flags" at runtime int "i" to false
set runtime bool "out" to runtime bool array "flags" at 0
set runtime bool "out" to runtime bool array "flags" at runtime int "i"

define runtime string array called "parts" size 2
set runtime string array "parts" at 0 to string "Cry"
set runtime string array "parts" at runtime int "i" to string "blo"
set runtime string "out" to runtime string array "parts" at 1
set runtime string "out" to runtime string array "parts" at runtime int "i"

set runtime int "len" to length of runtime string array "parts"
```

Static indexing lowers to direct `runtime_bool_set` / `runtime_string_set` actions targeting internal element slots. Dynamic indexing reuses the M46 bounds-checked dispatch and `runtime_trap_if_bool_false`. The length helper lowers to static `runtime_int_set` using the declared fixed array size.

## M49/M50 runtime array scope and parameter contract

M49 adds function-local runtime arrays. A local runtime array is only valid while parsing its function body and lowers to internal element slots with a function-scoped storage base.

M50 adds fixed-size runtime array parameters. Array parameters are not pointer ABI objects. They lower to copy-in/copy-back action sequences:

```txt
caller array element slots -> function parameter array element slots
function_call / function_call_assign
function parameter array element slots -> caller array element slots
```

The backend actions remain existing runtime slot actions:

```txt
runtime_int_set
runtime_bool_set
runtime_string_set
runtime_if_int
runtime_if_end
runtime_trap_if_bool_false
function_call
function_call_assign
```

Array parameter element type and fixed size must match exactly at compile time. Dynamic indexing continues to use the M46 generated bounds dispatch and `runtime_trap_if_bool_false`.

## M51/M52 array utilities and runtime records

M51 fill/copy runtime arrays and M52 runtime records add no backend action. They lower to existing runtime slot actions:

```txt
runtime_int_set
runtime_bool_set
runtime_string_set
```

M52 record field storage is slot-backed through internal names such as `__rec_player_hp`. Packed record memory, nested records, record arrays, record params, and record return values are reserved for later milestones.
