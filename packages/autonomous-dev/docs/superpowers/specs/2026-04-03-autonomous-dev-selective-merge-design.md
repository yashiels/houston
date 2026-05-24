# Design: Selective Merge — ExiPay Features into autonomous-dev

**Date:** 2026-04-03  
**Status:** Approved (post-grill)  
**Repo:** skyner-group/autonomous-dev  
**Goal:** Elevate the canonical openclaw autonomous-dev with ExiPay's proven improvements, keeping the repo generic and multi-LLM capable for multiple developers on openclaw.

---

## Background

Three autonomous-dev implementations were compared:
- **Our repo** (canonical): multi-LLM, hooks, SKILL.md, orchestrate.sh state machine
- **Priyen's** (autonomous-claude-main): simpler, Claude-only, no hooks, no SKILL.md
- **ExiPay** (yashiels/exipay-autonomous-dev): most advanced — adds grill agents, baseline diffing, mandatory Qdrant, multi-repo support

This design incorporates the **generic, high-value** ExiPay improvements only. Payment-platform-specific features (multi-repo per story, device testing gates, mandatory Qdrant) are excluded.

---

## Scope

### New Files

| File | Purpose |
|------|---------|
| `templates/grill-research.md` | Stress-test research findings before planning |
| `templates/grill-plan.md` | Stress-test implementation plan before execution |

### Modified Files

| File | Change |
|------|--------|
| `scripts/orchestrate.sh` | Add RESEARCH-GRILL and PLAN-GRILL steps to pipeline; capture baseline at init |
| `scripts/quality-gate.sh` | Add baseline diffing (read baseline file, distinguish pre-existing vs new failures) |
| `templates/coder.md` | Incorporate ExiPay worker.md improvements |
| `SKILL.md` | Update pipeline diagram to include RESEARCH-GRILL and PLAN-GRILL steps |

### Unchanged

Multi-LLM support (`run_llm()`), hooks system, config system, indexer, stacks, bin/.  
Qdrant stays **optional** — not enforced by hooks.

---

## Detailed Design

### 1. Grill Agents

Grill agents are **informational, not blocking**. They run after researcher/planner, stress-test the output, optionally trigger one targeted rework round, then report findings to the human review gate. The pipeline always continues — the human gate sees the grill report and decides whether to proceed, adjust, or cancel.

**grill-research.md** — disposable agent, spawned after RESEARCH step:
- Reads `research/findings.md` and verifies claims against the actual codebase
- Checks for: missing mandatory sections, claims contradicted by codebase, PRD features not researched, internal contradictions
- Severity levels: CRITICAL / MEDIUM / MINOR
- If ANY critical issues: spawns researcher sub-agent for one targeted rework round (fixes gaps only, keeps adequate sections)
- After rework (or if no critical issues): writes `research/grill-report.md` with verdict
- **Does NOT rework a second time** — remaining issues after one round are reported in the grill report and surfaced at the human gate
- Verdicts: `PASS`, `PASS_WITH_CONCERNS`, `REWORKED`
- Uses `model: "reviewer"` preset via `run_llm()` — works with all configured LLMs (Claude, OpenCode, Gemini, etc.)
- Grill templates are **read-only** — no Write or Edit tool use on source files (only writes grill-report.md)

**grill-plan.md** — disposable agent, spawned after PLANNER step:
- Reads `prd.json` + `research/findings.md` + `wiring-checklist.json`
- Checks for: research constraints not covered by stories, missing integration/wiring stories, dependency cycles, oversized stories (> 45min or > 3 AC), missing delivery/E2E stories
- Same auto-rework logic: one targeted rework round for critical issues, then report
- Writes `plan-grill-report.md` (at state root, alongside `prd.json`)
- Same verdicts, same `model: "reviewer"` dispatch

**Output paths (consistent with ExiPay convention):**
- `{stateDir}/research/grill-report.md` — alongside `findings.md`
- `{stateDir}/plan-grill-report.md` — alongside `prd.json`

**In Autonomous mode:** grill runs silently but logs a visible line when rework is triggered:
```
[autonomous-dev] research-grill: REWORK triggered — respawning researcher (1/1 allowed rounds)
[autonomous-dev] research-grill: complete — verdict: REWORKED (2 critical resolved, 1 remaining)
```

### 2. Updated Pipeline Flow

**Before:**
```
RESEARCH → [Research Review gate] → PLANNER → validate-prd → [Plan Review gate] → PHASES
```

**After:**
```
RESEARCH → RESEARCH-GRILL → [Research Review gate] → PLANNER → validate-prd → PLAN-GRILL → [Plan Review gate] → PHASES
```

In **Supervised Start** mode, the human review gate comes after grill — the developer sees already-stress-tested output plus the grill report.  
In **Autonomous** mode, grill runs with progress logging, re-spawns once if needed, then pipeline continues automatically.

The `orchestrate.sh` step transitions:
```
research → research-grill → research-review → validate-prd-exists → planner → validate-prd → plan-grill → plan-review → preflight → phases
```

Grill metadata (verdict, critical/medium counts) is included in the review gate summary output so developers can see quality signal before deciding to proceed.

### 3. Baseline Diffing in quality-gate.sh

**At pipeline init** (`orchestrate.sh init` step, after project detection):
- Run quality gate in `--baseline-capture` mode
- Capture current test/typecheck/build failure signatures to `.autonomous-dev/baseline-failures.txt`
- **If the project has a completely broken build at capture time:** log a warning and write an empty baseline (`baseline-failures.txt` with count=0), then continue. Do NOT abort the pipeline. Rationale: developers on openclaw may be working in a repo with pre-existing breakage; the pipeline should document this, not refuse to start.
- Log: `Baseline captured: N pre-existing failures (will not block progress)`

**At each gate check:**
```
current_failures = run_gate()
new_failures = current_failures - baseline_failures
if new_failures > 0 → BLOCKED
if only pre-existing failures → WARN (logged) + continue
if baseline-failures.txt missing → treat as empty baseline (all failures are new)
```

**Why this matters for openclaw multi-dev:** Developers working on a feature should never be blocked by someone else's pre-existing broken test. Only regressions they introduced block progress.

### 4. coder.md Improvements

Incorporate from **ExiPay's worker.md**:

- **Convention discovery step** — before writing any code, read 2-3 existing similar files to understand patterns (naming, test structure, mock patterns)
- **Mock cleanup rules** — restore all mocks/spies after each test, no global mock leaks between tests
- **Tighter TDD cycle** — explicit RED (write failing test, verify it fails for the right reason) → GREEN (minimal passing implementation) → REFACTOR (clean up, no behaviour change)
- **No new tooling unless PRD requires it** — do not install new packages or test frameworks unless the story's acceptance criteria explicitly requires a new dependency; use what already exists
- **Test file conventions** — discover and follow existing test file naming, location, and structure before creating new test files

Incorporate from **Priyen's coder.md** (unique additions not in ExiPay):

- **Branch safety check** — run `git branch --show-current` and verify correct branch before every commit; NEVER commit to main
- **Commit early and often discipline** — explicit section: commit after RED (tests written + failing), commit after GREEN (tests passing), commit after each acceptance criterion. Rationale: sessions can end at any time and uncommitted changes are permanently lost
- **Progress tracking** — after completing each story, append a summary to `.autonomous-dev/progress.txt`: story ID, start time, tests written count, commit hash, one-line learning. Gives openclaw developers a running log across all stories
- **Auto-add to anti-patterns.json** — if the coder discovers a new dangerous pattern during implementation, add it to `anti-patterns.json` immediately with pattern, description, severity, and filePattern

### 5. SKILL.md Update

Update the pipeline diagram in SKILL.md to show the two new grill steps:
```
RESEARCH → RESEARCH-GRILL → [Review] → PLANNER → PLAN-GRILL → [Review] → PHASES → FINAL REVIEW → CODE SIMPLIFY → PR → CI MONITOR
```

No other structural changes to SKILL.md.

---

## What We Are NOT Changing

- **Mandatory Qdrant** — stays optional (not every openclaw project has Qdrant running). The grill templates we port will have qdrant-find removed as a mandatory step.
- **Multi-repo per story** — ExiPay-specific, not generic
- **Device testing gates** — ExiPay-specific
- **Multi-LLM support** — already ours, no change needed
- **Hooks system** — already ours, no change needed
- **mr-comment-replies.md** — dropped from scope (no CLI entry point exists to invoke it)

---

## openclaw Multi-Dev Considerations

**Concurrent dev state isolation:**  
State lives in `.autonomous-dev/` inside the project directory. Two developers starting pipelines on the same repo simultaneously will conflict on `state.json`. This is a known limitation. Mitigation: state directory is named per-branch in a future iteration; for now, developers should coordinate pipeline runs per repo (one active pipeline per repo at a time). This limitation is documented in SKILL.md.

---

## Success Criteria

1. Pipeline runs RESEARCH → RESEARCH-GRILL → PLANNER → PLAN-GRILL → PHASES without errors
2. Grill verdicts (PASS / PASS_WITH_CONCERNS / REWORKED) appear correctly in review gate summary
3. Rework sub-agent spawns max 1 time — remaining issues after 1 round are reported, not re-retried
4. Autonomous mode logs a visible line when rework is triggered
5. Baseline failures captured at init; gate correctly distinguishes pre-existing vs new failures
6. Broken build at baseline capture → warning logged, empty baseline written, pipeline continues
7. coder.md improvements don't conflict with existing TDD rules
8. SKILL.md pipeline diagram updated
9. All existing tests pass (no regressions)
10. Grill templates have no mandatory qdrant-find requirement

---

## Out of Scope

- openclaw agent model changes (apex-dev model selection)
- Branch-keyed state isolation (future milestone)
- Any skyner-mono cleanup (separate task)
- mr-comment-replies.md reference doc
