# Quality Gates — Three-Tier System

Quality is enforced at three levels with increasing thoroughness. Run via `./scripts/quality-gate.sh --scope <level>`.

## The Three Tiers

### Story Scope (`--scope story`)
Fast per-story check. Run after every commit.
- **Package tests** — Tests in the current package/directory
- **ROOT typecheck** — `tsc --noEmit` at PROJECT ROOT (catches cross-package type gaps like missing union members)
- **Lockfile** — Uncommitted lockfile changes

**Why root typecheck at story level:** A worker adding `mcpServerConfigure` as an audit action in one package
needs the `AuditAction` union type updated in another package. Package-level typecheck won't catch this.
Root-level typecheck will. It's fast (~5-10s) and catches the most common cross-package gap.

### Phase Scope (`--scope phase`)
Thorough per-phase check. Run at phase review.
- **Full test suite** — ALL packages, run at project root (catches mock isolation issues, test convention gaps)
- **ROOT typecheck** — Same as story
- **Build** — Full project build
- **Lockfile** — Same as story
- **No shortcuts** — Scan for `.skip`, `.only`, `xit`, `xdescribe`, `fdescribe`, `fit`

**Why full test suite at phase level:** A worker adding a new component might break an existing test in
another package (e.g., a mock that assumed only one fetch call, or a route integrity test with an allowlist).
Package tests won't catch this. The full suite will.

### Final Scope (`--scope final`)
Everything. Run at final E2E review before PR.
- **Full test suite** — All packages
- **ROOT typecheck** — Full project
- **Build** — Full project
- **Docker build** — If applicable
- **E2E tests** — If available
- **No shortcuts** — Scan for skipped/focused tests
- **Project CI scripts** — Auto-discovers and runs project-specific CI validation scripts (e.g. `check-devdep-imports.sh`)
- **Lockfile** — Same as story

## When Each Tier Runs

| Context | Scope | Who Runs It |
|---------|-------|-------------|
| After each story commit | `--scope story` | Worker (self) + Phase Runner (verification) |
| Phase review (tester) | `--scope phase` | Tester agent |
| Final E2E review | `--scope final` | Final reviewer agent |

## What Each Tier Catches

| Gap Type | Story | Phase | Final |
|----------|-------|-------|-------|
| Package test failures | yes | yes | yes |
| Cross-package type errors | yes | yes | yes |
| Cross-package test regressions | no | yes | yes |
| Mock isolation issues | no | yes | yes |
| Test convention gaps (allowlists) | no | yes | yes |
| Build failures | no | yes | yes |
| Docker build failures | no | no | yes |
| E2E failures | no | no | yes |
| Anti-pattern scan | yes | yes | yes |
| Wiring checklist verification | no | yes | yes |
| Reachability (test-only exports) | no | yes | yes |
| Skipped/focused tests | no | yes | yes |
| Project CI scripts (devDep checks, etc.) | no | yes | yes |

## Baseline Diffing

Before any work begins, `orchestrate.sh` captures a baseline:

```bash
./scripts/quality-gate.sh --baseline capture
# Runs phase-scope gate, saves failures to .baseline-failures.txt
# Full output saved to .baseline-gate.log (researcher reads this)
```

All subsequent gates **diff against baseline**:
- **New failure** (not in baseline) → BLOCKED
- **Pre-existing failure** (in baseline) → WARN (not counted, exit 0)
- **All pass** → PASS

This prevents workers from being blocked by bugs that existed before they started.
The researcher reviews `.baseline-gate.log` and documents pre-existing issues as constraints.

## Running Gates

```bash
# Capture baseline (once at pipeline init)
./scripts/quality-gate.sh --baseline capture

# Per-story (fast, ~30s, diffs against baseline)
./scripts/quality-gate.sh --scope story

# Per-phase (thorough, ~3-5 min, diffs against baseline)
./scripts/quality-gate.sh --scope phase

# Final (everything, ~10 min)
./scripts/quality-gate.sh --scope final

# Default (no --scope): phase
./scripts/quality-gate.sh
```

## Gate Failure Policy

- **Test failure**: Fix before committing. Never skip or comment out tests.
- **Typecheck failure**: Fix type errors. Never use `// @ts-ignore` without explaining why.
- **Build failure**: Fix before completing the phase.
- **Docker failure**: Fix before final review.
- **Lockfile drift**: Commit the lockfile or revert the dependency change.
- **Skipped tests**: Remove `.skip`/`.only` before marking phase complete.
