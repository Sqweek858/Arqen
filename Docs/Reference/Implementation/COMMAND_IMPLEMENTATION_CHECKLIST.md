# Command Implementation Checklist

Every new Arqen command must pass this checklist before it is considered implemented.

## Design

- [ ] command name chosen
- [ ] canonical syntax written
- [ ] examples written
- [ ] invalid examples written
- [ ] meaning documented
- [ ] feature boundaries documented

## Lexer

- [ ] new keywords listed
- [ ] new symbols/operators listed
- [ ] token examples written
- [ ] token dump verified
- [ ] lexer errors added if needed

## Parser

- [ ] grammar rule added
- [ ] expected token sequence documented
- [ ] parser accepts valid examples
- [ ] parser rejects invalid syntax examples
- [ ] parse errors have codes

## AST

- [ ] AST node added
- [ ] fields documented
- [ ] AST dump example written
- [ ] stable AST format updated if needed

## Semantic

- [ ] symbol table effects documented
- [ ] type rules documented
- [ ] valid values listed
- [ ] invalid cases listed
- [ ] semantic error codes added

## Codegen

- [ ] compile-time behavior documented
- [ ] runtime behavior documented or explicitly none
- [ ] PE/template changes documented
- [ ] output changes documented
- [ ] codegen refuses semantic-failed AST

## Tests

- [ ] positive test added
- [ ] invalid syntax test added
- [ ] invalid semantic test added
- [ ] command test matrix updated
- [ ] previous milestone smoke tests still pass

## Docs

- [ ] `Docs\Language\LANGUAGE.md` updated
- [ ] `Tests\CommandTests\misc\<command>.command.txt` added or updated
- [ ] `Docs\Language\ERRORS.md` updated
- [ ] `Docs\Reference\Formats\TOKEN_DUMP_FORMAT.md` updated if tokens changed
- [ ] `Docs\Reference\Formats\AST_DUMP_FORMAT.md` updated if AST changed
- [ ] samples updated if needed

## Final

- [ ] `Tools\test.ps1 -Folder <command_folder>` passes, or `Tools\test.ps1 -AllCommand` passes for broad verification
- [ ] milestone log written
- [ ] no unrelated language features slipped in
