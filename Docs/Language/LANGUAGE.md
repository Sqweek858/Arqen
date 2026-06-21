# Arqen Language Reference

This document is the main user-facing syntax reference. It summarizes the active language surface through the M61/M62 enum-scope work. M63-M66 are mostly tooling and repository hygiene milestones, so they do not substantially change the language syntax surface.

## Program wrapper

```arq
program "Example"
    message text "Hello"
end program "Example"
```

The program name is required and the `end program` name must match.

## Compile-time values

```arq
let name be "Sqweek"
let count be 3
let active be true
```

`let` declares compile-time values used by expression/lowering paths.

## Basic output

```arq
title "Window title"
message text "Hello, " + name
exit 0
```

Early MessageBox/PE paths use title/message/exit style commands.

## Canonical typed definitions

```arq
define int called "count" be 3
define string called "name" be string "Arqen"
define bool called "enabled" be true
define float called "ratio" be 1.5
define double called "precise" be 2.0
```

Additional typed literals exist for vectors, matrices, transforms, quaternions, geometry, color, angle and complex/math features. These are mostly compile-time/metadata features, not the main runtime state model.

## Runtime slots

```arq
define runtime int called "score" be 0
define runtime bool called "ready" be false
define runtime string called "status" be string "boot"
```

Runtime slots lower into backend runtime state.

## Runtime set/copy/print

Typical runtime operations include:

```arq
set runtime int "score" to 10
set runtime bool "ready" to true
set runtime string "status" to string "running"
copy runtime int "a" to "b"
copy runtime bool "flagA" to "flagB"
copy runtime string "left" to "right"
print runtime string "status"
```

Exact accepted phrasing is milestone-shaped; prefer existing tests as the executable source of truth when in doubt.

## Runtime conditions and loops

```arq
if runtime int "score" equals 10
    print runtime string "status"
end if

while runtime int "score" less than 10
    # runtime operations
end while
```

Supported control-flow concepts include runtime `if`, `else`, `while`, nested while, `break` and `continue`.

## Runtime string helpers

Runtime string/data utilities include:

- equality and inequality checks;
- case-insensitive equality and inequality;
- contains checks;
- concatenation;
- substring;
- parse-int into a runtime int slot.

## Functions

Function support includes void functions, typed returns, typed params, local runtime slots and function-to-function calls.

Conceptually:

```arq
define function "name"
    return
end function
```

Typed function work covers int, bool, string and enum returns/params. Recursive/cyclic call graphs are rejected.

## Arrays

Supported runtime array concepts:

- fixed-size int arrays;
- dynamic runtime-int indexing with bounds checks;
- bool arrays;
- string arrays;
- array length helper;
- local arrays inside functions;
- fixed-size arrays as function params with copy-in/copy-back;
- fill/copy utilities.

Not currently included: array returns, push/pop, slices and dynamic resizing.

## Records

Records group runtime fields:

- int fields;
- bool fields;
- string fields;
- enum fields;
- local records;
- record params with copy-in/copy-back;
- record arrays;
- record copy/reset utilities.

The current lowering is slot-based rather than packed binary struct memory.

## Enums

Enum support includes:

- enum definitions;
- runtime enum slots;
- set/copy enum values;
- runtime `if` on enum;
- enum params;
- enum returns;
- enum record fields;
- enum arrays.

Enums are int-backed internally.

## Switch

Runtime switch support exists for:

- enum values;
- int values.

Switch validation rejects invalid cases, unsupported values and unsafe forms according to the current semantic rules.

## Window/UI/DX12 branch

The experimental graphics branch includes syntax/metadata for:

- windows;
- styles;
- UI objects;
- layout and parenting;
- DX12 renderer metadata;
- frame/clear configuration;
- shader/vertex metadata;
- scene objects and input/navigation experiments.

This branch is active but experimental. Treat it separately from the core runtime language.

## Source of truth

For exact accepted syntax, use the tests under `Tests/CommandTests/` and `Tests/Samples/`. This document explains the language surface; tests remain the strict behavior reference.
