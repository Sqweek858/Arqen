# M29C DX12 Object Selector + Selected Object Rotate

M29C adds the first minimal object-manipulation contract on top of M29B viewport navigation.

## Public syntax

```arq
define object selector called "PrimarySelector"
use object selector "PrimarySelector" for renderer "MainRenderer"
when mouse button "Left" is pressed select object using "PrimarySelector"
when key "R" is held rotate selected object around y by mouse x sensitivity 0.35
```

## Runtime behavior

- LMB selects a drawn object using its projected screen-space bounds, not only its center.
- Click in empty space deselects the current object.
- Selected objects receive a small cyan/bright feedback tint; this is not a full outline or screen gizmo.
- Input is ignored while the demo window is not the foreground window, so RMB/WASD/mouse actions do not leak through other focused windows.
- Hold `R` and move mouse X to rotate the selected object around Y.
- `R held` is the documented short form for the selected-object rotate mode; it maps to the explicit Arqen binding above.
- Pivot is the object transform center, currently the object's position.
- RMB viewport navigation remains from M29B and has priority over selection/rotation.

## Intentional non-scope

- No screen gizmo.
- No outline handles or screen-space highlight UI; only a tiny selected-object tint is allowed.
- No axis handles.
- No multi-select.
- No undo/redo.
- No move/scale tools.
- No mesh import.
- No perfect triangle raycast.
- No UI overlay.

This is a minimal editor-manipulation foundation, not a full editor gizmo. Humanity may survive waiting one more milestone for colored arrows.
