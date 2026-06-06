# BlendMixToCode Language Design

Canonical syntax:

```text
blend mix to code 0
```

Meaning:

```text
Canonical Arqen final statement. It means finish the program with ExitProcess(code).
```

Valid examples:

```text
blend mix to code 0
```

Invalid examples:

```text
blend to code 0
blend mix code 0
blend mix to code true
blend mix to code 1
```

Notes:

```text
This is a draft only. M10H does not implement this command.
Initial implementation should support only code 0.
```
