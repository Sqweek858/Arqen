# Backend Architecture

Status: M10I architecture boundary

Arqen architecture:

```text
Source
-> Lexer
-> Tokens
-> Parser
-> AST
-> Semantic
-> IR Lowering
-> Backend
-> Artifact
```

## Stage Boundaries

Source:

- input `.arq` path
- source text
- line endings normalized

Lexer:

- input: source text
- output: stable token stream
- errors: lexer diagnostics

Parser:

- input: token stream
- output: AST
- errors: parser diagnostics

Semantic:

- input: AST
- output: checked semantic model
- includes symbol table, resolved expressions, type info
- errors: semantic diagnostics

IR Lowering:

- input: checked semantic model
- output: ARQIR
- no Windows-specific details

Backend:

- input: ARQIR
- output: artifact
- current backend: `WindowsX64PE_MessageBoxBackend`

Artifact:

- generated `.exe`
- manifest
- logs

Current artifact manifest:

```text
Build\Manifests\<name>.manifest.txt
```

It records:

```text
ARTIFACT
SOURCE
IR
BACKEND
TARGET
STATUS
ACTIONS
EXIT_CODE
CREATED_AT
```

## Current Backend

```text
WindowsX64PE_MessageBoxBackend
```

It maps:

```text
show_message -> user32.dll!MessageBoxW
exit         -> kernel32.dll!ExitProcess
```

PE knowledge belongs in:

```text
Backends\WindowsX64PE
```

## Backend-Only Mode

The current driver can run the backend boundary directly:

```powershell
.\Tools\arqc_m10g.exe --backend-only .\Build\IR\hello_m10.arqir -o .\Build\EXE\hello_m10_from_ir.exe
```

This proves the backend consumes ARQIR without rereading `.arq` source, tokens, or AST.
