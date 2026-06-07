# ARQIR V0 Contract

ARQIR V0 is the current text IR boundary between the Arqen front-end and backend artifact generation.

## Required header

```text
ARQIR|version=0
TARGET|kind=program|name=<program>
META|source=<relative source path>
```

## Constants

```text
CONST|id=<id>|type=<type>|value=<escaped value>
```

Current backend-supported constant types are:

```text
text
int
```

Compile-time-only math types may appear in AST output, but should not be required by the current WindowsX64PE backend until a backend explicitly supports them.

## Actions

```text
ACTION|id=<id>|op=<operation>|<fields>
```

Every action `op` must be present in the backend capability table. Unsupported operations must be rejected before backend artifact writing.

## Entry

```text
ENTRY|actions=<comma-separated action ids>
END
```

## DX12 rule

DX12 actions are reserved but unsupported in M18B. `dx12`, `shader`, `render_pass`, and `frame_update` must be rejected by backend capability validation until the DX12 backend exists.

## Pipeline boundary

ARQIR v0 sits between the lexer/parser/semantic pipeline and the backend, so every backend action must stay visible as a capability-checked IR action.

## Strict validation rules

M18I makes ARQIR v0 strict enough for pre-DX12 work:

- `ARQIR`, `TARGET`, `ENTRY`, and `END` are required.
- `ARQIR`, `TARGET`, and `ENTRY` may appear only once.
- Unknown top-level line kinds are invalid.
- Duplicate `CONST` ids are invalid.
- Duplicate `ACTION` ids are invalid.
- Every `ACTION` must include both `id` and `op`.
- `ENTRY|actions=...` must reference existing action ids.
- Every entry action must pass the C# backend capability gate, not only wrapper-side PowerShell checks.

These rules intentionally keep DX12, shader, render pass, and frame update operations rejected until a real runtime/backend implementation exists.
