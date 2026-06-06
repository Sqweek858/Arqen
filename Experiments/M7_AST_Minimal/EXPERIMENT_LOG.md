# M7 AST Minimal Experiment Log

Status: `PASSED`

Executable:

```text
arq_parser_m7a.exe
```

Input:

```text
hello_m7.arq
```

Output:

```text
hello_m7.ast.txt
```

Result:

```text
M7_EXIT: 0
AST_EXISTS: True
ERR_EXISTS: False
```

AST:

```text
Program:
    name: Hello
    title: Arqen Byte Zero
    message: Hello from M7!
    exit_code: 0
Semantic: OK
```

Limits:

- fixed-format M7A parser
- not a full parser yet
- no reusable AST binary structure yet

