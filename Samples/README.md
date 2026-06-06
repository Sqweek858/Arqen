# Arqen Samples

## Current Canonical Sample

```text
Samples\hello_m10.arq
```

Source:

```text
program "Hello"

let name be "Sqweek"
let number be 0
let active be true

title "Arqen Byte Zero"
message text "Hello, " + name
exit 0

end program "Hello"
```

## How To Compile Today

M10 still uses fixed-path bootstrap tools, so copy the sample into the M10 experiment input:

```powershell
cd C:\Users\Sqweek\Documents\Arqen\Arqen
Copy-Item .\Samples\hello_m10.arq .\Experiments\M10_SimpleExpressions\m10.arq -Force
cd .\Experiments\M10_SimpleExpressions
.\arq_lexer_m10_tokens.exe
.\arq_parser_m10.exe
.\arqc_m10.exe
.\m10.exe
```

Expected output:

```text
MessageBoxW title: Arqen Byte Zero
MessageBoxW text:  Hello, Sqweek
Exit code: 0
```

## Current Limitations

- No single `arqc hello_m10.arq` driver yet.
- `let` values are literals only.
- `message text` is the only expression-enabled field.
- `+` supports text concatenation only.
- No if/else, functions, loops, UI/window/style, or non-zero exit code support yet.
