# Expression System M10

Status: current M10/M10G contract

## Supported Nodes

```text
StringLiteral
IntLiteral
BoolLiteral
VariableRef
BinaryPlus
```

## Supported Use Site

Only:

```text
message text <expression>
```

## Current Evaluation

All supported message expressions are folded at compile time.

Example:

```text
let name be "Sqweek"
message text "Hello, " + name
```

Folded result:

```text
Hello, Sqweek
```

## Allowed

```text
text
text + text
text + text + text
text variable + text literal
```

## Rejected

```text
text + int
text + bool
int + int
bool logic
unknown variable
broken plus
```

Current errors:

```text
S010 unknown variable
S011 type mismatch
S012 message text requires text expression
S013 unsupported expression type
P011 expected expression after +
```

## Stable AST Expression Examples

```text
MESSAGE_EXPR|var(name)
MESSAGE_EXPR|plus(str("Hello, "),var(name))
MESSAGE_EXPR|plus(plus(str("Hello"),str(" from ")),str("M10"))
```

## Future Expansion

Possible future milestones:

- int math
- explicit conversions
- bool comparisons
- runtime evaluation
- non-message expression sites
