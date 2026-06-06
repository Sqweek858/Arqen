# Backend Contract

Every backend must define:

- backend name
- supported IR version
- supported actions
- unsupported actions
- target platform
- target artifact type
- required imports/runtime
- output path
- temp path behavior
- diagnostics behavior
- failure behavior

## Current Backend

Backend name:

```text
WindowsX64PE_MessageBoxBackend
```

Supported IR:

```text
ARQIR version 0
```

Supported actions:

```text
show_message
exit
```

Unsupported actions:

```text
branches
loops
functions
windows/ui/style actions
runtime allocation
```

Target:

```text
windows-x64-pe
```

Artifact:

```text
.exe
```

Required imports:

```text
user32.dll!MessageBoxW
kernel32.dll!ExitProcess
```

Failure behavior:

- write backend diagnostics
- do not overwrite final exe unless temp output succeeds
- do not report backend errors as parser errors

Current diagnostic path:

```text
Build\Diagnostics\Backend\<name>.backend.diagnostic.txt
```

Current manifest path:

```text
Build\Manifests\<name>.manifest.txt
```

Backend-only mode:

```powershell
.\Tools\arqc_m10g.exe --backend-only <input.arqir> -o <output.exe>
```

In this mode, `.arq` source, token dumps, parser output, and AST output are not required by the backend.
