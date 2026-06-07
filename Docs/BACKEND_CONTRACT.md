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
