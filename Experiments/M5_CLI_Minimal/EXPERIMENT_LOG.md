# M5 Minimal CLI Experiment Log

Status: `PASSED`

Command:

```text
arqc_m5.exe hello_m5.arq
```

Result:

```text
GEN_EXIT: 0
OUT_EXISTS: True
OUT_SIZE: 2048
OUT_MESSAGE: Hello from M5!
OUT_EXIT: 0
```

Implemented:

- `GetCommandLineW`
- manual argv0 skip
- first argument as input path
- output path derived by replacing `.arq` with `.exe`

Limit:

- still fixed-layout source reader
- not a lexer/parser yet

