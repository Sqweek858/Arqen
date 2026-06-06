# Milestone 1 x64dbg Check

Goal:

- Confirm whether the Windows loader resolves the IAT before the entry call.
- Confirm where the access violation happens.

Executable:

```text
C:\Users\Sqweek\Documents\Arqen\Arqen\Experiments\M1_ExitProcess\arqen_m1_exitprocess.exe
```

## Expected Entry Bytes

At entry point:

```text
ImageBase + 0x1000
```

Expected bytes:

```text
48 83 EC 28 31 C9 FF 15 44 10 00 00
```

Expected disassembly:

```text
sub rsp, 28
xor ecx, ecx
call qword ptr [rip + 1044]
```

The call reads the function pointer from:

```text
ImageBase + 0x2050
```

## Main Question

Before executing the call, inspect memory at:

```text
ImageBase + 0x2050
```

Expected if imports resolved:

```text
some real kernel32/kernelbase function address
```

Bad if unresolved:

```text
60 20 00 00 00 00 00 00
```

If the IAT slot still contains `0x2060`, the call jumps into `.idata` instead of `ExitProcess`, causing an access violation.

## Debug Steps

1. Open the executable in x64dbg.
2. Let it load to entry point.
3. Note the image base.
4. Go to memory address:

```text
ImageBase + 0x2050
```

5. Check the 8-byte value there.
6. Step over:

```text
sub rsp, 28
xor ecx, ecx
```

7. Before the call, confirm:

```text
RCX = 0
```

8. Step into or step over the call.

## Interpretation

If IAT is resolved and it still crashes:

- likely stack/calling convention issue
- next patch: test a slightly different entry prologue

If IAT is unresolved:

- import table is readable to PE-bear but not accepted/resolved by the Windows loader
- next patch: adjust import directory, section characteristics, or descriptor/thunk layout

