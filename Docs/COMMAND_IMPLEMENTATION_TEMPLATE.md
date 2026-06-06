# Command Implementation Template

Use this checklist before adding any new Arqen command.

Do not add a command by only patching one stage. Every command must be carried through lexer, parser, AST, semantic checks, codegen, tests, and docs.

## A. Language Design

Command name:

```text
TODO
```

Canonical syntax:

```text
TODO
```

Short alias:

```text
None for now unless explicitly approved.
```

Valid examples:

```text
TODO
```

Invalid examples:

```text
TODO
```

Meaning:

```text
TODO
```

## B. Lexer

New keywords:

```text
TODO
```

New symbols/operators:

```text
TODO
```

Token examples:

```text
TODO
```

Valid token dump:

```text
TODO
```

Lexer errors:

```text
TODO
```

## C. Parser

Grammar rule:

```text
TODO
```

Expected token sequence:

```text
TODO
```

AST node created:

```text
TODO
```

Parse errors:

```text
TODO
```

## D. AST

Node name:

```text
TODO
```

Fields:

```text
TODO
```

Example AST dump:

```text
TODO
```

## E. Semantic Checker

Symbol table effects:

```text
TODO
```

Type rules:

```text
TODO
```

Allowed values:

```text
TODO
```

Invalid cases:

```text
TODO
```

Semantic error codes:

```text
TODO
```

## F. Codegen

Compile-time behavior:

```text
TODO
```

Runtime behavior:

```text
TODO
```

PE/template changes:

```text
TODO
```

Output changes:

```text
TODO
```

## G. Tests

Valid test:

```text
TODO
```

Invalid syntax test:

```text
TODO
```

Invalid semantic test:

```text
TODO
```

Regression check:

```text
Previous milestone smoke tests must still pass.
```

## H. Docs

Update:

```text
Docs\MILESTONES.md
Docs\ERROR_CODES.md
Docs\TOKEN_DUMP_FORMAT.md if tokens change
Docs\AST_DUMP_FORMAT.md if AST changes
Samples\README.md if examples change
```

## Approval Rule

If the command adds runtime behavior, new PE imports, or a new control-flow shape, make it a separate milestone.

Do not combine command design, parser rewrite, and backend rewrite in one patch unless explicitly approved.
