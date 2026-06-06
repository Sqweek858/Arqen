# BlendMixToCode Parser Changes

Grammar:

```text
BlendMixToCode := blend mix to code IntLiteral
```

Expected sequence:

```text
KEYWORD(blend)
KEYWORD(mix)
KEYWORD(to)
KEYWORD(code)
INT
```

Parse errors:

```text
missing mix
missing to
missing code
missing int
```
