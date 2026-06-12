# M28B DX12 Full Peripheral Input

M28B adds a small, explicit input bridge for the DX12 runtime scene path. It builds on M26 keyboard input, M27 perspective camera/depth, M27D native window style, and M28A box primitives.

## Public syntax

```arq
capture mouse for window "MainWindow"

when mouse moves rotate camera "MainCamera" by [0.12, 0.12]
when mouse wheel moves move camera "MainCamera" by [0.0, 0.0, 1.25]
when mouse button "Left" is held move camera "MainCamera" by [0.0, 0.0, 3.0]
when mouse button "Right" is pressed reset camera "MainCamera"
when mouse button "Middle" is pressed toggle animation

when key "Q" is held move camera "MainCamera" by [0.0, -3.0, 0.0]
when key "E" is held move camera "MainCamera" by [0.0, 3.0, 0.0]
```

## Runtime behavior

- `capture mouse for window` captures the Win32 mouse for the selected native window.
- `when mouse moves rotate camera` applies yaw/pitch to the selected perspective camera.
- Pitch is clamped to avoid camera flip.
- `when mouse wheel moves move camera` applies one movement step per wheel unit.
- `Left`, `Right`, and `Middle` mouse buttons are supported.
- When M28B peripheral input is enabled, `Q` no longer closes the generated demo window, because Q/E are now valid vertical camera controls. `Esc` still closes.

## IR markers

```text
DX12_MOUSE_CAPTURE|window=MainWindow
DX12_MOUSE_MOVE|target=MainCamera|sensitivity=[0.12,0.12]
DX12_MOUSE_BUTTON|button=Left|action=move_camera_held|target=MainCamera|delta=[0,0,3]
DX12_MOUSE_WHEEL|action=move_camera_wheel|target=MainCamera|delta=[0,0,1.25]
```

## Lowerer/config markers

```text
M28B_PERIPHERAL_INPUT|True
M28B_MOUSE_CAPTURE|True
M28B_MOUSE_MOVE_BINDINGS|1
M28B_MOUSE_BUTTON_BINDINGS|3
M28B_MOUSE_WHEEL_BINDINGS|1
```

and generated config macros:

```cpp
#define ARQEN_M28B_PERIPHERAL_INPUT_ENABLED 1
#define ARQEN_M28B_MOUSE_CAPTURE_ENABLED 1
#define ARQEN_M28B_MOUSE_MOVE_BINDING_COUNT 1
#define ARQEN_M28B_MOUSE_BUTTON_BINDING_COUNT 3
#define ARQEN_M28B_MOUSE_WHEEL_BINDING_COUNT 1
```

## Official sample

```text
Samples/DX12/dx12_full_peripheral_input_scene_m28b.arq
```

Build/run wrapper:

```powershell
.\Tools\build_m28b_dx12_full_peripheral_input_scene.ps1 -BuildNative -RunNative -KeepOpen
```

Validator:

```powershell
.\Tools\validate_m28b_dx12_full_peripheral_input.ps1
```

## Boundaries

M28B deliberately stops before the larger input/gameplay swamp:

- No key remapping.
- No controller/gamepad.
- No collision.
- No physics.
- No UI widgets.
- No editor viewport model.
- No mouse picking.
- No scroll-driven UI.

Key remapping remains a future contract because it should not be bolted onto the first mouse pass as a pile of special cases.
