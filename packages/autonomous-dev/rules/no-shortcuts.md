# No Shortcuts — The #1 Rule

> GitHub is the ONLY source of truth. Every change must go through code → commit → CI/CD.

## Forbidden Actions

```
NEVER:
- Hotfix production directly
- SSH into servers to fix things
- Manually patch containers or deployments
- Bypass CI/CD pipelines
- Push directly to main without PR
- Skip tests to "unblock"
- Hardcode values to pass tests
- Comment out failing tests
- Use environment-specific hacks
- "Fix in prod, backport later"
- Suppress errors without fixing root cause
```

## The Only Acceptable Path

```
ALWAYS:
- Write fixes in source code
- Write tests that verify the fix
- Run ALL tests locally — pass? continue
- Run typecheck locally — pass? continue
- Run build locally — pass? continue
- ALL checks pass? NOW commit
- Push to GitHub
- CI/CD runs (should NEVER fail — verified locally!)
- Merge via PR
- Let CI/CD deploy
- Document learning in progress.txt
```

## Pre-Commit Loop

```
Code Change
    |
    v
Run tests ----FAIL----> Fix --+
    |                         |
   PASS                       |
    |                         |
    v                         |
Run typecheck ---FAIL----> Fix-+
    |
   PASS
    |
    v
Run build ----FAIL----> Fix --+
    |
   PASS
    |
    v
  COMMIT

CI/CD failure = you skipped this loop = shortcut taken
```

## Why This Matters

Shortcuts create:
- Drift between code and production state
- Unreproducible environments
- Missing test coverage
- Hidden technical debt that compounds

A "quick fix" in Story 5 breaks Stories 15, 23, and 41.

## Enforcement

Hooks in `hooks/` enforce these rules automatically:

| Hook | Enforces |
|------|---------|
| `pre-commit-gate.sh` | Blocks `git commit` if tests fail |
| `post-edit-tests.sh` | Runs tests after every file edit |
| `block-shortcuts.sh` | Blocks ssh, docker exec, kubectl exec |
| `inject-rules.sh` | Re-injects rules after context compaction |

See `hooks/README.md` for installation.
