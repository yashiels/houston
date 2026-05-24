---
name: autonomous-dev
description: Autonomous AI-driven software development from PRD to merge-ready PR. Combines research, TDD, multi-phase execution, and supervisor/reviewer patterns. Use when asked to "build autonomously", "implement this PRD", "run autonomous dev", "agentic development", or to build a feature/project without manual intervention.
---

# Autonomous Development (v4) — Engineering Playbook

Execute autonomous development loops: take a PRD, produce working tested code with a merge-ready PR.

> **Repo-level override:** If the target repo has its own CLAUDE.md or .cursor/rules with pipeline instructions, follow those instead of this file.

## Conventions

### Output Format (STRICT)

**You are a dev bot. Output is structured, minimal, machine-readable when possible.**

**FORBIDDEN:**
- Internal monologue: "Now I need to...", "I need to be careful not to...", "Let me continue..."
- Duplicate reporting: Say it once, move on
- Emoji: No ✅ ❌ 🎉 or any emoji
- Filler: "Great!", "Successfully!", "I'll now..."
- Explanations of what you're about to do: Just do it
- Non-English output: ALL output MUST be in English. Never output Chinese, Japanese, or any non-English text. If your internal reasoning drifts to another language, stop and reformulate in English before outputting.

**REQUIRED FORMAT for status updates:**
```
[STEP] <step-name>: <one-line status>
[NEXT] <next-action>
```

**Examples:**
```
✗ BAD:
STORY-016 has completed successfully! The coder agent created the block form screen with all features. The commit hash is 0d869b1.
Now I need to:
Report this to the user
Continue to STORY-017 (next story in PHASE-4)

✓ GOOD:
[DONE] STORY-016: Block form screen — commit 0d869b1
[NEXT] STORY-017: Block management screen
```

**For gate reviews, show only:**
1. Summary (2-3 lines max)
2. Key findings (bullet list, no prose)
3. Required action (single line)

**Silence is golden.** If nothing needs user attention, emit minimal status and continue.

### Commit and PR Format
- **Branch:** `feat/<ticket>-description` or `feat/description`
- **Commits during dev:** free-form (gets squashed on merge)
- **PR title (becomes squash commit):** `feat(scope): description [TICKET-ID]`
- **PR body:** ticket link + co-author trailer
- **Co-author:** `Co-Authored-By: __CO_AUTHOR__`
- **PR command:** `gh pr create --title "feat(scope): description" --reviewer __REVIEWERS__`

## Paths

Pipeline scripts and templates live at a fixed location. Set this based on installation:

```
# If cloned standalone:
PIPELINE_DIR=/path/to/autonomous-dev

# If installed as an OpenClaw skill:
PIPELINE_DIR=~/.openclaw/workspace/skills/autonomous-dev
```

All commands below use `$PIPELINE_DIR/scripts/` and `$PIPELINE_DIR/templates/`. The project directory is separate — `cd` to the project, but run scripts from `$PIPELINE_DIR`.

## Two Usage Modes

### Mode A: CLI (Interactive)
```bash
./ac.sh /path/to/project
```
The CLI provides a TUI that walks through mode selection, model presets, and pipeline execution interactively.

### Mode B: Agent (Programmatic — via run-pipeline.sh)
```bash
# Kick off the entire pipeline with ONE command:
$PIPELINE_DIR/scripts/run-pipeline.sh /path/to/project [--mode autonomous] [--preset balanced]
```
run-pipeline.sh is a bash loop that drives orchestrate.sh next/complete automatically.
It spawns Claude Code for stories, handles timeouts, and notifies via openclaw system event.

**You (the orchestrating agent) do NOT drive the loop. run-pipeline.sh does.**
Your only jobs are:
1. Kick off run-pipeline.sh as a background process
2. Relay notifications to the user in Discord
3. Handle gates (when run-pipeline.sh exits with code 2, relay the prompt and restart after user responds)

## Startup Sequence (Agent Mode)

**You do NOT call orchestrate.sh directly. You call run-pipeline.sh.**

### Worktree Detection (CRITICAL)

The pipeline creates git worktrees to keep the main branch clean. **Always pass the worktree path to run-pipeline.sh, not the main repo.**

```bash
# Check if a worktree exists for this project
WORKTREE=$(jq -r '.project.worktree // empty' /path/to/project/.autonomous-dev/state.json 2>/dev/null)

# If worktree exists, use it. Otherwise use the main repo.
TARGET="${WORKTREE:-/path/to/project}"

# If state.json doesn't have worktree but a sibling directory exists (e.g., project-dev-91/), use that
# Look for: /parent/project-*/  with .autonomous-dev/ inside
```

**When restarting after a gate:** always check for the worktree path again. The worktree may have been created since the last run.

### Kick Off

```bash
# Start pipeline (background) — use worktree path if it exists
exec background:true command:"$PIPELINE_DIR/scripts/run-pipeline.sh $TARGET --mode autonomous --preset balanced"

# Monitor via notifications (openclaw system event arrives automatically)
# Check status manually if needed:
exec command:"$PIPELINE_DIR/scripts/coder-status.sh $TARGET"
```

### Exit Codes

- **0** = Pipeline complete. Report PR URL to user.
- **1** = Fatal error or blocked. Report details to user.
- **2** = Paused for human input. Read `$TARGET/.autonomous-dev/pending-gate.json`, relay the gate prompt to user. After user responds, restart run-pipeline.sh with the SAME target path.

### ⚠️ Session Resume Protocol (CRITICAL — prevents pipeline replay)

**After context compaction, session reset, or any session boundary, you MUST resume — NEVER re-initialize.**

Context compaction destroys your in-memory state. Without this protocol, you will replay the entire pipeline from `init`, causing:
- Hundreds of duplicate `init`/`next`/`complete` calls
- Duplicate story spawns (944 spawns for a single story in observed failure)
- State.json corruption from bulk `complete` calls
- Commits on wrong branch

**Resume sequence (MANDATORY on every session start where state.json exists):**

```bash
# 1. CHECK if pipeline already exists (BEFORE calling init)
if [ -f "$PROJECT_PATH/.autonomous-dev/state.json" ]; then
  # RESUME — do NOT call init
  $PIPELINE_DIR/scripts/orchestrate.sh resume
  $PIPELINE_DIR/scripts/orchestrate.sh verify-state
  # Only proceed if verify-state returns status: ok
  $PIPELINE_DIR/scripts/orchestrate.sh next
else
  # Fresh start — init is appropriate
  $PIPELINE_DIR/scripts/orchestrate.sh init "$PROJECT_PATH"
fi
```

**Rules:**
- **NEVER call `init` if state.json exists.** Init resets the pipeline.
- **NEVER call `complete` more than once per `next` call.** The ratio must be 1:1.
- **NEVER batch multiple `complete` calls to "catch up".** If state seems behind, call `verify-state` first, then `next` once.
- **ALWAYS call `verify-state` before any action after a session boundary.**
- **If `verify-state` returns warnings, STOP and fix state before proceeding.**

### ⚠️ Lossless-Claw Integration (CRITICAL — prevents duplicate processing)

**Use lossless-claw recall tools to track what has already been processed across session boundaries.**

After context compaction, you lose memory of which events/stories you already processed. Without recall tools, you will re-process the same events and spawn duplicate agents.

**Before spawning any agent or executing any story:**

```
1. lcm_grep for the story ID (e.g., "STORY-001")
2. If found in compacted history → it was already processed. Skip.
3. If not found → safe to proceed.
```

**Before calling orchestrate.sh complete:**

```
1. lcm_grep for "complete <step>" to check if you already completed this step
2. If found → do NOT call complete again
3. If not found → safe to call complete
```

**On session resume:**

```
1. Read state.json to get current phase/story
2. lcm_expand_query "what stories have been completed and what is the current pipeline status"
3. Compare recall results with state.json
4. If they disagree → trust state.json + git log, not memory
```

**Gate behavior:**
```
When action is "ask" or "gate": show content to user, WAIT for reply,
  pass their response to: orchestrate.sh complete <step> success <user_response>
  The script REFUSES to advance without the user's response.

When action is "run", "spawn", "check", "summary": execute and complete normally.
```

### State Machine Flow

```
init -> MODE-SELECT -> MODEL-SELECT -> pull-latest -> branch-check -> detect -> baseline
  -> RESEARCH -> RESEARCH-GRILL -> [Research Review] -> validate -> PLANNER -> validate-prd
  -> PLAN-GRILL -> [Plan Review] -> PRE-FLIGHT -> PHASE-1 -> [Phase Review] -> PHASE-2 -> ...
  -> FINAL REVIEW -> PR CREATE -> CI MONITOR -> complete
```

## ⚠️ State Verification (MANDATORY)

**Before ANY pipeline action, you MUST verify state against git history.**

```bash
# Check pipeline state
cat .autonomous-dev/state.json | jq '{currentPhase, step, phases, stories}'

# Check actual git progress
git log --oneline -10

# Check current branch
git branch --show-current
```

**Sanity checks:**
- `state.json.currentPhase` should match phases marked complete + 1
- Last commit should match the last completed story/phase
- Branch should be a feature branch (not main/master/develop)
- If state and git disagree, **trust git** and fix state.json

**If state is out of sync:**
1. Stop and notify user
2. Manually update state.json to match git reality
3. Do NOT proceed until state is verified

## ⚠️ MANDATORY Pre-Flight (NO EXCEPTIONS)

**Before ANY spawn/run action, you orchestration.sh enforces these safety checks automatically:**

### 1. Branch Protection
```
BLOCKED if on: main | master | develop | production
```

The pipeline will **refuse** to execute these steps on protected branches:
- research, research-grill, planner, preflight
- story-execute, story-verify, phase-review
- final-review, simplify, pr-create

**You MUST be on a feature branch.** The pipeline auto-creates a worktree after preset selection.

### 2. Worktree Isolation
All pipeline work happens in a **git worktree** to keep main branch clean.

After mode/preset selection, the pipeline:
1. Creates a worktree at `.worktrees/<timestamp>/`
2. Creates a feature branch: `feat/pipeline-<timestamp>`
3. Updates `state.json` with worktree path
4. All subsequent operations use the worktree

### 3. Gate Token Verification

For `ask` and `gate` actions:
1. A verification token is generated and stored in `state.json .pendingGate.token`
2. The AI **MUST** show the prompt to the user
3. The user's response **MUST** include the token
4. Format: `complete <step> <token>:<user_response>`

**The pipeline will REJECT responses without valid tokens.** This prevents the AI from skipping user input.

## Three Modes

| # | Mode | Description |
|---|------|-------------|
| 1 | Supervised Start | Review research + plan, then autonomous build (default) |
| 2 | Fully Autonomous | Summaries only, no blocking — alert only on BLOCKED |
| 3 | Human Assisted | Pause at research, plan, AND every phase gate |

| Gate | Supervised Start | Autonomous | Human Assisted |
|------|-----------------|------------|----------------|
| Research review | blocks | summary only | blocks |
| Plan review | blocks | summary only | blocks |
| Phase gates | skip | skip | blocks |
| BLOCKED | always stops | always stops | always stops |

## Agent Hierarchy (v4 — Disposable Phase Supervisors)

```
YOU (orchestrator — reads SKILL.md, drives the pipeline via orchestrate.sh)
 |-- RESEARCHER  [one-shot, 30 min]  — audit system -> research/findings.md
 |-- PLANNER  [one-shot, 30 min]  — findings + PRD -> prd.json + wiring-checklist.json
 |-- PHASE SUPERVISOR per phase  [disposable, 2h max, fresh context]
 |     |-- CODER per story  [disposable, dynamic timeout]
 |     \-- (quality gate verified by phase supervisor after each story)
 |-- TESTER per phase  [disposable, 30 min]  — phase review + adds tests
 |-- FINAL REVIEWER  [one-shot, 45 min]  — E2E review
 \-- CI MONITOR  [one-shot, 1h]  — PR + CI fixes + conflicts
```

**Key design:** No persistent supervisor. Each phase gets a fresh phase supervisor that reads state.json + memory files, executes one phase, writes memory, and exits. The orchestrator manages phase progression.

**Benefits:**
- No context exhaustion — fresh context per phase
- 6h+ runs trivially supported — unlimited phases, each with full context budget
- Silent death impossible — orchestrator knows immediately when a phase exits
- Crash recovery = normal operation — restart from state.json + memory files

## Model Presets

Models are selected at pipeline init. Read from `state.json .models.<role>`.

| Preset | researcher | planner | supervisor | coder | tester | reviewer |
|--------|-----------|---------|------------|-------|--------|----------|
| budget | sonnet | sonnet | haiku | sonnet | haiku | sonnet |
| balanced | sonnet | sonnet | sonnet | sonnet | sonnet | sonnet |
| premium | opus | opus | sonnet | opus | sonnet | opus |
| custom | user-specified per role |

Model aliases (`haiku`, `sonnet`, `opus`) are resolved to full model IDs by the invoking agent (see Placeholder Resolution below).

### CLI Dispatch

When spawning agents, dispatch to the correct CLI tool:

```bash
# Claude Code
claude --print "<task>"

# Gemini CLI
gemini --model <model-name> --prompt "<task>"

# OpenCode
opencode --prompt "<task>"
```

## Spawning Agents

When `orchestrate.sh next` returns `"action":"spawn"`, read the model from state.json and dispatch:

```
# Research
Template: $PIPELINE_DIR/templates/researcher.md
Timeout: 30 min

# Research Grill (stress-tests researcher output, optional rework)
Template: $PIPELINE_DIR/templates/grill-research.md
Timeout: 15 min
Model: reviewer

# Planner
Template: $PIPELINE_DIR/templates/planner.md
Timeout: 30 min

# Plan Grill (stress-tests planner output, optional rework)
Template: $PIPELINE_DIR/templates/grill-plan.md
Timeout: 15 min
Model: reviewer

# Phase Supervisor
Template: $PIPELINE_DIR/templates/phase-supervisor.md
Timeout: 2h

# Phase Reviewer/Tester
Template: $PIPELINE_DIR/templates/reviewer.md
Timeout: 30 min

# Final Reviewer
Template: $PIPELINE_DIR/templates/final-review.md
Timeout: 45 min
```

**All agents are disposable.** State persists in files, not sessions.

## Test Requirements (MANDATORY)

Every story MUST include tests. No exceptions. "Skip TDD" was never intended to mean "skip writing tests" — it meant "skip the red-green-refactor ceremony when no test framework exists." If a test framework exists (even a placeholder test file), tests are required.

### Test Tiers

| Tier | What | When | Required |
|------|------|------|----------|
| Unit tests | Pure logic: models, utils, helpers, services (no UI) | Every story that adds/modifies logic | YES |
| Widget tests | UI components: screens, widgets, forms | Every story that adds/modifies UI | YES |
| Integration tests | Cross-feature flows: auth → onboarding → home | Per-phase (phase reviewer adds these) | YES for phase review |

### Unit Test Rules

- Test all model serialization/deserialization (toJson, fromJson, fromFirestore)
- Test all business logic (overlap computation, timezone conversion, recurrence expansion)
- Test all edge cases (null partner, empty blocks, timezone boundary)
- Mock external dependencies (Firebase, Google Calendar API) — never call real services in unit tests
- One test file per source file: `lib/core/models/time_block.dart` → `test/core/models/time_block_test.dart`

### Widget Test Rules

- Test widget renders without errors
- Test user interactions (tap, scroll, form submission)
- Test state changes (loading → loaded → error)
- Use `WidgetTester` and `pumpWidget` with proper providers mocked
- Test accessibility (semantic labels exist for screen readers)

### Integration Test Rules (Phase Reviewer)

- Test complete user flows end-to-end
- Use `integration_test` package for Flutter
- Place in `integration_test/` directory
- Key flows to test:
  - Auth → Onboarding → Home
  - Create block → See on calendar
  - Pair with partner → See partner's blocks
  - Settings change → Reflected in UI

### Test Infrastructure Bootstrap

If the repo has NO test infrastructure beyond a placeholder, the FIRST story in PHASE-1 must set it up:

```bash
# Flutter project test structure
test/
  core/
    models/          # Unit tests for data models
    utils/           # Unit tests for helpers
  features/
    auth/            # Widget tests for auth screens
    home/            # Widget tests for home screens
    blocks/          # Widget tests for block screens
  services/          # Unit tests for services
  helpers/
    test_helpers.dart    # Shared mocks, fixtures, pump helpers
    firebase_mocks.dart  # Firebase mock setup
integration_test/
  app_test.dart      # End-to-end flow tests
```

### CI/CD Workflows (MANDATORY for all autonomous-dev projects)

Every project MUST have GitHub Actions CI. The pipeline should create this during the `preflight` step if it doesn't exist.

**Runner requirement: ALL Skyner Group repos use `[self-hosted, Linux, X64, astra]` — NEVER use `ubuntu-latest`.**

CI workflow template for Flutter projects (`.github/workflows/ci.yml`):

```yaml
name: CI

on:
  pull_request:
    branches: [main, develop]
  push:
    branches: [main, develop]

jobs:
  analyze:
    runs-on: [self-hosted, Linux, X64, astra]
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter analyze --no-fatal-infos

  test:
    runs-on: [self-hosted, Linux, X64, astra]
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter test --coverage
      - name: Check coverage
        run: |
          COVERAGE=$(lcov --summary coverage/lcov.info 2>&1 | grep -oP 'lines\.+: \K[0-9.]+')
          echo "Coverage: ${COVERAGE}%"
          # Fail if coverage drops below threshold
          # python3 -c "exit(0 if float('${COVERAGE}') >= 60 else 1)"

  build:
    runs-on: [self-hosted, Linux, X64, astra]
    needs: [analyze, test]
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter build apk --debug
```

**Non-Flutter projects:** Adapt the workflow to the project's stack (Node.js, Rust, etc.) but always use `[self-hosted, Linux, X64, astra]` as the runner.

## Quality Gates (Three Tiers)

```bash
$PIPELINE_DIR/scripts/quality-gate.sh --scope story   # Per-story: package tests + typecheck + anti-patterns (~30s)
$PIPELINE_DIR/scripts/quality-gate.sh --scope phase   # Per-phase: full suite + build + wiring + reachability (~3-5 min)
$PIPELINE_DIR/scripts/quality-gate.sh --scope final   # Final: everything + Docker + E2E (~10 min)
```

**Baseline diffing:** At pipeline init, `--baseline capture` snapshots pre-existing failures. Workers never chase bugs that existed before they started.

## Handling BLOCKED States

Any BLOCKED signal always stops the pipeline and notifies the user, regardless of mode:

| Signal | Source | Action |
|--------|--------|--------|
| `RESEARCH_BLOCKED` | Researcher | Pipeline stops. Notify user. |
| `PHASE_BLOCKED` | Phase Supervisor | Pipeline stops with phase + story details. |
| `REVIEW_BLOCKED` | Tester | Pipeline stops. Wiring issues found. |
| `E2E_REVIEW_BLOCKED` | Final Reviewer | Pipeline stops. Critical issues. |
| `CI_BLOCKED` | CI Monitor | Pipeline stops. PR needs manual attention. |

## Memory System

> **Multi-dev note:** Pipeline state lives in `.autonomous-dev/` inside the project directory. Two developers running pipelines on the same repo simultaneously will conflict on `state.json`. One active pipeline per repo at a time. Branch-keyed state isolation is planned for a future release.

- `memory/learnings.md` — Cross-phase insights. Phase supervisors read at boot, write before exit.
- `memory/phase-N-summary.md` — Per-phase summaries. Next phase supervisor reads these.
- `research/findings.md` — Researcher output.
- `state.json` — Pipeline state. Updated by orchestrate.sh between phases.

## state.json Schema (v4)

```json
{
  "version": 4,
  "mode": null,
  "preset": null,
  "models": {},
  "currentPhase": "PHASE-2",
  "step": "phase-execute",
  "phases": {
    "PHASE-1": { "status": "complete", "completedAt": "ISO8601" }
  },
  "stories": {
    "STORY-001": { "status": "complete", "completedAt": "ISO8601" }
  },
  "prUrl": "https://github.com/owner/repo/pull/123"
}
```

## PR Creation

After final review passes, orchestrate.sh returns `pr-create`:

**1. Rebase on default branch first:**
```bash
$PIPELINE_DIR/scripts/workflow-guards.sh rebase-default ${projectPath}
# If CONFLICTS returned, alert user - do not proceed
# Note: rebase-develop is an alias (backward compatible)
```

**2. Run pre-push checks:**
```bash
$PIPELINE_DIR/scripts/workflow-guards.sh pre-push ${projectPath}
# If fails, fix issues before pushing
```

**3. Push and create PR:**
```bash
cd ${projectPath}
git push -u origin ${branchName}

PR_URL=$(gh pr create \
  --title "${TYPE}(${SCOPE}): ${TITLE}" \
  --body "$(cat <<PRBODY
## Summary
$(jq -r '.description // ""' prd.json)

## Stories
$(jq -r '.userStories[] | "- [x] \(.id): \(.title)"' prd.json)

## Quality
- All quality gates passing (story + phase + final)
- Wiring checklist verified
- Phase reviews complete
- Final E2E review complete

Co-Authored-By: __CO_AUTHOR__
PRBODY
)" --base develop 2>&1 | grep -oE 'https://github.com/[^ ]+')
```

**4. Enable auto-merge with squash:**
```bash
gh pr merge ${PR_URL##*/} --auto --squash
```
This allows the PR to auto-merge when all checks pass and reviews are approved.

## Enforcement Rules

- `$PIPELINE_DIR/rules/no-shortcuts.md` — mandatory, enforced by hooks
- `$PIPELINE_DIR/rules/breaking-changes.md` — flag before stories are created
- `$PIPELINE_DIR/rules/quality-gates.md` — three-tier gate definitions

## OpenClaw Integration Guide

This section documents how OpenClaw executes the pipeline programmatically.

### Action Types

Orchestrate.sh returns JSON with an `action` field. Handle each type:

- **ask** — Show message to user, WAIT for reply, call `complete <step> success <reply>`
- **gate** — Show content + grill report, WAIT for reply, call `complete <step> success <proceed|adjust:instructions|cancel>`
- **spawn** — Spawn agent, wait for completion, call `complete <step>`
- **run** — Execute commands from worktree, call `complete <step>` or `complete <step> blocked <reason>`
- **progress** — Log message, call `next` again
- **blocked** — Pipeline stopped. Notify user. Do NOT continue.
- **complete** — Pipeline finished. Show PR URL.
- **error** — Something went wrong. Check state.json and notify user.

### Placeholder Resolution (MANDATORY — agents will commit without co-author if skipped)

**Before EVERY spawn, you MUST resolve placeholders. This is not optional.**

If you skip this step, commits will lack Co-Authored-By trailers and use raw `__CO_AUTHOR__` text.

**1. Read config (MUST do this on every session start, not just once):**
```bash
source $PIPELINE_DIR/config.sh
# Provides: AD_LLM_CLI, AD_CO_AUTHOR, AD_REVIEWERS
# AD_CO_AUTHOR="Yashiel Sookdeo <yashiel@skyner.co.za>"
```

**2. Read state.json for model aliases and paths:**
```bash
MODELS=$(jq -r '.models' .autonomous-dev/state.json)
WORKTREE_PATH=$(jq -r '.project.worktree // .project.path' .autonomous-dev/state.json)
```

**3. Resolve model alias to full ID (for Claude Code roles only):**

| Alias | claude --model flag |
|-------|---------------------|
| `haiku` | `claude-haiku-4-5-20251001` |
| `sonnet` | `claude-sonnet-4-6` |
| `opus` | `claude-opus-4-6` |

All roles use Claude Code — resolve the alias from `state.json .models.<role>` for every spawn.

**4. Substitute in template:**
```
__PROJECT_PATH__ → $WORKTREE_PATH (points to worktree)
__ISSUE_DETAILS__ → contents of PRD file or Linear issue
__AD_LLM_CLI__ → $AD_LLM_CLI (e.g., "claude")
__MODEL_RESEARCHER__ → resolved model ID
```

### PRD / Issue Input

The pipeline needs a PRD or issue. Provide it BEFORE `init`:

**Option A: PRD file (recommended)**
```bash
echo "# My Feature\n..." > /path/to/project/prd.md
```

**Option B: Linear issue**
```bash
ISSUE_ID="DEV-123"
ISSUE=$($PIPELINE_DIR/../linear/scripts/linear-wrapper.sh issue "$ISSUE_ID")
# Set __ISSUE_DETAILS__ to issue URL + body
```

**Option C: Inline** — Write user-provided requirements to `prd.md` before init.

### Linear CLI Reference

```bash
# View issue
linear issue view DEV-123

# Search issues
linear issues search --team-key DEV --filter '{"identifier":{"eq":"DEV-123"}}' --json

# List team projects
linear projects --team-key DEV --json
```

### Worktree Isolation

All pipeline work happens in a **git worktree** to keep main branch clean and up-to-date.

**After mode/preset selection, create worktree:**
```bash
cd "$PROJECT_PATH"
BRANCH_NAME="feat/pipeline-$(date +%Y%m%d-%H%M%S)"
WORKTREE_PATH="../$(basename $(pwd))-${BRANCH_NAME#feat/}"

git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME"

# Update state.json
jq --arg wt "$WORKTREE_PATH" --arg br "$BRANCH_NAME" \
  '.project.worktree = $wt | .project.branch = $br' \
  .autonomous-dev/state.json > /tmp/state.json && mv /tmp/state.json .autonomous-dev/state.json
```

**All subsequent operations use `$WORKTREE_PATH`**, not the original directory.

**After PR merge:**
```bash
git worktree remove "$WORKTREE_PATH"
git branch -d "$BRANCH_NAME"
```

### Pre-Spawn Checklist (HARD GATE — do not spawn without completing all items)

Before EVERY agent spawn, verify ALL of these. If any fails, STOP and fix before spawning:

```
[ ] 1. state.json exists and is valid JSON
[ ] 2. orchestrate.sh next returned action:"spawn" (not stale from previous session)
[ ] 3. Current branch is a feature branch (NOT main/master/develop)
[ ] 4. git log confirms last completed story matches state.json
[ ] 5. config.sh sourced — AD_CO_AUTHOR is resolved (not __CO_AUTHOR__)
[ ] 6. Template placeholders resolved (__PROJECT_PATH__, __CO_AUTHOR__, __BRANCH_NAME__)
[ ] 7. lcm_grep confirms this story was NOT already spawned in compacted history
[ ] 8. This is the ONLY spawn for this step (no duplicate spawns)
```

If you cannot verify item 7 (lossless-claw not available), verify via git log instead:
```bash
git log --oneline | grep -q "STORY-XXX" && echo "ALREADY DONE" || echo "SAFE TO SPAWN"
```

### Agent Spawning — Via Helper Scripts (Pipeline-Integrated)

**⚠️ CRITICAL: NEVER use `runtime: "acp"` for pipeline agents.** ACP causes `Permission denied`.
**⚠️ CRITICAL: NEVER use `sessions_spawn` for pipeline agents.** Subagents inherit your model and can't use Claude Code tools.
**⚠️ CRITICAL: NEVER construct `claude --print` commands yourself.** Use the helper scripts below — they handle prompt construction, co-author enforcement, and completion notifications.

#### The Pipeline Loop (MANDATORY — this is the entire flow)

```
orchestrate.sh resume                          # (1) Resume pipeline
orchestrate.sh verify-state                    # (2) Verify state matches git
orchestrate.sh next                            # (3) Get next action
  → action:"spawn", step:"story-execute", story:"STORY-XXX"
spawn-coder.sh STORY-XXX $PROJECT_PATH         # (4) Spawn Claude Code (background:true)
  ... wait for completion (auto-notifies via openclaw system event) ...
coder-status.sh $PROJECT_PATH                  # (5) Verify commit landed
orchestrate.sh complete story-execute success   # (6) Mark step done
orchestrate.sh next                            # (7) Get next action
  → action:"run", step:"story-verify"
  ... run verify commands from the action ...
orchestrate.sh complete story-verify success    # (8) Mark verify done
orchestrate.sh next                            # (9) Next story or phase-review
  → repeat from (4)
```

**Rules:**
- ALWAYS use `orchestrate.sh next` to get the action — never decide yourself
- ALWAYS use `spawn-coder.sh` to spawn coders — never construct claude commands
- ALWAYS call `orchestrate.sh complete` after each step — exactly once per `next`
- ALWAYS use `coder-status.sh` to verify before completing

#### spawn-coder.sh — Spawn Claude Code for a Story

```bash
# Usage: background:true is REQUIRED
exec background:true command:"$PIPELINE_DIR/scripts/spawn-coder.sh STORY-XXX $PROJECT_PATH [MODEL]"
```

What it does:
1. Reads story from `prd.json`
2. Constructs prompt with acceptance criteria
3. Enforces Co-Authored-By from `config.sh`
4. Runs `claude --model claude-sonnet-4-6 --permission-mode bypassPermissions --print`
5. On completion, fires `openclaw system event` to wake you up
6. Reports STORY_COMPLETE or STORY_BLOCKED

Optional MODEL arg: `claude-sonnet-4-6` (default), `claude-opus-4-6`, `claude-haiku-4-5-20251001`

#### coder-status.sh — Check Running Coders

```bash
exec command:"$PIPELINE_DIR/scripts/coder-status.sh $PROJECT_PATH"
```

Returns: running/idle status, PIDs, recent commits, uncommitted changes, test file count.

#### For Non-Story Spawns (researcher, planner, reviewer)

These roles also use Claude Code but with template files instead of prd.json stories:

```bash
# Read the template, resolve placeholders, then:
exec background:true command:"claude --model $MODEL_ID --permission-mode bypassPermissions --print '$RESOLVED_PROMPT'"
```

Templates live at `$PIPELINE_DIR/templates/`. Resolve placeholders (`__PROJECT_PATH__`, `__CO_AUTHOR__`, etc.) before spawning.

**After ANY agent completes, call complete:**

```bash
orchestrate.sh complete <step> success
# or if blocked:
orchestrate.sh complete <step> blocked <reason>
```

**If you forget `complete`, the pipeline stalls forever.**

### Gate Handling

For `action: "gate"`:

1. Show content (files from `grillReport` field)
2. Show summary (`data` object: wiring count, constraints, verdict)
3. **WAIT for user reply** — Do NOT proceed until user responds
4. Parse response:
   - "proceed" / "continue" → `complete <step> success proceed`
   - "adjust: <instructions>" → `complete <step> success adjust:<instructions>`
   - "cancel" / "stop" → `complete <step> success cancel`

### Run Action Handling

For `action: "run"`:

1. Execute each command in `commands` array (from worktree)
2. Check exit codes:
   - All succeed → `complete <step> success`
   - Any fails → `complete <step> blocked <reason>`

### Error Handling

```
spawn returns BLOCKED?
  → notify user, call complete <step> blocked <reason>

spawn times out?
  → kill process, call complete <step> blocked agent_timeout

quality gate fails?
  → check baseline (pre-existing)
  → if baseline: ignore, call complete success
  → if new: call complete <step> blocked gate_failed:<details>

user cancels at gate?
  → call complete <step> success cancel
```

### Config File

`config.sh` should contain:

```bash
# LLM CLI to use (must be in PATH)
AD_LLM_CLI="claude"

# Co-author for all commits (never use AI co-author)
AD_CO_AUTHOR="Your Name <email@example.com>"

# PR reviewers (comma-separated GitHub usernames)
AD_REVIEWERS="user1,user2"

# GitHub Actions runner label (Skyner Group uses self-hosted astra)
AD_RUNNER_LABEL='[self-hosted, Linux, X64, astra]'
```

**Note:** Mode and preset are NOT configured here. The pipeline always asks the user to select mode and preset at startup via `ask` actions.

**Runner requirement:** ALL Skyner Group repositories MUST use `[self-hosted, Linux, X64, astra]` as the GitHub Actions runner. NEVER use `ubuntu-latest` or any GitHub-hosted runner. This applies to all CI/CD workflows created by the pipeline.

## Workflow Guards

Safety guards for the development workflow. Located at `scripts/workflow-guards.sh`.

### Verify Pipeline State (MANDATORY before any action)
```bash
$PIPELINE_DIR/scripts/orchestrate.sh verify-state
```
- Compares `state.json` to git history
- Checks if branch is correct (should be feature branch, not main)
- Detects phase mismatches
- Returns `status: ok` or `status: warning` with details
- **Run this before ANY pipeline action**

### Pre-Push Checks (Run tests before push)
```bash
$PIPELINE_DIR/scripts/workflow-guards.sh pre-push /path/to/worktree
```
- Detects project type (Node.js, Flutter, Rust)
- Runs lint, typecheck, and tests
- Fails fast if any check fails

### Worktree State Check
```bash
$PIPELINE_DIR/scripts/workflow-guards.sh worktree-check /path/to/worktree
# Returns: NOT_EXISTS | CLEAN | DIRTY
```

### Get Default Branch (detect from remote)
```bash
$PIPELINE_DIR/scripts/workflow-guards.sh get-default-branch /path/to/worktree
```
- Detects default branch via gh CLI, git symref, or remote show
- Falls back to main/master if detection fails
- Use before rebase to know the target branch

### Rebase on Default Branch (before PR)
```bash
$PIPELINE_DIR/scripts/workflow-guards.sh rebase-default /path/to/worktree
# Alias: rebase-develop (backward compatible)
```
- Detects default branch automatically (production, main, master, etc)
- Cleans .next artifacts to avoid conflicts
- Fetches and rebases on detected default
- Returns CONFLICTS if merge conflicts detected

### Linear API with Retry
```bash
$PIPELINE_DIR/scripts/workflow-guards.sh linear-retry "issue DEV-123"
```
- Retries 3x with exponential backoff
- Returns DEGRADED if all retries fail

### Validate Requirements Clarity
```bash
$PIPELINE_DIR/scripts/workflow-guards.sh validate-requirements DEV-123
# Returns: CLEAR:85:Title | UNCERTAIN:65:Title | UNCLEAR:40:Title
```

### CI Status Check
```bash
$PIPELINE_DIR/scripts/workflow-guards.sh ci-status 123 /path/to/repo
# Returns: PASSED | PENDING | FAILED:details | UNKNOWN:details
```

### Review Status Check
```bash
$PIPELINE_DIR/scripts/workflow-guards.sh review-status 123 /path/to/repo
```

## Reference Files

| File | Purpose |
|------|---------|
| `scripts/workflow-guards.sh` | Safety guards (pre-push, rebase, CI checks) |
| `templates/researcher.md` | System audit -> research/findings.md |
| `templates/grill-research.md` | Stress-test researcher output -> research/grill-report.md |
| `templates/planner.md` | Findings + PRD -> prd.json + wiring-checklist.json |
| `templates/grill-plan.md` | Stress-test planner output -> plan-grill-report.md |
| `templates/phase-supervisor.md` | Execute ONE phase -> memory + state update |
| `templates/coder.md` | TDD story implementation |
| `templates/reviewer.md` | Phase review + adds tests |
| `templates/final-review.md` | Final E2E review |
| `templates/code-simplify.md` | Code simplification pass |
| `scripts/orchestrate.sh` | Pipeline state machine (the brain) |
| `scripts/quality-gate.sh` | 11-check quality gate (3 tiers + baseline) |
| `scripts/anti-pattern-scan.sh` | Scan for known dangerous patterns |
| `scripts/wiring-check.sh` | Verify wiring-checklist.json items |
| `scripts/reachability-check.sh` | Find test-only exports |
| `scripts/detect-project.sh` | Auto-detect project structure |
| `scripts/validate-prd.sh` | Validate prd.json schema |
| `scripts/resume.sh` | Resume from state.json checkpoint |
| `references/methodology.md` | Background theory |
| `references/quick-commands.md` | Copy-paste commands |
