# Single `arqc` Driver Plan

Status: implemented in M10G as `Tools\arqc_m10g.exe`

M10G implemented the first single-driver workflow without adding language syntax.

Completed milestone:

```text
M10G_CorePipelineUpgrade
```

## Goal

Current M10 pipeline requires three tools:

```text
arq_lexer_m10_tokens.exe
arq_parser_m10.exe
arqc_m10.exe
```

Desired future command:

```text
arqc hello.arq
```

Current M10G command:

```powershell
.\Tools\arqc_m10g.exe .\Samples\hello_m10.arq
```

Expected output:

```text
hello.exe
```

## Current Separate Inputs And Outputs

M10 current:

```text
m10.arq
-> m10.tokens.txt
-> m10.ast.txt
-> m10.exe
```

Current limitations:

- fixed filenames
- fixed folder
- each stage must be run manually
- codegen requires `template_messagebox_m8.exe`

## Desired Interface

Basic:

```text
arqc hello_m10.arq
```

Optional later:

```text
arqc build hello_m10.arq
arqc build hello_m10.arq -o hello.exe
```

## Required Behavior

The driver should:

1. Read command line.
2. Validate input file exists.
3. Decide output exe path.
4. Run lexer stage.
5. Stop on lexer error.
6. Run parser stage.
7. Stop on parser/semantic error.
8. Run codegen stage.
9. Stop on codegen error.
10. Print or write clear summary.

## Risks

- Current tools use fixed filenames.
- Current parser/codegen are milestone-shaped.
- Running sub-tools requires either process creation or merging stages.
- A full merge may be too much before generic parser work.

## Implemented M10G Approach

Current:

```text
arqc_m10g.exe Samples\hello_m10.arq
```

Implemented:

- accepts an input `.arq` path
- supports `-o custom.exe`
- writes stable tokens to `Build\Tokens`
- writes stable AST to `Build\AST`
- writes output exe to `Build\EXE`
- writes errors to `Build\Errors`
- writes logs to `Build\Logs`

Not allowed in M10G:

- if/else
- new commands
- new expression types
- UI/window syntax

## Pass Criteria

```text
Tools\arqc_m10g.exe Samples\hello_m10.arq
-> Build\EXE\hello_m10.exe
-> MessageBoxW title "Arqen Byte Zero"
-> MessageBoxW text "Hello, Sqweek"
-> exit 0
```

Regression:

```text
Tools\run_all_tests.ps1
```

must still pass.
