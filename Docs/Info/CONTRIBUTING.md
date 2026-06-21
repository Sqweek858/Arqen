# Contributing Rules

Arqen is milestone-driven. Keep changes small, testable and reversible.

## Required discipline

- Every new syntax form needs at least one positive test and one negative test.
- Do not change parser, semantic or backend behavior without updating validation.
- Prefer small vertical slices over broad refactors.
- Keep generated output out of the repository.
- Keep Markdown/text documentation under `Docs/` or `Tests/`, except for the approved README entrypoints documented in `Docs/Info/REPO_LAYOUT.md`.
- Do not add `.md` or `.txt` files beside source code, backend code or tools unless the path has been explicitly approved as a local entrypoint README.

## Recommended patch shape

1. Update code.
2. Add/update tests.
3. Add/update docs under `Docs/` or an approved local README if the change is about a local entrypoint.
4. Run the relevant validator or test slice.
5. Report exact commands and pass/fail output.

## Current warning

Large refactors of `Parser.Statements.cs`, backend lowering or function/array/record/enum scope should be treated as separate milestones, not mixed into cleanup patches.
