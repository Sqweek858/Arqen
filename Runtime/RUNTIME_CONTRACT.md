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
