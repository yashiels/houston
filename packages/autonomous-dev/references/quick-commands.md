# Quick Command Reference

Copy-paste ready commands for autonomous development. Covers both CLI and Agent modes.

---

## Section 1: CLI Mode (ac.sh)

### Initialize a Pipeline

```bash
# From your project directory:
ac init "Linear issue URL or description"

# With specific preset:
ac init --preset quality "Build the dashboard"
ac init --preset balanced "Add auth system"
ac init --preset budget "Fix the login bug"
```

### Resume a Pipeline

```bash
ac resume
# Reads .autonomous-dev/state.json and continues from last checkpoint
```

### Run Quality Gates

```bash
# Per-story (fast)
ac gate story

# Per-phase (thorough)
ac gate phase

# Final (everything)
ac gate final
```

### Check Status

```bash
ac status
# Shows: current phase, story progress, active workers
```

### Validate PRD

```bash
ac validate prd.json
# Checks structure, phase references, duplicate IDs
```

### Detect Project

```bash
ac detect
# Outputs JSON with: lang, package_manager, test_cmd, build_cmd, etc.
```

---

## Section 2: Agent Mode (orchestrate.sh)

### Start Orchestration

```bash
./scripts/orchestrate.sh "Linear issue URL or feature description"

# With options:
./scripts/orchestrate.sh --mode autonomous "Build the API"
./scripts/orchestrate.sh --mode assisted "Refactor auth"
./scripts/orchestrate.sh --preset quality "Critical feature"
```

### Spawn Worker (Fresh Context)

```javascript
sessions_spawn({
  task: `AUTONOMOUS DEV WORKER — Fresh Context

## Bootstrap (in order)
1. cd ${projectPath}
2. cat CLAUDE.md
3. Read story: jq '.userStories[] | select(.id=="${storyId}")' prd.json
4. Read learnings: tail -50 progress.txt
5. Read conventions: cat AGENTS.md

## Your Assignment
Story ID: ${storyId}

## Process
1. TDD: failing test -> code -> pass -> commit
2. Run quality gate: ./scripts/quality-gate.sh --scope story
3. Commit: git commit -m "${storyId}: <title>"
4. Update AGENTS.md if patterns found

## Output
STORY_COMPLETE | STORY_BLOCKED: <reason>`,

  model: 'opus',
  label: `worker-${storyId}`,
  runTimeoutSeconds: 1800,
  cleanup: 'delete'
})
```

### Spawn Phase Runner

```javascript
sessions_spawn({
  task: `PHASE AGENT — ${phase.name}

Implement stories: ${stories.join(', ')}
TDD for each. All tests must pass.
PHASE_COMPLETE when done.`,

  model: 'opus',
  label: `phase-${phase.id}`,
  runTimeoutSeconds: 3600,
  cleanup: 'delete'
})
```

### Spawn Review Agent

```javascript
sessions_spawn({
  task: `REVIEW AGENT — ${phase.name}

1. Verify ALL tests pass
2. Add smoke tests for new features
3. Add API/integration tests
4. Add build verification
5. NO shortcuts

REVIEW_COMPLETE when done.`,

  model: 'opus',
  label: `review-${phase.id}`,
  runTimeoutSeconds: 1800,
  cleanup: 'delete'
})
```

### Spawn Final E2E Review

```javascript
sessions_spawn({
  task: `FINAL E2E REVIEW

Full integration verification:
1. All tests pass
2. E2E tests exist/pass
3. Build succeeds
4. Docs updated
5. Ready for merge

E2E_REVIEW_COMPLETE when done.`,

  model: 'opus',
  label: 'final-e2e-review',
  runTimeoutSeconds: 2700,
  cleanup: 'keep'
})
```

---

## Section 3: Quality Gates

### Three-Tier System

| Scope | When | What |
|-------|------|------|
| `story` | After each story commit | Package tests + root typecheck + lockfile |
| `phase` | Phase review | Full test suite + typecheck + build + lint + anti-patterns + wiring + reachability |
| `final` | Before PR | Everything above + Docker + E2E + CI scripts |

### Running Gates

```bash
# Capture baseline (once at pipeline init)
./scripts/quality-gate.sh --baseline capture

# Per-story (fast, ~30s)
./scripts/quality-gate.sh --scope story

# Per-phase (thorough, ~3-5 min)
./scripts/quality-gate.sh --scope phase

# Final (everything, ~10 min)
./scripts/quality-gate.sh --scope final

# With explicit config
./scripts/quality-gate.sh --scope phase --config .autonomous-dev/project-config.json

# Skip optional gates
./scripts/quality-gate.sh --scope final --skip-docker --skip-build
```

### Baseline Diffing

```bash
# Capture baseline before any work
./scripts/quality-gate.sh --baseline capture
# Creates .baseline-failures.txt and .baseline-gate.log

# All subsequent gates auto-diff against baseline:
# - New failures = BLOCKED
# - Pre-existing failures = WARN (exit 0)
```

### Individual Checks

```bash
# Anti-pattern scan
./scripts/anti-pattern-scan.sh HEAD~3

# Wiring verification
./scripts/wiring-check.sh wiring-checklist.json

# Reachability (dead code detection)
./scripts/reachability-check.sh main

# PRD validation
./scripts/validate-prd.sh prd.json

# Project detection
./scripts/detect-project.sh /path/to/project
```

---

## Section 4: Common Workflows

### Start a New Feature (Full Flow)

```bash
# 1. Initialize pipeline
ac init "https://linear.app/team/issue/PROJ-123"

# 2. Pipeline creates: prd.json, state.json, baseline
# 3. Workers execute stories with TDD
# 4. Phase gates run automatically
# 5. Final review before PR

# Or manually:
./scripts/orchestrate.sh "https://linear.app/team/issue/PROJ-123"
```

### Resume After Context Reset

```bash
# Check state
./scripts/resume.sh .autonomous-dev/state.json

# Continue from last checkpoint
ac resume
```

### Check Progress

```bash
# Count complete stories
jq '[.userStories[] | select(.passes==true)] | length' prd.json

# Count remaining
jq '[.userStories[] | select(.passes!=true)] | length' prd.json

# List incomplete stories
jq '.userStories[] | select(.passes!=true) | {id, phase, title}' prd.json

# Progress by phase
jq '.phases[] as $p | {
  phase: $p.name,
  complete: [.userStories[] | select(.phase==$p.id and .passes==true)] | length,
  total: [.userStories[] | select(.phase==$p.id)] | length
}' prd.json
```

### Mark Story Complete

```bash
jq '(.userStories[] | select(.id=="STORY-001")).passes = true' prd.json > tmp.json && mv tmp.json prd.json
```

### Verify Before PR

```bash
# Run final quality gate
./scripts/quality-gate.sh --scope final

# If all pass, create PR
git push origin feature-branch
gh pr create --title "feat: description" --body "..."
```

### Debug a Failing Story

```bash
# Check progress log
tail -50 progress.txt

# Run tests for specific package
cd packages/affected-package && npm test

# Check anti-patterns
./scripts/anti-pattern-scan.sh HEAD~1

# Check wiring
./scripts/wiring-check.sh
```

### Install Hooks

```bash
# Copy hooks to your project
cp -r hooks/.claude/ /path/to/your/project/.claude/
chmod +x /path/to/your/project/.claude/hooks/*.sh
```
