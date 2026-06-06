# IR Format: ARQIR v0

ARQIR v0 is documented in:

```text
IR\Formats\ARQIR_V0.md
```

Current M10I lowering:

```text
checked semantic model
-> constants
-> show_message action
-> exit action
-> entry action list
```

M10 message expressions are folded before IR. There is no runtime string engine yet.

Current generated IR path:

```text
Build\IR\<name>.arqir
```
