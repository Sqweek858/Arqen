# Build Output Policy

`Build/` is a generated-output directory. It may contain tokens, AST dumps, IR, diagnostics, executable output, logs, generated C++/headers and validator reports during local development.

Do not commit generated build output unless it is intentionally moved into `Tests/` as a fixture.

## Main generated-output locations

```text
Build/Generated/
Build/Logs/
Build/Temp/
Build/EXE/
Build/IR/
Build/Tokens/
Build/AST/
Build/Diagnostics/
Build/Errors/
```

## Showcase generated-output locations

The `What_I_Can_Do/` showcase keeps generated files in its own local output folders:

```text
What_I_Can_Do/Build/Artifacts/
What_I_Can_Do/Build/*.build.log
What_I_Can_Do/Exe/
```

`What_I_Can_Do/Build/build_all.ps1`, `What_I_Can_Do/Build/.gitkeep` and `What_I_Can_Do/Exe/.gitkeep` are source/control files. Other generated files under those folders are local output and should not be committed.

## Visual Studio generated-output locations

The contained Visual Studio shell keeps local Visual Studio state and logs under:

```text
VisualStudio/.vs/
VisualStudio/Trash/
```

`VisualStudio/Trash/.gitkeep` is intentionally tracked so the folder exists. Build logs and other local artifacts under `VisualStudio/Trash/` should not be committed.

## Native intermediate files

Native files such as `.obj`, `.pdb`, `.ilk`, `.exp` and `.lib` should not be left in the repository root. DX12 native build helpers should place intermediate files under the configured build/artifact directory.
