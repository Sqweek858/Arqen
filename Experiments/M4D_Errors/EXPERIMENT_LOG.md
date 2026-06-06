# M4D Errors Experiment Log

Status: `PARTIAL PASS`

Implemented:

- `A003` missing required field: `title`
- `A004` missing required field: `message`
- `A005` missing required field: `exit`

Generator:

```text
arqen_generator_m4d_errors.exe
```

Input:

```text
input/hello_m4d_bad_missing_message.arq
```

Result:

```text
GEN_EXIT: 4
ERROR_EXISTS: True
```

Error file:

```text
arqen_error.txt
```

Error text:

```text
Error A004:
Missing required field: message

Expected:
message text "Hello from Arqen"
```

Remaining M4D cases:

- string too long
- missing quotes
- unsupported exit code
- unknown keyword

## Additional Passes

```text
[missing_title] exit=3
Error A003:
Missing required field: title

Expected:
message title "Arqen Byte Zero"
```

```text
[missing_exit] exit=5
Error A005:
Missing required field: exit

Expected:
exit 0
```
