# Arqen IR

Arqen IR is the boundary between the language front-end and backend artifact generation.

Current architecture:

```text
Source -> Lexer -> Tokens -> Parser -> AST -> Semantic -> IR -> Backend -> Artifact
```

Current format:

```text
ARQIR v0
```

Docs:

```text
IR\Formats\ARQIR_V0.md
Docs\IR_FORMAT_ARQIR_V0.md
Docs\BACKEND_ARCHITECTURE.md
Docs\BACKEND_CONTRACT.md
```
