# BlendMixToCode Tests

Valid:

```text
blend mix to code 0
```

Invalid syntax:

```text
blend to code 0
blend mix code 0
blend mix to
```

Invalid semantic:

```text
blend mix to code true
blend mix to code 1
```

Regression:

```text
Tools\run_all_tests.ps1
```

must still pass after implementation.
