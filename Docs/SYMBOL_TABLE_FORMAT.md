# Symbol Table Format

Status: M10 contract

## Purpose

The symbol table tracks declared names during semantic checks.

Current M10/M10G variables are compile-time constants.

## Current Variable Record

Recommended record:

```text
name
type
value
declaration_line
declaration_column
mutability
scope
```

Current M10G effective record:

```text
name: string
type: text | int | bool
value: compile-time literal
declaration_line: token line
declaration_column: token column
mutability: const
scope: program
```

## Current Rules

- `let <identifier> be <literal>` declares a variable.
- duplicate variable names are rejected.
- unknown variable references are rejected.
- all values are compile-time known.
- message expressions are folded at compile time.

## Current Types

```text
text
int
bool
```

## Stable Dump Draft

If a symbol dump is added later:

```text
SYMBOL|name|type|value|line|column|const|program
```

Example:

```text
SYMBOL|userName|text|Sqweek|3|5|const|program
```

## Future Work

Later additions:

- scopes
- mutable variables
- function parameters
- runtime-only values
- type conversions
- shadowing rules
