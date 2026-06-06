# M1 ExitProcess Experiment Log

## Output

Executable:

```text
C:\Users\Sqweek\Documents\Arqen\Arqen\Experiments\M1_ExitProcess\arqen_m1_exitprocess.exe
```

File size:

```text
1536 bytes = 0x600
```

## Static Checks Performed

PowerShell byte checks confirmed:

| Field | Observed |
|---|---|
| File size | `1536` |
| DOS signature | `4D 5A` |
| `e_lfanew` | `128` / `0x80` |
| PE signature | `50 45 00 00` |
| Machine | `0x8664` |
| Entry RVA | `0x1000` |
| Import RVA | `0x2000` |
| IAT RVA | `0x2050` |
| Entry bytes | `48 83 EC 28 31 C9 FF 15 44 10 00 00` |
| DLL name | `kernel32.dll` |

## First Run Result

The file started but exited with:

```text
LASTEXITCODE: -1073741819
```

Meaning:

```text
0xC0000005 = access violation
```

Interpretation:

- Windows accepted the file far enough to attempt execution.
- Milestone 1 is not complete yet.
- Most likely failure area: import resolution / IAT call target / entry call path.

## Later Run Result

After the first run and one test patch attempt, Windows blocked further runs with:

```text
An Application Control policy has blocked this file
```

Authenticode status:

```text
NotSigned
```

Interpretation:

- Further runtime testing from PowerShell is currently blocked by Windows policy.
- Static inspection in PE-bear should be the next step.

## Import Size Patch

The first file used Import Directory Size:

```text
0x28
```

That may be too narrow for runtime loading even though it describes the descriptor array itself.

The current preferred value is:

```text
0x80
```

Reason:

- It covers the descriptor, ILT, IAT, hint/name entry, and DLL name.
- PE-bear recognizes `kernel32.dll!ExitProcess` with this layout.

Status:

- Runtime confirmation is still blocked by Windows Application Control on this machine.

## Next Debug Step

PE-bear screenshot showed:

- `.text` entry is decoded correctly.
- The call is labelled as `[kernel32.dll].ExitProcess`.

Next, use x64dbg and check:

1. Does the IAT slot at `ImageBase + 0x2050` contain a real resolved function pointer?
2. Or does it still contain `0x2060`?
3. If it contains `0x2060`, the access violation is caused by calling into unresolved `.idata`.
4. If it contains a real pointer, inspect stack/register state before the call.

Detailed steps:

- `Docs/M1_X64DBG_CHECK.md`

## Text Section Characteristics Bug

The first executable had a malformed `.text` section header.

Expected at file offset `0x01AC`:

```text
20 00 00 60
```

Meaning:

```text
0x60000020 = code | execute | read
```

Observed in the loaded/original file:

```text
00 00 60 00
```

Meaning:

```text
0x00600000
```

This explains the x64dbg result:

```text
C0000005 EXCEPTION_ACCESS_VIOLATION at 0000000140001000
```

The section was not mapped with proper execute permission.

Root cause:

- The generated `.text` section header had `NumberOfLinenumbers` and `Characteristics` shifted by one byte.

Corrected test file:

```text
C:\Users\Sqweek\Documents\Arqen\Arqen\Experiments\M1_ExitProcess\arqen_m1_exitprocess_v3_fixed_text_flags.exe
```

Verified in bytes:

| Field | Value |
|---|---|
| `.text NumberOfRelocations` | `0x0000` |
| `.text NumberOfLinenumbers` | `0x0000` |
| `.text Characteristics` | `0x60000020` / `20 00 00 60` |
| `.idata Characteristics` | `0xC0000040` / `40 00 00 C0` |

Note:

- The original `arqen_m1_exitprocess.exe` could not be overwritten while it was open in x64dbg.
- Use the `v3_fixed_text_flags` executable for the next test, or close x64dbg and patch/regenerate the main file.

## Milestone 1 Pass

Tested executable:

```text
C:\Users\Sqweek\Documents\Arqen\Arqen\Experiments\M1_ExitProcess\arqen_m1_exitprocess_v3_fixed_text_flags.exe
```

PowerShell result:

```powershell
.\arqen_m1_exitprocess_v3_fixed_text_flags.exe
echo $LASTEXITCODE
```

Observed:

```text
0
```

x64dbg result:

- entry point reached at `0x140001000`
- entry bytes decoded correctly
- no access violation after fixed `.text` flags
- process terminated cleanly

Conclusion:

```text
M1 ExitProcess-only PE: PASSED
```

Meaning:

- Windows accepted the manually constructed PE32+ executable.
- The executable imported `kernel32.dll!ExitProcess`.
- The entry code called `ExitProcess(0)`.
- The process exited with code `0`.
