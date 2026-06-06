# Command Registry

Status: M10H command system infrastructure

This registry documents the current Arqen constructs. It is the human-readable companion to `Specs\Commands\*.command.txt`.

M10H does not add new syntax.

## program / end program

Canonical syntax:

```text
program "Hello"
...
end program "Hello"
```

Token pattern:

```text
KEYWORD(program) STRING
...
KEYWORD(end) KEYWORD(program) STRING
```

Parser rule:

```text
Program := program Name Statements end program Name
```

AST:

```text
PROGRAM|Hello
```

Semantic:

- program name is required
- end program name must match

Codegen:

- no direct codegen yet

Tests:

- `Tests\CommandTests\program`

Limitations:

- no modules or nested programs

## let / be

Canonical syntax:

```text
let name be "Sqweek"
let number be 0
let active be true
```

Token pattern:

```text
KEYWORD(let) IDENT KEYWORD(be) LITERAL
```

Parser rule:

```text
Let := let Identifier be Literal
```

AST:

```text
LET|name|text|Sqweek
LET|number|int|0
LET|active|bool|true
```

Semantic:

- declares a compile-time variable
- rejects duplicate names
- let values are literals only

Codegen:

- no direct codegen
- values can be folded into message expressions

Tests:

- `Tests\CommandTests\let`

Limitations:

- no reassignment
- no scopes
- no expression values in let

## title

Canonical syntax:

```text
title "Arqen Byte Zero"
```

Token pattern:

```text
KEYWORD(title) STRING
```

Parser rule:

```text
Title := title StringLiteral
```

AST:

```text
TITLE|Arqen Byte Zero
```

Semantic:

- title must be text
- title must fit current PE template buffer

Codegen:

- written as UTF-16LE into the MessageBox title buffer

Tests:

- covered by message/program smoke tests

Limitations:

- title expressions are not supported

## message text

Canonical syntax:

```text
message text "Hello, " + name
```

Token pattern:

```text
KEYWORD(message) KEYWORD(text) Expression
```

Parser rule:

```text
MessageText := message text TextExpression
```

AST:

```text
MESSAGE|Hello, Sqweek
MESSAGE_EXPR|plus(str("Hello, "),var(name))
```

Semantic:

- expression must resolve to text
- unknown variables are rejected
- text + text is allowed
- text + bool/int is rejected

Codegen:

- folded text is written as UTF-16LE into the MessageBox message buffer

Tests:

- `Tests\CommandTests\message_text`

Limitations:

- only compile-time folding
- no runtime string allocation

## exit

Canonical syntax:

```text
exit 0
```

Token pattern:

```text
KEYWORD(exit) INT
```

Parser rule:

```text
Exit := exit IntLiteral
```

AST:

```text
EXIT|0
```

Semantic:

- only `0` is currently supported

Codegen:

- generated PE calls `ExitProcess(0)`

Tests:

- covered by smoke tests

Limitations:

- no non-zero exit code support yet

## Literals

Canonical syntax:

```text
"text"
0
true
false
```

Token pattern:

```text
STRING
INT
BOOL
```

AST:

```text
text/int/bool values inside LET or expression nodes
```

Semantic:

- type inferred from literal kind

Codegen:

- only text values used in MessageBox output today

Limitations:

- no escape sequences in source strings yet

## Plus Expression

Canonical syntax:

```text
"Hello, " + name
```

Token pattern:

```text
Expression PLUS Expression
```

AST:

```text
MESSAGE_EXPR|plus(str("Hello, "),var(name))
```

Semantic:

- only text + text is supported

Codegen:

- folded at compile time

Tests:

- `Tests\CommandTests\message_text`

Limitations:

- no int math
- no bool logic
- no runtime expression evaluation
