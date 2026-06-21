# Arqen Documentation

This folder is the main documentation surface for the Arqen repository.

Most Markdown and text documentation should live under `Docs/` or `Tests/`. The approved exceptions are the root `README.md`, `What_I_Can_Do/README.md`, and `VisualStudio/README.md`, because those files document local entrypoints that are useful when browsing the repository or opening the Visual Studio solution.

## Main sections

- `Milestones/` - grouped milestone history and workflow notes.
- `Info/` - practical project information: terminal commands, tools, repo layout, build output rules, contribution rules, and current status.
- `Language/` - user-facing language syntax and diagnostic/error reference.
- `Reference/` - technical contracts for IR, backends, runtime actions, file formats, and Windows x64 details.

## Current status

Arqen is an experimental programming language and compiler/toolchain built incrementally in C#. The current line is around M70 on the tooling/workflow line. The active compiler is still the M10G driver line, but the repository now includes a broad runtime-language surface, an experimental DX12/UI branch, a root `run_me.ps1` health console, a `What_I_Can_Do/` showcase area, and a contained Visual Studio solution for building the showcase and DX12 demo.

The project is not presented as a finished production language. It is a research/prototype toolchain with strict milestone validation and a growing test suite.
