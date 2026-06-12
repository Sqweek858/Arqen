# M27D/M28A Handoff

## Scope shipped

M27D:

- Arqen style metadata can target native windows with `title bar color` and `title text color`.
- Lowering emits M27D manifest/config markers.
- Generated native Win32 smoke code applies dark/title colors through DWM.

M28A:

- `define box called "CubeA"` creates a generated 3D box primitive object.
- AST/IR/strict IR emit `DX12_OBJECT_PRIMITIVE`.
- The lowerer generates a 36-vertex box and feeds the existing multi-draw/runtime path.
- Manual vertex-buffer binding is rejected for primitives.

## Official sample

```text
Samples\DX12\dx12_window_style_box_scene_m28a.arq
```

## Wrapper

```powershell
.\Tools\build_m28a_dx12_window_style_box_scene.ps1 `
  -BuildNative `
  -RunNative `
  -KeepOpen
```

## Validator

```powershell
.\Tools\validate_m27d_m28a_dx12_window_style_box.ps1
Get-Content .\Build\Generated\m27d_m28a_dx12_window_style_box_validation.txt
```

## Required regression

Because parser C# changed, run:

```powershell
.\Tools\run_test_slice.ps1 -BuildDriver -Folder dx12 -StopOnFail
```

## Command tests

Positive:

- `Tests\CommandTests\dx12\valid_dx12_window_style_titlebar_metadata.arq`
- `Tests\CommandTests\dx12\valid_dx12_box_primitive_metadata.arq`

Negative:

- `Tests\CommandTests\dx12\invalid_dx12_window_style_unknown_target.arq`
- `Tests\CommandTests\dx12\invalid_dx12_window_style_named_color.arq`
- `Tests\CommandTests\dx12\invalid_dx12_box_duplicate_object.arq`
- `Tests\CommandTests\dx12\invalid_dx12_box_unknown_draw.arq`
- `Tests\CommandTests\dx12\invalid_dx12_box_manual_vertex_buffer.arq`

## Boundaries

Do not treat M28A as a full mesh system. It is one generated primitive contract, deliberately tiny. No scene graph, no mesh import, no lighting, no materials, no custom title bar, and no mouse input were added.
