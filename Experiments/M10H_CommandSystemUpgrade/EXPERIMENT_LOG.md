# M10H Command System Upgrade

Status: PASSED

## Goal

Create a structured internal system for adding future Arqen commands.

No new language syntax was implemented.

## Created

```text
Docs\COMMAND_REGISTRY.md
Docs\COMMAND_IMPLEMENTATION_CHECKLIST.md
Docs\PARSER_RECOVERY_PLAN.md
Docs\SYMBOL_TABLE_FORMAT.md
Docs\EXPRESSION_SYSTEM_M10.md
Docs\CODEGEN_CONTRACT_M10.md
Specs\Commands\*.command.txt
Tools\new_command_scaffold.ps1
Tests\CommandTests\...
Experiments\CommandDrafts\BlendMixToCode\...
```

## Scaffold

Usage:

```powershell
.\Tools\new_command_scaffold.ps1 CommandName
```

Creates:

```text
Experiments\CommandDrafts\CommandName
LANGUAGE_DESIGN.md
COMMAND_SPEC.command.txt
LEXER_CHANGES.md
PARSER_CHANGES.md
AST_CHANGES.md
SEMANTIC_CHANGES.md
CODEGEN_CHANGES.md
TESTS.md
IMPLEMENTATION_CHECKLIST.md
```

## Command Tests

Added command test folders:

```text
Tests\CommandTests\program
Tests\CommandTests\let
Tests\CommandTests\message_text
Tests\CommandTests\exit
```

Each folder has:

```text
*.arq
expected.txt
```

## Verification

```text
Tools\run_all_tests.ps1
Total: 52/52 passed
```

## Draft Command

Created draft only:

```text
Experiments\CommandDrafts\BlendMixToCode
```

Canonical draft syntax:

```text
blend mix to code 0
```

This command is not implemented in M10H.

## Known Limitations

- Command specs are documentation/source-of-truth files, not code generation yet.
- Test runner can discover command tests, but it is still simple PowerShell.
- New commands still require manual compiler changes.
- M10G driver remains the active compiler path.
