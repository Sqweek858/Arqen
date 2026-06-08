# M19 Handoff Checklist

This checklist keeps the next stage split into safe slices instead of turning DX12/design into one heroic soup bowl.

## M19A Runtime Loop Contract

- Keep `frame_update`, `dx12`, `shader`, and `render_pass` unsupported until runtime/backend execution exists.
- Define one runtime loop ownership model before adding delta time.
- Window runtime must be the source of truth for create/show/run/close ordering.
- Events must be dispatched by runtime-owned loop state, not compile-time control flow.

## M19B Style / Design Foundation

- Add style/design blocks as data first, not rendering behavior.
- Canonical syntax is `with style for "Panel" ... end style`, including state-specific blocks like `with style for "PlayButton" when hovered`.
- Add parser/semantic tests before backend rendering.
- Do not use `[]` except for literal/constructor values such as vec4 color literals.

## M19C UI Objects Basic

- UI objects should emit explicit IR/runtime actions only after the design data model is validated.
- Start with named objects, bounds/position, text, color/style reference, and visibility.
- Invalid cases must cover missing style, duplicate object name, bad numeric bounds, and unsupported event attachment.

## M19D DX12 Skeleton / Clear Color Window

- First real rendering goal: one existing window cleared to a color.
- No shader language surface until device/swapchain/command list diagnostics are stable.
- No delta time until the runtime loop can provide measured frame values.
- Capability table stays the gate. No fake supported flags.
