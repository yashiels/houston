# Quality Gates

Houston uses a 3-tier quality gate system. Each tier runs progressively more thorough checks.

## Tier 1: Story Scope (~30 seconds)
Runs after each story completes.
- Package/unit tests
- Typecheck
- Anti-pattern scan on changed files

## Tier 2: Phase Scope (~3-5 minutes)
Runs after all stories in a phase complete.
- Full test suite
- Full typecheck
- Build
- Lint
- Anti-pattern scan

## Tier 3: Final Scope (~10 minutes)
Runs before PR creation.
- Everything from Phase scope
- E2E tests (if configured)
- Docker build (if configured)
- Full anti-pattern scan
- Security scan (hardcoded secrets)

## Baseline Diffing

Pre-existing failures are captured at pipeline init as a baseline. During quality gates:
- **Pre-existing failures** → WARN (don't block)
- **New failures** → FAIL (block pipeline)

This prevents agents from being blocked by legacy issues while ensuring they don't introduce new ones.
