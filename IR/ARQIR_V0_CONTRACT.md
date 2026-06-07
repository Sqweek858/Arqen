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
