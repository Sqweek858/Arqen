# Backend Contract

Every backend must define:

- backend name
- supported IR version
- supported actions
- unsupported/reserved actions
- target platform
- target artifact type
- required imports/runtime
- output path
- temp path behavior
- diagnostics behavior
- failure behavior
- artifact validation behavior

## Current backend

```text
Backend name: WindowsX64PE
Backend id: WindowsX64PE_MessageBoxBackend
Supported IR: ARQIR version 0
Target: windows-x64-pe
Artifact: .exe
```

## Supported current actions

```text
show_message
print_stdout
print_runtime_slot
file_write
file_append
file_load
command_arg_count
command_arg_index
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
exit
```

## Reserved / unsupported current actions

```text
print
branch
loop
function
ui_element
dx12
shader
render_pass
frame_update
```

These reserved actions must remain unsupported until the IR, runtime model, and backend implementation can validate and execute them.

## Required imports by artifact family

### Message box

```text
user32.dll!MessageBoxW
kernel32.dll!ExitProcess
```

### stdout/file/command args

```text
kernel32.dll!CreateFileW
kernel32.dll!WriteFile
kernel32.dll!ReadFile
kernel32.dll!CloseHandle
kernel32.dll!SetFilePointer
kernel32.dll!GetStdHandle
kernel32.dll!GetCommandLineW
kernel32.dll!ExitProcess
```

### window runtime

```text
kernel32.dll!ExitProcess
kernel32.dll!GetModuleHandleW
user32.dll!RegisterClassW
user32.dll!CreateWindowExW
user32.dll!ShowWindow
user32.dll!UpdateWindow
user32.dll!GetMessageW
user32.dll!TranslateMessage
user32.dll!DispatchMessageW
user32.dll!DefWindowProcW
user32.dll!PostQuitMessage
user32.dll!DestroyWindow
user32.dll!PostMessageW
```

## Failure behavior

- write backend diagnostics
- do not overwrite final exe unless temp output succeeds
- reject unsupported actions through backend capability validation
- do not report backend errors as parser errors

## Current diagnostic path

```text
Build\Diagnostics\Backend\<name>.backend.diagnostic.txt
```

## Current manifest path

```text
Build\Manifests\<name>.manifest.txt
Build\Manifests\<name>.build.txt
```

## M20B DX12 metadata boundary

The backend contract accepts that ARQIR may contain DX12 metadata lines:

```text
DX12_RENDERER
DX12_PARENT
```

These are not executable backend actions. WindowsX64PE must ignore them until a later DX12 backend slice consumes renderer metadata, parent window handoff, and style-derived background/clear color through a real runtime path.

## M20C DX12 clear style metadata boundary

The backend contract accepts that ARQIR may also contain DX12 renderer clear style metadata:

```text
DX12_CLEAR_STYLE
```

This line is still metadata, not an executable backend action. WindowsX64PE must parse/accept it through strict IR validation and ignore it until a later DX12 backend slice consumes renderer metadata, parent-window metadata, and style-derived clear color through a real runtime path.

## M20E0 DX12 clear-readiness metadata

`DX12_CLEAR_READY` is a derived metadata line. It is accepted by strict IR parsing but ignored by executable backends until a DX12 integration milestone consumes it.

```text
DX12_CLEAR_READY|renderer=<renderer>|window=<window>|kind=<kind>|value=<value>|unit=<unit>|source=<source>
```

It must not be treated as an `ACTION` and must not promote `dx12` capability support.

## M21B DX12 shader/pipeline metadata

The WindowsX64PE backend may accept `DX12_SHADER`, `DX12_PIPELINE`, and `DX12_PIPELINE_BIND` metadata through strict IR parsing, but must continue to ignore them until a real DX12 execution backend exists.
