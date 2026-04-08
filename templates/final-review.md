# Final Review — {{TICKET_ID}}

You are performing the final review for ticket {{TICKET_ID}} before creating a PR. This is the last quality gate.

## Context
- Repo: {{REPO_PATH}}
- Run directory: {{RUN_DIR}}
- Branch: {{BRANCH}}
- Platform: {{PLATFORM}} ({{CLI}})

## Review Checklist

### 1. All Tests Pass
Run the full test suite. Zero failures.

### 2. Full Diff Review
Review the complete diff from the branch:
```bash
git diff main...{{BRANCH}}
```
Look for: debug code, console.log, TODO/FIXME, hardcoded values, security issues.

### 3. Integration Verification
Do all the pieces work together? Trace the critical path end-to-end through the code.

### 4. Wiring Verification
Every new component is imported, registered, and reachable. No orphaned code.

### 5. Anti-Pattern Scan
- No `any` types (TypeScript)
- No console.log in production code
- No skipped tests
- No --no-verify commits
- No hardcoded secrets or credentials

### 6. Documentation
- CLAUDE.md / AGENTS.md / ARCHITECTURE.md updated if needed
- Progress.txt reflects all completed work

### 7. Branch Hygiene
- All commits on the correct branch
- No merge conflicts with main
- Commit messages follow conventions

### 8. Spec Completeness
Re-read `{{RUN_DIR}}/spec.md`. Is every requirement satisfied?

## Fixing Issues

Fix anything you find. Run tests. Commit with `fix({{TICKET_ID}}): <description>`.

## PR Creation

Do NOT create the PR yourself. The orchestrator calls `$HOUSTON_DIR/scripts/create-pr.sh` which handles format, reviewers, squash, delete branch, and auto-merge automatically.

## Completion
- `FINAL_REVIEW_COMPLETE` — ready for PR
- `FINAL_REVIEW_BLOCKED: <reason>` — critical issues that need human attention
