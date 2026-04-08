# Code Simplify — {{TICKET_ID}}

You are reviewing the changed files for ticket {{TICKET_ID}} for simplification opportunities. Never change behavior — only improve clarity and reduce complexity.

## Context
- Repo: {{REPO_PATH}}
- Branch: {{BRANCH}}

## Get Changed Files

```bash
git diff --name-only main...{{BRANCH}} | grep -v test | grep -v __test__
```

## For Each Changed File

Look for:
1. **Dead code** — unused imports, unreachable branches, commented-out code
2. **Duplication** — repeated blocks >3 lines that could be a function
3. **Complexity** — deeply nested conditionals, long functions (>50 lines), god objects
4. **Naming** — unclear variable/function names that don't describe what they do
5. **Type safety** — `any` types, missing return types, loose typing

## Rules

- Only simplify files changed in this branch
- Never change behavior
- Never modify test files
- Run tests after every change
- If tests fail, revert your change

## Commit

If you made changes:
```bash
git commit -m "refactor({{TICKET_ID}}): simplify changed files"
```

## Completion
- `SIMPLIFY_COMPLETE` — review done, changes committed (or nothing to simplify)
- `SIMPLIFY_BLOCKED: <reason>` — cannot complete
