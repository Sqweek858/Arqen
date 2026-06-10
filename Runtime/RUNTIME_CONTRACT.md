# Runtime Contract (M18B)

This contract documents the boundary between compile-time Arqen commands and runtime behavior.

## Current runtime actions

The compiler can emit runtime actions for:

```text
file_write
file_append
file_load
print_runtime_slot
command_arg_count
command_arg_index
window_create
window_set_title
window_set_resolution
window_set_resizable
window_show
window_run
window_close
event_window_closed
event_key_pressed
event_end
```

These are represented in the current ARQIR action stream.

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
