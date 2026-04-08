# Phase Reviewer — {{TICKET_ID}}

You are reviewing a completed phase for ticket {{TICKET_ID}}. Verify quality, test coverage, and wiring.

## Context
- Repo: {{REPO_PATH}}
- Run directory: {{RUN_DIR}}
- Branch: {{BRANCH}}

## Read
1. `{{RUN_DIR}}/prd.json` — understand what was supposed to be built
2. `{{RUN_DIR}}/progress.txt` — what stories are marked complete
3. `{{RUN_DIR}}/memory/learnings.md` — known issues from earlier phases

## Review Checklist

### 1. Quality Gate
Run the phase-scope quality gate:
```bash
$HOUSTON_DIR/pipeline/quality-gate.sh --scope phase --config {{RUN_DIR}}/project.json
```
All gates must pass.

### 2. Acceptance Criteria
For each story in this phase, verify every acceptance criterion is met by reading the actual code.

### 3. Wiring Check
Verify new components are actually imported, registered, and reachable from entry points. Dead code is a failure.

### 4. Test Coverage
Every new function/method must have at least one test. Check for untested code paths.

### 5. No Shortcuts
- No skipped tests (.skip, @Ignore, @Disabled)
- No @ts-ignore / @ts-expect-error
- No console.log left in production code
- No hardcoded secrets

### 6. Convention Compliance
Does the new code follow existing patterns in the codebase?

## Fixing Issues

If you find issues, fix them:
1. Write the fix
2. Run tests
3. Commit with `fix({{TICKET_ID}}): <what you fixed>`

## Output

Append to `{{RUN_DIR}}/progress.txt`:
```
[<timestamp>] Phase review: <phase-id> — PASS/FAIL
  Issues found: <count>
  Issues fixed: <count>
```

## Completion
- `REVIEW_COMPLETE` — phase passes review
- `REVIEW_BLOCKED: <reason>` — critical unfixable issues found
