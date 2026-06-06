# M10I Backend Architecture

Status: PASSED

## Goal

Insert an explicit IR and backend boundary into the current M10 driver.

No new language syntax was added.

Current architecture:

```text
Source
-> Lexer
-> Tokens
-> Parser
-> AST
-> Semantic
-> IR
-> Backend
-> Artifact
```

## Driver

```text
Tools\arqc_m10g.exe
```

Normal build:

```powershell
.\Tools\arqc_m10g.exe .\Samples\hello_m10.arq
```

Backend-only build:

```powershell
.\Tools\arqc_m10g.exe --backend-only .\Build\IR\hello_m10.arqir -o .\Build\EXE\hello_m10_from_ir.exe
```

## Outputs

```text
Build\Tokens\hello_m10.tokens
Build\AST\hello_m10.ast
Build\IR\hello_m10.arqir
Build\EXE\hello_m10.exe
Build\EXE\hello_m10_from_ir.exe
Build\Manifests\hello_m10.manifest.txt
Build\Manifests\hello_m10_from_ir.manifest.txt
Build\Logs\hello_m10.build.log
```

## IR

Current IR format:

```text
ARQIR v0
```

Docs:

```text
IR\Formats\ARQIR_V0.md
Docs\IR_FORMAT_ARQIR_V0.md
```

ARQIR v0 contains source-level actions:

```text
show_message
exit
```

It does not contain Windows API names, PE headers, RVAs, IAT details, or file offsets.

## Backend

Current backend:

```text
WindowsX64PE_MessageBoxBackend
```

Docs:

```text
Docs\BACKEND_ARCHITECTURE.md
Docs\BACKEND_CONTRACT.md
Backends\WindowsX64PE\README.md
Backends\WindowsX64PE\PE_BACKEND_CONTRACT.md
```

## Verification

```text
Tools\run_all_tests.ps1
Total: 61/61 passed
```

M10I checks:

```text
M10I_SAMPLE_BUILD PASS
M10I_IR_VERSION PASS
M10I_IR_ACTION_SHOW PASS
M10I_IR_ACTION_EXIT PASS
M10I_IR_NO_WINDOWS_API PASS
M10I_IR_NO_PE_DETAILS PASS
M10I_MANIFEST PASS
M10I_BACKEND_ONLY PASS
M10I_BACKEND_OUT PASS
```

## Known Limitations

- Driver is still a bootstrap .NET tool.
- Backend still patches the M8 MessageBox PE template.
- Only `show_message` and `exit 0` are supported in ARQIR-to-PE backend.
- No if/else, blend mix implementation, functions, loops, UI/window/style, or new operators were added.
