# M19 Handoff Checklist

This checklist keeps the next stage split into safe slices instead of turning DX12/design into one heroic soup bowl.

## M19A Runtime Loop Contract

- Keep `frame_update`, `dx12`, `shader`, and `render_pass` unsupported until runtime/backend execution exists.
- Define one runtime loop ownership model before adding delta time.
- Window runtime must be the source of truth for create/show/run/close ordering.
- Events must be dispatched by runtime-owned loop state, not compile-time control flow.

## M19B Style / Design Foundation

- Add style/design blocks as data first, not rendering behavior.
- Canonical direct syntax is `with style for "Panel" ... end style`, including state-specific blocks like `with style for "PlayButton" when hovered`.
- Reusable syntax is `define style called "PrimaryButton" ... end style` plus `use style "PrimaryButton" for "PlayButton"`.
- Add parser/semantic tests before backend rendering.
- M19B currently covers core box/text style plus extended metadata for outline, shadow, cursor, transitions, blend mode, z index, sizing hints, interaction flags, visual transforms, status states, and reusable presets.
- Do not use `[]` except for literal/constructor values such as vec4 color literals.

## M19C UI Objects Basic

- UI objects emit metadata first: `UI_OBJECT` and `UI_SET`, not runtime draw actions.
- Start with named `shape`, `text`, `button`, `slider`, `input field`, `checkbox`, and `dropdown` objects.
- Basic setters cover content, slider range/value, input placeholder/value, checkbox checked state, and dropdown options.
- Style presets can already be applied to UI object names through the M19B `use style` contract.
- Invalid cases must cover duplicate object names, symbol/window collisions, unknown targets, unsupported properties for object types, bad numeric ranges, bad booleans, duplicate options, and duplicate property assignment.
- Layout, hierarchy, hit testing, UI events, font rendering, and DX12 drawing stay out of M19C.

## M19D UI Hierarchy / Layout Foundation

- `parent "Child" to "Parent"` links UI objects to UI object/window parents as metadata.
- `with layout for "Panel" ... end layout` describes absolute, anchored, flex, and grid layout intent as metadata.
- `dock "Toolbar" to top of "Window"` describes docking intent without computing rectangles yet.
- M19D emits `UI_PARENT`, `UI_DOCK`, and `UI_LAYOUT`; it must not run layout, hit testing, animation, UI event dispatch, font rendering, or DX12 drawing.
- Invalid cases must cover unknown targets, self-parenting, duplicate parent/dock relationships, simple cycles, unknown layout properties, bad units, bad enum values, empty blocks, and duplicate layout properties.

## M20A DX12 Skeleton / Clear Color Window

- First real rendering goal: one existing window cleared to a color.
- No shader language surface until device/swapchain/command list diagnostics are stable.
- No delta time until the runtime loop can provide measured frame values.
- Capability table stays the gate. No fake supported flags.

## M19E/F/G/H UI Final Foundation

Combined UI final language-side milestone: `when clicked/hovered/value changed/text changed`, `link ... to ...`, `set enabled/visible/state ...`, and `define texture/font/sound ... from file ...` are metadata-only. This closes the UI contract before the first renderer bridge.
