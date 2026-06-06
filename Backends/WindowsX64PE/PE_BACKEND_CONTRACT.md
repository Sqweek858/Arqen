# PE Backend Contract

Current backend:

```text
WindowsX64PE_MessageBoxBackend
```

Template requirements:

- valid PE32+ executable
- AMD64 machine
- imports `user32.dll!MessageBoxW`
- imports `kernel32.dll!ExitProcess`
- message buffer at raw offset `0x400`
- title buffer at raw offset `0x440`
- buffers are UTF-16LE
- current buffer size is 64 bytes each

PE-specific concepts:

- PE headers
- sections
- imports
- IAT
- file alignment
- section alignment
- UTF-16LE emission
- template patching

Known limitations:

- MessageBox-only output
- exit code only 0
- fixed template buffers
- no general PE writer yet
