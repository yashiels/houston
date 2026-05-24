# ExiPay Selective Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge ExiPay's grill agents, grill-aware review gates, and coder improvements into the canonical autonomous-dev repo for openclaw multi-dev use.

**Architecture:** Two new disposable agent templates (grill-research, grill-plan) are inserted into the pipeline after RESEARCH and after PLAN respectively. They stress-test outputs and optionally trigger one targeted rework round. The pipeline always continues — grill findings are surfaced to human review gates. orchestrate.sh step transitions and spawn instructions are updated to wire in the new steps. SKILL.md is updated to document the new pipeline shape.

**Tech Stack:** Bash, jq, Markdown templates

**Note on scope:** After reading the source files, `quality-gate.sh` already has full baseline diffing implemented (lines 343–377 + capture mode lines 56–84). `coder.md` already has all planned improvements (branch safety, commit discipline, progress tracking, anti-pattern auto-add). These two files require **no changes** — the work is already done.

---

## File Map

| Action | File | What changes |
|--------|------|-------------|
| Create | `templates/grill-research.md` | New disposable agent template |
| Create | `templates/grill-plan.md` | New disposable agent template |
| Modify | `scripts/orchestrate.sh` | Add grill step transitions + spawn cases + gate metadata |
| Modify | `SKILL.md` | Update pipeline diagram + reference table + spawning section |

---

### Task 1: Create grill-research.md

**Files:**
- Create: `templates/grill-research.md`

- [ ] **Step 1: Write the template**

Create `/Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/templates/grill-research.md` with this exact content:

```markdown
# Autonomous Dev Research Grill

You are a one-shot grill agent. Your job: stress-test the researcher's findings BEFORE
the human review gate. Verify claims against the actual codebase, find gaps, and
optionally trigger rework.

**Project:** __PROJECT_PATH__
**PRD:** __ISSUE_DETAILS__
**Findings:** research/findings.md

## Why You Exist

> "Research findings that nobody questioned led to plans built on wrong assumptions."

The researcher reads existing code and produces findings.md. But researchers can miss things,
make shallow claims without evidence, or skip mandatory sections. You catch this before a human
has to.

## Process

```bash
cd __PROJECT_PATH__

# 1. Read the inputs
cat __ISSUE_DETAILS__ 2>/dev/null || true
cat research/findings.md
```

Use Grep, Glob, and Read to verify claims against the actual codebase.

## Grill Checklist

For each mandatory section in findings.md, run three checks:

### 1. Existence & Substance Check

Verify each section exists and has real content (not just headers or "N/A"):

| Section | Required Content |
|---------|-----------------|
| Prior Attempts | MR/PR list or explicit "None found" |
| Deployment Path | Runtime, mechanism, full path trace, gaps |
| Integration Points | At least one system with interface details |
| Conflicts & Exclusivity | Explicit check (even if "none found") |
| Open Questions Resolved | Each Q with A and evidence |
| Delivery Verification | Component traced from repo to runtime |
| Wiring Points | At least one entry point with file path and line |
| Constraints for Planner | Actionable items (not vague) |
| Risks | At least one risk assessed (even if low) |

**Severity:** Missing or empty mandatory section = **CRITICAL**

### 2. Evidence Check

For each claim in findings.md that references a file, class, or interface:
- Use Grep or Read to verify the referenced entity exists
- If findings say "deploys via Docker" → verify Dockerfile exists
- If findings say "integrates with ServiceX via REST" → verify the REST client/endpoint
- If findings say "config key Y controls Z" → verify Y appears in config files

**Severity:**
- Claim contradicted by codebase = **CRITICAL**
- Claim without any file path evidence = **MEDIUM**

### 3. Contradiction Check

Read all sections together and look for:
- Deployment path says Docker but delivery verification says npm publish
- Integration points say system A is REST but wiring points reference gRPC imports
- Cross-repo impact says "only one repo" but wiring points reference files in other repos

**Severity:** Internal contradiction = **CRITICAL**

### 4. Completeness Check

Compare findings against the PRD:
- Every system/feature mentioned in the PRD should appear in integration points
- Every "open question" or "TBD" in the PRD should be resolved in findings
- Every wiring point mentioned should have a file path and line reference

**Severity:**
- PRD feature completely missing from findings = **CRITICAL**
- PRD feature mentioned but shallowly covered = **MEDIUM**

## Severity Classification

| Severity | Definition | Action |
|----------|-----------|--------|
| **CRITICAL** | Missing mandatory section, codebase contradicts claim, PRD feature not researched | Auto-rework |
| **MEDIUM** | Shallow analysis, claims without file evidence, missing risk mitigation | Report only |
| **MINOR** | Style issues, verbose but correct, low-value risks without mitigation | Report only |

## Auto-Rework (Max 1 Round)

If ANY critical issues found:

1. Compile critical gaps into a focused list
2. Spawn a researcher sub-agent (using the Agent tool) with this prompt:

```
You are a researcher doing a TARGETED rework. Read the original findings and fix ONLY the
critical gaps listed below. Do not rewrite sections that are already adequate.

Project: __PROJECT_PATH__
PRD: __ISSUE_DETAILS__
Original findings: research/findings.md

CRITICAL GAPS TO FIX:
<list your critical findings here>

Rewrite research/findings.md with the gaps addressed. Keep all adequate sections intact.
Output: RESEARCH_COMPLETE when done.
```

3. After rework, re-evaluate the rewritten findings against the same checklist
4. **Do NOT rework a second time** — report remaining issues in the grill report and let the human gate decide

## Output

Write `research/grill-report.md`:

```markdown
# Research Grill Report

## Verdict: <PASS | PASS_WITH_CONCERNS | REWORKED>

## Rework Summary
<!-- Only if verdict is REWORKED -->
- Critical gaps found: <count>
- Gaps resolved after rework: <list>
- Gaps remaining after rework: <list>

## Critical Issues
<!-- Empty if PASS -->
- [Section]: [issue] — [evidence from codebase]

## Medium Issues
- [Section]: [issue] — [suggestion]

## Minor Issues
- [Section]: [issue]

## Verified Claims
- [Claim from findings]: verified via [file:line or grep output]

## Unverifiable Claims
- [Claim]: could not verify because [reason]

## Interactive Grill Suggestions
<!-- Questions the automated grill could not resolve — strategic/intent questions for the user -->
- [Question 1] (Recommended: [your suggestion])
- [Question 2] (Recommended: [your suggestion])
```

## Completion

```
GRILL_RESEARCH_COMPLETE
Verdict: <PASS|PASS_WITH_CONCERNS|REWORKED>
Critical: <count>
Medium: <count>
Minor: <count>
Interactive questions: <count>
Report: research/grill-report.md
```

Or if the findings file is missing or unreadable:

```
GRILL_RESEARCH_BLOCKED: findings.md missing or empty
```

## Rules

- Read ACTUAL CODE to verify claims — do not trust findings at face value
- Every verification must include evidence (file path, grep output)
- Do NOT implement any code
- Do NOT modify the PRD
- Do NOT skip the rework step if critical issues are found
- `mkdir -p research` before writing grill-report.md
- Do NOT reference ticket numbers in code comments
```

- [ ] **Step 2: Verify the file was created**

```bash
ls -la /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/templates/grill-research.md
grep "GRILL_RESEARCH_COMPLETE" /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/templates/grill-research.md
grep "Max 1 Round" /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/templates/grill-research.md
grep "qdrant" /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/templates/grill-research.md
```

Expected: file exists, GRILL_RESEARCH_COMPLETE found, "Max 1 Round" found, **no qdrant references**

- [ ] **Step 3: Commit**

```bash
cd /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev
git add templates/grill-research.md
git commit -m "feat: add grill-research template for stress-testing researcher output"
```

---

### Task 2: Create grill-plan.md

**Files:**
- Create: `templates/grill-plan.md`

- [ ] **Step 1: Write the template**

Create `/Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/templates/grill-plan.md` with this exact content:

```markdown
# Autonomous Dev Plan Grill

You are a one-shot grill agent. Your job: stress-test the planner's output BEFORE
the human review gate. Verify the plan covers all research constraints, has proper
integration stories, correct sizing, and valid dependencies.

**Project:** __PROJECT_PATH__
**PRD JSON:** prd.json
**Findings:** research/findings.md
**Wiring Checklist:** wiring-checklist.json (if present)

## Why You Exist

> "Plans that pass validation but miss integration stories produce code that compiles but doesn't connect."

The planner converts research into stories. But planners can miss constraints, create oversized stories,
forget integration wiring, or leave cross-repo gaps. You catch this before a human has to.

## Process

```bash
cd __PROJECT_PATH__

# 1. Read the inputs
cat prd.json
cat research/findings.md
cat wiring-checklist.json 2>/dev/null || echo "No wiring checklist"
```

## Grill Checklist

### 1. Research Constraint Coverage

Read the "Constraints for Planner" section from findings.md. For each constraint:
- Find the story in prd.json that addresses it
- If no story addresses a MUST constraint → **CRITICAL**
- If no story addresses a SHOULD constraint → **MEDIUM**

Build a coverage table:

| Research Constraint | Story ID | Status |
|--------------------|----|--------|
| Must include delivery story | STORY-00N | covered/missing |

### 2. Integration Story Audit

Find all sets of parallel stories (same phase, no dependency between them) that produce
components which must work together:

- Stories in the same phase that modify related files or the same module
- Stories that produce UI components + API endpoints that must connect
- Stories where one produces a type/interface another consumes

For each parallel set: verify an integration/wiring story exists with `dependsOn` referencing
all pieces.

**Severity:** Missing integration story for parallel work = **CRITICAL**

### 3. Consolidation Story Check

Read research findings for mentions of:
- "currently goes through ClassA" where the plan bypasses ClassA
- "dual send risk" or "dedup needed"
- Responsibility moving from one class to another

For each: verify a consolidation story exists to clean up the old path.

**Severity:** Bypassed class with no consolidation story = **MEDIUM**

### 4. Story Sizing Validation

For each story in prd.json, check:
- `estimatedMinutes` is between 20 and 45
- `acceptanceCriteria` has 1-3 items (not more)
- Description doesn't imply more than 3-4 files modified

**Severity:**
- Story > 45 min or > 3 AC = **MEDIUM**
- Story > 60 min or > 5 AC = **CRITICAL** (will exhaust agent context)

### 5. Dependency Graph Validation

```bash
# Extract dependency graph from prd.json
jq '.userStories[] | {id, phase, dependsOn}' prd.json
```

Check:
- No circular dependencies (A depends on B depends on A)
- Cross-phase dependencies are sequential (story in PHASE-2 can depend on PHASE-1, not reverse)
- All `dependsOn` references point to valid story IDs

**Severity:** Circular dependency or invalid reference = **CRITICAL**

### 6. Delivery & E2E Stories

Verify:
- A delivery story exists (references deployment path from research)
- An E2E validation story exists in the final phase
- E2E story references wiring-checklist.json verification

**Severity:** Missing delivery or E2E story = **CRITICAL**

### 7. Wiring Checklist Mapping

For each item in wiring-checklist.json (if present):
- Find at least one story whose scope (files, description) would produce that wiring
- If no story covers a wiring item → **MEDIUM**

### 8. External System Contracts

For stories that interact with external systems:
- Acceptance criteria must include expected schema or interface contract
- A contract test criterion should exist

**Severity:** External system story without schema in AC = **MEDIUM**

## Severity Classification

| Severity | Definition | Action |
|----------|-----------|--------|
| **CRITICAL** | Missing delivery/E2E story, dependency cycle, research constraint uncovered, story will exhaust context | Auto-rework |
| **MEDIUM** | Oversized story, missing integration story, wiring item unmapped, no contract test | Report only |
| **MINOR** | Low estimates, vague descriptions with clear AC, minor naming issues | Report only |

## Auto-Rework (Max 1 Round)

If ANY critical issues found:

1. Compile critical gaps into a focused list
2. Spawn a planner sub-agent (using the Agent tool) with this prompt:

```
You are a planner doing a TARGETED rework. Read the existing prd.json and fix ONLY the
critical gaps listed below. Do not rewrite stories that are already adequate.

Project: __PROJECT_PATH__
Existing prd.json: prd.json
Research findings: research/findings.md

CRITICAL GAPS TO FIX:
<list your critical findings here>

Update prd.json with the gaps addressed. Keep all adequate stories intact.
Run ./scripts/validate-prd.sh prd.json to verify.
Output: PLANNER_COMPLETE when done.
```

3. After rework, re-evaluate the updated prd.json against the same checklist
4. **Do NOT rework a second time** — report remaining issues in the grill report and let the human gate decide

## Output

Write `plan-grill-report.md` (at project root, alongside prd.json):

```markdown
# Plan Grill Report

## Verdict: <PASS | PASS_WITH_CONCERNS | REWORKED>

## Rework Summary
<!-- Only if verdict is REWORKED -->
- Critical gaps found: <count>
- Gaps resolved after rework: <list>
- Gaps remaining after rework: <list>

## Constraint Coverage
| Research Constraint | Story | Status |
|--------------------|----|--------|
| [constraint] | STORY-00N | covered/missing |

## Integration Story Audit
| Parallel Stories | Integration Story | Status |
|-----------------|-------------------|--------|
| STORY-X, STORY-Y | STORY-Z | covered/missing |

## Sizing Issues
- STORY-00N: [issue]

## Dependency Graph Issues
<!-- empty if clean -->

## Wiring Checklist Coverage
| Wiring Item | Story | Status |
|------------|-------|--------|
| [item] | STORY-00N | covered/missing |

## Interactive Grill Suggestions
- [Question 1] (Recommended: [your suggestion])
- [Question 2] (Recommended: [your suggestion])
```

## Completion

```
GRILL_PLAN_COMPLETE
Verdict: <PASS|PASS_WITH_CONCERNS|REWORKED>
Critical: <count>
Medium: <count>
Minor: <count>
Interactive questions: <count>
Report: plan-grill-report.md
```

Or if prd.json is missing:

```
GRILL_PLAN_BLOCKED: prd.json missing
```

## Rules

- Read prd.json and findings.md thoroughly — do not skim
- Every finding must include evidence (story ID, constraint text, file reference)
- Do NOT implement any code
- Do NOT modify research/findings.md
- Do NOT skip rework if critical issues are found
- Do NOT reference ticket numbers in code comments
```

- [ ] **Step 2: Verify the file was created**

```bash
ls -la /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/templates/grill-plan.md
grep "GRILL_PLAN_COMPLETE" /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/templates/grill-plan.md
grep "Max 1 Round" /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/templates/grill-plan.md
grep "qdrant" /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/templates/grill-plan.md
```

Expected: file exists, GRILL_PLAN_COMPLETE found, "Max 1 Round" found, **no qdrant references**

- [ ] **Step 3: Commit**

```bash
cd /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev
git add templates/grill-plan.md
git commit -m "feat: add grill-plan template for stress-testing planner output"
```

---

### Task 3: Update orchestrate.sh — step transitions

The COMPLETE case block controls which step follows each completed step. We need to insert grill steps between `research→review` and `validate-prd→plan-review`.

**Files:**
- Modify: `scripts/orchestrate.sh`

**Current COMPLETE case (relevant lines):**
```bash
research)      json_set '.step = "research-review"' ;;
planner)       json_set '.step = "validate-prd"' ;;
```

**Current NEXT loop (validate-prd section):**
```bash
validate-prd)
  ...
  advance "validate-prd" "plan-review"
  ...
  advance "validate-prd" "plan-review"
```

- [ ] **Step 1: Change `research` transition to go to `research-grill`**

In `scripts/orchestrate.sh`, find and replace:
```bash
    research)      json_set '.step = "research-review"' ;;
```
with:
```bash
    research)      json_set '.step = "research-grill"' ;;
    research-grill) json_set '.step = "research-review"' ;;
```

- [ ] **Step 2: Add `plan-grill` transition after `plan-grill` completes**

In the COMPLETE case block, find:
```bash
    plan-review)
```
and add the following line immediately before it:
```bash
    plan-grill)    json_set '.step = "plan-review"' ;;
```

- [ ] **Step 3: Change `validate-prd` advance target from `plan-review` to `plan-grill`**

In the `validate-prd)` case inside the NEXT auto-advance loop, replace both occurrences of:
```bash
          advance "validate-prd" "plan-review"
```
with:
```bash
          advance "validate-prd" "plan-grill"
```

- [ ] **Step 4: Fix COMPLETE case `validate-prd` to also point to `plan-grill`**

In the COMPLETE case block, under the "Auto-executed steps" comment, find:
```bash
    validate-prd)        json_set '.step = "plan-review"' ;;
```

Replace with:
```bash
    validate-prd)        json_set '.step = "plan-grill"' ;;
```

- [ ] **Step 5: Add `plan-grill-report.md` to the gitignore entries in `init`**

In the `init` section of orchestrate.sh, find:
```bash
  GITIGNORE_ENTRIES=(
    "${AD_STATE_DIR}/"
    "prd.json"
    "research/"
    "progress.txt"
  )
```

Replace with:
```bash
  GITIGNORE_ENTRIES=(
    "${AD_STATE_DIR}/"
    "prd.json"
    "research/"
    "progress.txt"
    "plan-grill-report.md"
  )
```

- [ ] **Step 6: Verify transitions with a dry run**

```bash
cd /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev
mkdir -p /tmp/grill-test-proj && cd /tmp/grill-test-proj
git init -q && echo '{}' > package.json

# Initialize pipeline
AD_STATE_DIR=".autonomous-dev" /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/scripts/orchestrate.sh init /tmp/grill-test-proj

# Simulate completing research — should now go to research-grill
/Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/scripts/orchestrate.sh complete research

# Verify step is now research-grill
jq '.step' .autonomous-dev/state.json
```

Expected output: `"research-grill"`

- [ ] **Step 5: Verify plan-grill transition**

```bash
cd /tmp/grill-test-proj

# Skip ahead to validate-prd step
jq '.step = "validate-prd"' .autonomous-dev/state.json > /tmp/s.json && mv /tmp/s.json .autonomous-dev/state.json

# Create a minimal prd.json so validate-prd passes
cat > prd.json << 'EOF'
{"name":"test","phases":[{"id":"PHASE-1","name":"Test","stories":["STORY-001"]}],"userStories":[{"id":"STORY-001","title":"Test","phase":"PHASE-1","acceptanceCriteria":["It works"],"estimatedMinutes":30}]}
EOF

# Run next — validate-prd should auto-advance to plan-grill
/Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/scripts/orchestrate.sh next | jq '.action,.step // .autoAdvanced'
```

Expected: action is `spawn` with step `plan-grill` (after auto-advancing through validate-prd)

- [ ] **Step 6: Clean up test dir**

```bash
rm -rf /tmp/grill-test-proj
```

- [ ] **Step 7: Commit**

```bash
cd /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev
git add scripts/orchestrate.sh
git commit -m "feat: insert research-grill and plan-grill steps into pipeline transitions"
```

---

### Task 4: Update orchestrate.sh — spawn cases for grill steps

Add the `research-grill` and `plan-grill` cases to the NEXT loop's spawn section, and add grill metadata to the review gate outputs.

**Files:**
- Modify: `scripts/orchestrate.sh`

- [ ] **Step 1: Add `research-grill` spawn case to the NEXT loop**

In the NEXT loop, find the `research)` spawn case:
```bash
      research)
        emit_progress_before_spawn "research" "Spawning researcher (codebase audit)" "~5-15 min"
        emit "spawn" "\"step\":\"research\",\"template\":\"templates/researcher.md\",\"model\":\"researcher\",\"timeout\":1800,\"invocation\":{\"tool\":\"__AD_LLM_CLI__\",\"model\":\"__MODEL_RESEARCHER__\",\"prompt_template\":\"templates/researcher.md\"},\"onComplete\":\"complete research\",\"onBlocked\":\"complete research blocked <reason>\""
        exit 0
        ;;
```

Insert the following **after** the `research)` case (before `planner)`):
```bash
      research-grill)
        if [ ! -f "research/findings.md" ]; then
          emit_blocked "research-grill" "research/findings.md missing — run research step first"
        fi
        emit_progress_before_spawn "research-grill" "Grilling research findings (stress-test)" "~5-10 min"
        emit "spawn" "\"step\":\"research-grill\",\"template\":\"templates/grill-research.md\",\"model\":\"reviewer\",\"timeout\":900,\"invocation\":{\"tool\":\"__AD_LLM_CLI__\",\"model\":\"__MODEL_REVIEWER__\",\"prompt_template\":\"templates/grill-research.md\"},\"onComplete\":\"complete research-grill\",\"onBlocked\":\"complete research-grill blocked <reason>\""
        exit 0
        ;;
```

- [ ] **Step 2: Add `plan-grill` spawn case to the NEXT loop**

Find the `planner)` spawn case. Insert the following **after** the `planner)` case (before `preflight)`):
```bash
      plan-grill)
        if [ ! -f "prd.json" ]; then
          emit_blocked "plan-grill" "prd.json missing — run planner step first"
        fi
        GRILL_WIRING=""
        [ -f "wiring-checklist.json" ] && GRILL_WIRING=",\"wiringChecklist\":\"wiring-checklist.json\""
        emit_progress_before_spawn "plan-grill" "Grilling implementation plan (stress-test)" "~5-10 min"
        emit "spawn" "\"step\":\"plan-grill\",\"template\":\"templates/grill-plan.md\",\"model\":\"reviewer\",\"timeout\":900${GRILL_WIRING},\"invocation\":{\"tool\":\"__AD_LLM_CLI__\",\"model\":\"__MODEL_REVIEWER__\",\"prompt_template\":\"templates/grill-plan.md\"},\"onComplete\":\"complete plan-grill\",\"onBlocked\":\"complete plan-grill blocked <reason>\""
        exit 0
        ;;
```

- [ ] **Step 3: Add grill metadata to the `research-review` gate**

Find the `research-review)` case in the NEXT loop:
```bash
      research-review)
        if [ "$MODE" = "autonomous" ]; then
          advance "research-review" "validate-prd-exists"
        else
          if [ ! -f "research/findings.md" ]; then
            emit_blocked "research-review" "research/findings.md missing"
          fi
          WIRING=$(grep -c "must import\|must extend\|must include\|must add" research/findings.md 2>/dev/null; true)
          CONSTRAINTS=$(grep -c "MUST\|MUST NOT" research/findings.md 2>/dev/null || echo "0")
          emit "gate" "\"step\":\"research-review\",\"data\":{\"wiring\":$WIRING,\"constraints\":$CONSTRAINTS},\"message\":\"Show research/findings.md to user. WAIT for reply. Then: complete research-review success <proceed|adjust:instructions|cancel>\""
          exit 0
        fi
        ;;
```

Replace it with:
```bash
      research-review)
        GRILL_VERDICT="none"
        GRILL_CRITICAL=0
        GRILL_MEDIUM=0
        if [ -f "research/grill-report.md" ]; then
          GRILL_VERDICT=$(sed -n 's/^## Verdict: //p' "research/grill-report.md" 2>/dev/null || echo "unknown")
          GRILL_CRITICAL=$({ sed -n '/## Critical Issues/,/^##/p' "research/grill-report.md" 2>/dev/null | grep -c '^\- ' || true; })
          GRILL_MEDIUM=$({ sed -n '/## Medium Issues/,/^##/p' "research/grill-report.md" 2>/dev/null | grep -c '^\- ' || true; })
        fi
        if [ "$MODE" = "autonomous" ]; then
          log_step "research-review" "grill verdict: $GRILL_VERDICT (critical: $GRILL_CRITICAL, medium: $GRILL_MEDIUM)"
          advance "research-review" "validate-prd-exists"
        else
          if [ ! -f "research/findings.md" ]; then
            emit_blocked "research-review" "research/findings.md missing"
          fi
          WIRING=$({ grep -c "must import\|must extend\|must include\|must add" research/findings.md 2>/dev/null || true; })
          CONSTRAINTS=$({ grep -c "MUST\|MUST NOT" research/findings.md 2>/dev/null || echo "0"; })
          emit "gate" "\"step\":\"research-review\",\"data\":{\"wiring\":$WIRING,\"constraints\":$CONSTRAINTS,\"grillVerdict\":\"$GRILL_VERDICT\",\"grillCritical\":$GRILL_CRITICAL,\"grillMedium\":$GRILL_MEDIUM},\"grillReport\":\"research/grill-report.md\",\"message\":\"Show research/findings.md and research/grill-report.md to user. WAIT for reply. Then: complete research-review success <proceed|adjust:instructions|cancel>\""
          exit 0
        fi
        ;;
```

- [ ] **Step 4: Add grill metadata to the `plan-review` gate**

Find the `plan-review)` case in the NEXT loop:
```bash
      plan-review)
        if [ "$MODE" = "autonomous" ]; then
          advance "plan-review" "preflight"
        else
          STORY_COUNT=$(jq '[.userStories // [] | length] | add // 0' prd.json 2>/dev/null || echo "?")
          PHASE_COUNT=$(jq '.phases | length' prd.json 2>/dev/null || echo "?")
          PROJECT_NAME=$(jq -r '.name // "unknown"' prd.json 2>/dev/null)
          emit "gate" "\"step\":\"plan-review\",\"data\":{\"project\":\"$PROJECT_NAME\",\"stories\":$STORY_COUNT,\"phases\":$PHASE_COUNT},\"message\":\"Show prd.json summary to user. WAIT for reply. Then: complete plan-review success <proceed|adjust:instructions|cancel>\""
          exit 0
        fi
        ;;
```

Replace it with:
```bash
      plan-review)
        GRILL_VERDICT="none"
        GRILL_CRITICAL=0
        GRILL_MEDIUM=0
        if [ -f "plan-grill-report.md" ]; then
          GRILL_VERDICT=$(sed -n 's/^## Verdict: //p' "plan-grill-report.md" 2>/dev/null || echo "unknown")
          GRILL_CRITICAL=$({ sed -n '/## Critical Issues/,/^##/p' "plan-grill-report.md" 2>/dev/null | grep -c '^\- ' || true; })
          GRILL_MEDIUM=$({ sed -n '/## Medium Issues/,/^##/p' "plan-grill-report.md" 2>/dev/null | grep -c '^\- ' || true; })
        fi
        if [ "$MODE" = "autonomous" ]; then
          log_step "plan-review" "grill verdict: $GRILL_VERDICT (critical: $GRILL_CRITICAL, medium: $GRILL_MEDIUM)"
          advance "plan-review" "preflight"
        else
          STORY_COUNT=$(jq '[.userStories // [] | length] | add // 0' prd.json 2>/dev/null || echo "?")
          PHASE_COUNT=$(jq '.phases | length' prd.json 2>/dev/null || echo "?")
          PROJECT_NAME=$(jq -r '.name // "unknown"' prd.json 2>/dev/null)
          emit "gate" "\"step\":\"plan-review\",\"data\":{\"project\":\"$PROJECT_NAME\",\"stories\":$STORY_COUNT,\"phases\":$PHASE_COUNT,\"grillVerdict\":\"$GRILL_VERDICT\",\"grillCritical\":$GRILL_CRITICAL,\"grillMedium\":$GRILL_MEDIUM},\"grillReport\":\"plan-grill-report.md\",\"message\":\"Show prd.json summary and plan-grill-report.md to user. WAIT for reply. Then: complete plan-review success <proceed|adjust:instructions|cancel>\""
          exit 0
        fi
        ;;
```

- [ ] **Step 5: Verify the full pipeline sequence with a dry run**

```bash
cd /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev
mkdir -p /tmp/grill-test2 && cd /tmp/grill-test2
git init -q && echo '{}' > package.json

# Init pipeline
AD_STATE_DIR=".autonomous-dev" /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/scripts/orchestrate.sh init /tmp/grill-test2

# Advance through mode/preset selection
/Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/scripts/orchestrate.sh complete tool-select success claude
/Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/scripts/orchestrate.sh complete mode-select success autonomous
/Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/scripts/orchestrate.sh complete preset-select success balanced

# Fast forward to research step
jq '.step = "research"' .autonomous-dev/state.json > /tmp/s.json && mv /tmp/s.json .autonomous-dev/state.json

# Verify research → research-grill spawn
RESULT=$(/Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/scripts/orchestrate.sh next)
echo "research next → $(echo "$RESULT" | jq -r '.step // .action')"

# Create fake findings.md
mkdir -p research && echo "# Findings" > research/findings.md

# Complete research-grill → should go to research-review (autonomous: auto-advance)
/Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/scripts/orchestrate.sh complete research-grill
RESULT=$(/Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/scripts/orchestrate.sh next)
echo "After research-grill → $(echo "$RESULT" | jq -r '.step // .autoAdvanced // .action')"

# The pipeline should be past research-review (autonomous), now at planner
jq '.step' .autonomous-dev/state.json
```

Expected:
- `research next` → action is `spawn`, step is `research-grill`
- After research-grill → auto-advances past research-review to `planner` (autonomous mode)
- state.json step shows `planner`

- [ ] **Step 6: Verify plan-grill spawn and transition**

```bash
cd /tmp/grill-test2

# Create minimal prd.json and jump to plan-grill
cat > prd.json << 'EOF'
{"name":"test","phases":[{"id":"PHASE-1","name":"Test","stories":["STORY-001"]}],"userStories":[{"id":"STORY-001","title":"Test","phase":"PHASE-1","acceptanceCriteria":["It works"],"estimatedMinutes":30}]}
EOF
jq '.step = "plan-grill"' .autonomous-dev/state.json > /tmp/s.json && mv /tmp/s.json .autonomous-dev/state.json

# plan-grill next should spawn grill-plan
RESULT=$(/Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/scripts/orchestrate.sh next)
echo "plan-grill next → action=$(echo "$RESULT" | jq -r '.action'), step=$(echo "$RESULT" | jq -r '.step')"

# Complete plan-grill → autonomous mode should advance to preflight
/Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev/scripts/orchestrate.sh complete plan-grill
jq '.step' .autonomous-dev/state.json
```

Expected: action is `spawn` with `step:"plan-grill"`, then state.json shows `preflight`

- [ ] **Step 7: Clean up and commit**

```bash
rm -rf /tmp/grill-test2
cd /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev
git add scripts/orchestrate.sh
git commit -m "feat: add research-grill and plan-grill spawn cases with gate metadata"
```

---

### Task 5: Update SKILL.md

Update the pipeline diagram, reference files table, and spawning agents section to document the new grill steps.

**Files:**
- Modify: `SKILL.md`

- [ ] **Step 1: Update the pipeline diagram**

Find in `SKILL.md`:
```
init -> MODE-SELECT -> MODEL-SELECT -> pull-latest -> branch-check -> detect -> baseline
  -> RESEARCH -> [Research Review] -> validate -> PLANNER -> validate-prd -> [Plan Review]
  -> PRE-FLIGHT -> PHASE-1 -> [Phase Review] -> PHASE-2 -> [Phase Review] -> ...
  -> FINAL REVIEW -> PR CREATE -> CI MONITOR -> complete
```

Replace with:
```
init -> MODE-SELECT -> MODEL-SELECT -> pull-latest -> branch-check -> detect -> baseline
  -> RESEARCH -> RESEARCH-GRILL -> [Research Review] -> validate -> PLANNER -> validate-prd
  -> PLAN-GRILL -> [Plan Review] -> PRE-FLIGHT -> PHASE-1 -> [Phase Review] -> PHASE-2 -> ...
  -> FINAL REVIEW -> PR CREATE -> CI MONITOR -> complete
```

- [ ] **Step 2: Update the Spawning Agents section**

Find in `SKILL.md`:
```
# Research
Template: $PIPELINE_DIR/templates/researcher.md
Timeout: 30 min

# Planner
Template: $PIPELINE_DIR/templates/planner.md
Timeout: 30 min
```

Replace with:
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
```

- [ ] **Step 3: Update the Reference Files table**

Find in `SKILL.md`:
```
| `templates/researcher.md` | System audit -> research/findings.md |
| `templates/planner.md` | Findings + PRD -> prd.json + wiring-checklist.json |
```

Replace with:
```
| `templates/researcher.md` | System audit -> research/findings.md |
| `templates/grill-research.md` | Stress-test researcher output -> research/grill-report.md |
| `templates/planner.md` | Findings + PRD -> prd.json + wiring-checklist.json |
| `templates/grill-plan.md` | Stress-test planner output -> plan-grill-report.md |
```

- [ ] **Step 4: Add concurrent dev limitation note**

Find in `SKILL.md` the section about memory or state:
```
## Memory System
```

Add after `## Memory System` (before the bullet list):
```
> **Multi-dev note:** Pipeline state lives in `.autonomous-dev/` inside the project directory. Two developers running pipelines on the same repo simultaneously will conflict on `state.json`. One active pipeline per repo at a time. Branch-keyed state isolation is planned for a future release.
```

- [ ] **Step 5: Verify SKILL.md changes are valid**

```bash
cd /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev
grep "RESEARCH-GRILL" SKILL.md
grep "PLAN-GRILL" SKILL.md
grep "grill-research.md" SKILL.md
grep "grill-plan.md" SKILL.md
grep "Multi-dev note" SKILL.md
```

Expected: all 5 greps return at least one match

- [ ] **Step 6: Commit**

```bash
cd /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev
git add SKILL.md
git commit -m "docs: update SKILL.md pipeline diagram and references for grill steps"
```

---

### Task 6: Final verification

- [ ] **Step 1: Verify all new files exist**

```bash
cd /Volumes/pulsar/apex-local/Developer/github/skyner-group/autonomous-dev
ls -la templates/grill-research.md templates/grill-plan.md
```

Expected: both files exist

- [ ] **Step 2: Verify no qdrant-find in grill templates**

```bash
grep -r "qdrant" templates/grill-research.md templates/grill-plan.md
```

Expected: no output (no qdrant references)

- [ ] **Step 3: Verify orchestrate.sh step sequence is correct**

```bash
grep -n "research-grill\|plan-grill" scripts/orchestrate.sh
```

Expected: lines showing transitions (research→research-grill, research-grill→research-review), spawn cases, and plan-grill cases

- [ ] **Step 4: Verify SKILL.md has both grill steps in the diagram**

```bash
grep -A2 "RESEARCH-GRILL" SKILL.md
grep -A2 "PLAN-GRILL" SKILL.md
```

Expected: both appear in context of the pipeline flow

- [ ] **Step 5: Verify git log shows all commits**

```bash
git log --oneline -6
```

Expected: 4 commits for this feature (grill-research.md, grill-plan.md, transitions, spawn cases + SKILL.md)

- [ ] **Step 6: Verify ShellCheck has no new errors**

```bash
shellcheck scripts/orchestrate.sh 2>&1 | head -20
```

Expected: no new errors (ignore pre-existing SC2034 which is already shellcheck-disabled)
