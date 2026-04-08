# Houston Development Methodology

## TDD (Test-Driven Development)

Every code change follows Red → Green → Refactor:
1. **Red** — Write a failing test that defines the desired behavior
2. **Green** — Write the minimum code to make it pass
3. **Refactor** — Clean up while keeping tests green

## Context Budget

Disposable agents have limited context. Spend it wisely:
- **Bootstrap:** 3 minutes max. Read only what's needed for the current task.
- **Working set:** Keep under 15k tokens of source code in context.
- **Generation budget:** Reserve 50k+ tokens for actual code generation.
- **Anti-patterns:** Avoid bulk directory reads, loading entire test suites, passing full prd.json in spawn prompts.

## Commit Discipline

- Commit after each unit of work (test + implementation)
- Each commit should leave tests passing
- Commit message format: `feat|fix|refactor|test(<ticket-id>): <description>`
- Never commit with --no-verify

## Quality Gates

Three tiers of increasing rigor:
1. **Story** — After each story: unit tests + typecheck + anti-pattern scan
2. **Phase** — After each phase: full tests + build + lint
3. **Final** — Before PR: everything + E2E + security scan

## Memory Across Stages

Each disposable agent starts fresh. Cross-stage continuity via:
- `research/findings.md` — what the researcher found
- `prd.json` — the implementation plan
- `memory/learnings.md` — accumulated insights
- `memory/phase-N-summary.md` — per-phase summaries
- `progress.txt` — human-readable log
