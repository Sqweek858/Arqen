# ARQIR v0

Status: bootstrap IR format

ARQIR v0 is a stable line-based IR format.

Example:

```text
ARQIR|version=0
TARGET|kind=program|name=Hello
META|source=Samples/hello_m10.arq
CONST|id=str_0|type=text|value=Arqen Byte Zero
CONST|id=str_1|type=text|value=Hello, Sqweek
CONST|id=i32_0|type=int|value=0
ACTION|id=act_0|op=show_message|title=str_0|text=str_1
ACTION|id=act_1|op=exit|code=i32_0
ENTRY|actions=act_0,act_1
END
```

Rules:

- Values are referenced by IDs.
- Actions are explicit.
- Backends consume actions.
- IR does not mention Windows APIs.
- IR does not mention PE headers, sections, RVAs, imports, IAT, or UTF-16.

Supported types:

```text
text
int
bool
```

Supported constants:

```text
text constants
int constants
bool constants
```

Supported actions:

```text
show_message(title, text)
exit(code)
```

Escaping:

```text
\\ = literal backslash
\p = literal |
\r = carriage return
\n = line feed
```

Future concepts:

- variables
- scopes
- functions
- branches
- loops
- diagnostics metadata
