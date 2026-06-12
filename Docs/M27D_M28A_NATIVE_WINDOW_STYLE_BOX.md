# M27D/M28A - Native Window Style + Box Primitive

M27D and M28A keep the post-M27 scope small and strict:

- **M27D** adds native window title-bar styling through the existing Arqen style system.
- **M28A** adds a generated 3D `box` primitive as a real object contract.

This milestone does **not** add a scene graph, custom title bar, DX12 UI, mouse input, lighting, materials, textures, mesh import, or a larger primitive zoo.

## M27D public syntax

M27D uses the existing direct style block syntax and targets a defined window:

```arq
define window called "MainWindow"

with style for "MainWindow"
    title bar color: color "#000000"
    title text color: color "#FFFFFF"
end style
```

Rules:

- the target must be a defined window;
- only the default state is supported;
- `title bar color` and `title text color` require explicit `color "#RRGGBB"` values;
- named colors are rejected for this native window bridge;
- this is native Win32/DWM chrome styling, not a DX12 renderer clear/background command.

## M28A public syntax

M28A adds one primitive:

```arq
define box called "CubeA"
draw "CubeA"
```

It reuses existing object bindings and transform syntax:

```arq
use renderer "MainRenderer" for object "CubeA"
use pipeline "BoxPipeline" for object "CubeA"
set position of object "CubeA" to [0.0, 0.0, 2.0]
set rotation z of object "CubeA" to 15 deg
set scale of object "CubeA" to [1.0, 1.0, 1.0]
```

Rules:

- a box is also a DX12 object;
- a box owns generated vertex data;
- manual `use vertex buffer ... for object "CubeA"` is rejected for box primitives;
- the generated box draw count is 36 vertices;
- the primitive still needs a renderer and pipeline, either through object bindings or renderer defaults;
- `draw "CubeA"` still obeys frame/clear/present ordering.

## Metadata contracts

M27D lowers style properties into runtime actions:

```text
ACTION|op=window_style_title_bar_color|target=MainWindow|kind=color|value=#000000
ACTION|op=window_style_title_text_color|target=MainWindow|kind=color|value=#FFFFFF
```

M28A adds:

```text
DX12_OBJECT|name=CubeA
DX12_OBJECT_PRIMITIVE|object=CubeA|kind=box
DX12_DRAW_OBJECT|object=CubeA|...
```

The lowerer emits manifest/config markers:

```text
M27D_NATIVE_WINDOW_STYLE|True
M27D_TITLE_BAR_COLOR|#000000
M27D_TITLE_TEXT_COLOR|#FFFFFF
M28_BOX_PRIMITIVE|True
M28_BOX_PRIMITIVE_COUNT|2
OBJECT_PRIMITIVE|object=CubeA|kind=box
```

```c
#define ARQEN_M27D_TITLE_BAR_ENABLED 1
#define ARQEN_M27D_TITLE_TEXT_ENABLED 1
#define ARQEN_M28_BOX_PRIMITIVE_ENABLED 1
#define ARQEN_M28_BOX_PRIMITIVE_COUNT 2
```

## Native runtime bridge

The generated Win32 smoke source applies the M27D title bar style via DWM:

- `DWMWA_USE_IMMERSIVE_DARK_MODE`
- `DWMWA_CAPTION_COLOR`
- `DWMWA_TEXT_COLOR`

This remains optional and data-driven. If no M27D title style metadata exists, the generated window chrome path does not force dark mode.

M28A generated boxes are lowered into normal generated position/color vertices, then rendered by the existing M23/M24/M27 draw path. Depth and perspective remain M27 runtime features.

## Official sample

```text
Samples\DX12\dx12_window_style_box_scene_m28a.arq
```

## Validation

```powershell
.\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail
.\Tools\validate_m27d_m28a_dx12_window_style_box.ps1
.\Tools\build_m28a_dx12_window_style_box_scene.ps1 -BuildNative -RunNative -KeepOpen
```

## Explicitly out of scope

- No custom title bar.
- No DX12 UI system.
- No scene graph.
- No lighting.
- No material/texture system.
- No mesh import.
- No mouse look.
- No M28B/C implementation in this milestone.
