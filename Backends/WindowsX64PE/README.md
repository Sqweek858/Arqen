# WindowsX64PE Backend

Backend name:

```text
WindowsX64PE_MessageBoxBackend
```

Target:

```text
Windows x64 PE .exe
```

Supported ARQIR v0 actions:

```text
show_message
exit
```

Mapping:

```text
show_message -> user32.dll!MessageBoxW
exit         -> kernel32.dll!ExitProcess
```

Current implementation uses the M8 MessageBox PE template.

PE-specific knowledge belongs here, not in language docs.
