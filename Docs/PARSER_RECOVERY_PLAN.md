# Parser Recovery Plan

Status: future plan

M10H does not implement full parser recovery. It documents the target behavior.

## Current Behavior

The parser stops on the first parse or semantic failure.

This is acceptable for M10/M10G because:

- codegen never runs after failure
- errors include a stage and code
- M10G writes stage-specific error files

## Future Target

The parser should eventually report:

- error code
- line
- column
- actual token
- expected token or grammar rule
- short fix suggestion

Example:

```text
Error P011 at line 8, column 23:
Expected expression after +.

Expected:
STRING or IDENT
```

## Recovery Strategy

Planned recovery levels:

1. Stop cleanly at first error.
2. Skip to next newline and report one error per line.
3. Continue within block until `end program`.
4. Later: collect multiple errors without codegen.

## Hard Rules

- Never generate code after parse failure.
- Never generate code after semantic failure.
- Never overwrite a known-good exe after codegen failure.
- Keep line/column tied to the original source token.

## Future Work

Suggested milestone:

```text
M10R_GenericParser
```

Possible output:

```text
Build\Errors\file.parse.error.txt
Build\Errors\file.semantic.error.txt
```
