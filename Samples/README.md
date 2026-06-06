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

Current normal workflow:

```powershell
cd C:\Users\Sqweek\Documents\Arqen\Arqen
.\Tools\arqc_m10g.exe .\Samples\hello_m10.arq
.\Build\EXE\hello_m10.exe
```

Expected output:

```text
MessageBoxW title: Arqen Byte Zero
MessageBoxW text:  Hello, Sqweek
Exit code: 0
```

## Current Limitations

- Current driver is `Tools\arqc_m10g.exe`, not final `arqc.exe`.
- `let` values are literals only.
- `message text` is the only expression-enabled field.
- `+` supports text concatenation only.
- No if/else, functions, loops, UI/window/style, or non-zero exit code support yet.

Debug-only old M10 manual stages remain in:

```text
Experiments\M10_SimpleExpressions
```
