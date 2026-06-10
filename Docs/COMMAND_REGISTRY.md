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

## style

Canonical direct syntax:

```text
with style for "Panel"
    type: rectangle
    color: black
    opacity: 0.8
    visibility: visible
    clip children: false
end style
```

State-specific style blocks:

```text
with style for "PlayButton" when hovered
    background color: light blue
end style
```

Reusable style presets:

```text
define style called "PrimaryButton"
    background color: blue
    foreground color: white
    corner radius: 8 px
end style

use style "PrimaryButton" for "PlayButton"
use style "PrimaryButton" for "PlayButton" when selected
```

Supported M19B properties:

```text
type
display
color
background color
foreground color
accent color
border color
border size
outline color
outline size
corner radius
padding
margin
opacity
visibility
clip children
font
size
font weight
font style
text align
vertical align
line height
letter spacing
wrap
shadow color
shadow opacity
shadow blur
shadow spread
shadow offset x
shadow offset y
cursor
transition duration
transition easing
blend mode
z index
min width
min height
max width
max height
preferred width
preferred height
aspect ratio
overflow
pointer events
interactable
scale
scale x
scale y
rotation
translate x
translate y
pivot
transition property
transition delay
animation duration
animation easing
```

Supported M19B state suffixes are `hovered`, `pressed`, `disabled`, `focused`, `unfocused`, `active`, `selected`, `checked`, `loading`, `visited`, `dragged`, `dropped`, `error`, `warning`, and `success`.

Style blocks emit `STYLE|...`, `STYLE_PRESET|...`, and `STYLE_APPLY|...` metadata in AST/IR. They are not executable runtime/render actions yet; later UI/DX12 milestones consume the metadata after UI object and renderer contracts exist.

Tests:

- `Tests\CommandTests\style`

## ui_objects

Canonical syntax:

```text
define shape called "Panel"
define text called "Title"
define button called "PlayButton"
define slider called "VolumeSlider"
define input field called "NameInput"
define checkbox called "FullscreenCheck"
define dropdown called "QualityDropdown"

set content of "Title" to string "Hello world"
set range of "VolumeSlider" to 0, 100
set value of "VolumeSlider" to 50
set placeholder of "NameInput" to string "Enter name"
set checked of "FullscreenCheck" to false
add string "High" to "QualityDropdown"
```

Parser rule:

```text
UiObject := define UiObjectType called Name
UiSet := set UiProperty of Name to UiValue
UiDropdownOption := add string StringLiteral to Name
```

AST/IR metadata:

```text
UI_OBJECT|type=button|name=PlayButton
UI_SET|target=PlayButton|property=content|kind=text|value=Play
```

Semantic:

- rejects duplicate UI object names and collisions with existing symbols/windows
- validates target existence for UI setters
- validates property support per UI object type
- validates slider range/value as numeric
- validates checkbox checked state as boolean
- validates duplicate property assignment and duplicate dropdown options

Backend:

- metadata only in M19C
- accepted by strict IR parser
- ignored by WindowsX64PE executable generation until UI/DX12 consumes it

Tests:

- `Tests\CommandTests\ui_objects`


## ui_layout

Canonical forms:

```arq
parent "Title" to "Panel"

with layout for "Panel"
    x: 100 px
    y: 50 px
    width: 300 px
    height: 80 px
end layout

dock "Toolbar" to top of "Window"
```

AST/IR metadata:

```text
UI_PARENT|child=Title|parent=Panel
UI_DOCK|target=Toolbar|side=top|parent=Window
UI_LAYOUT|target=Panel|property=width|kind=dimension|value=300|unit=px
```

Backend: metadata only in M19D; strict IR accepts it but WindowsX64PE ignores it until UI layout/render milestones consume it.

Tests: `Tests\CommandTests\ui_layout`.

- `ui_final` - M19E/F/G/H UI final foundation: UI event metadata, binding/link metadata, state metadata, and UI resource metadata.
