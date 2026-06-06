# M2 MessageBoxW Experiment Log

## Goal

Show a Windows message box from a manually constructed PE32+ executable, then exit with code `0`.

Target behavior:

```text
MessageBoxW(NULL, L"Hello from Arqen", L"Arqen Byte Zero", 0)
ExitProcess(0)
```

## Output

Planned executable:

```text
C:\Users\Sqweek\Documents\Arqen\Arqen\Experiments\M2_MessageBoxW\arqen_m2_messagebox.exe
```

## Status

```text
PASSED
```

## First Runtime Attempt

PowerShell result:

```text
LASTEXITCODE: -1073741819
```

Meaning:

```text
0xC0000005 = access violation
```

Cause found:

- The RIP-relative displacement for the `MessageBoxW` call was wrong.
- The call targeted RVA `0x3090`, which is the `ExitProcess` hint/name entry.
- It should target the `MessageBoxW` IAT slot at RVA `0x3070`.

Incorrect bytes:

```text
FF 15 73 20 00 00
```

Correct bytes:

```text
FF 15 53 20 00 00
```

Patch location:

```text
file offset 0x0219: 73 -> 53
```

## Byte Checklist

```text
Docs\M2_BYTE_CHECKLIST.md
```

## Passing Executable

```text
C:\Users\Sqweek\Documents\Arqen\Arqen\Experiments\M2_MessageBoxW\arqen_m2_messagebox_v2_fixed_messagebox_call.exe
```

Runtime command:

```powershell
.\arqen_m2_messagebox_v2_fixed_messagebox_call.exe
echo $LASTEXITCODE
```

Observed:

```text
0
```

Conclusion:

```text
M2 MessageBoxW PE: PASSED
```

Meaning:

- Windows accepted the manually constructed PE32+ executable.
- The executable imported:
  - `kernel32.dll!ExitProcess`
  - `user32.dll!MessageBoxW`
- The entry code called `MessageBoxW`.
- After the dialog was closed, the process called `ExitProcess(0)`.
- The process exited with code `0`.
