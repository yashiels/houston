# BART

> **B**uild **A**utonomously with **R**eview and **T**esting

Autonomous development loop that takes a PRD and produces production-ready code with TDD, multi-agent orchestration, and code-enforced quality gates.

## Features

- 🎯 **Fresh Context Per Story** — Each story gets a clean Claude session
- 🔄 **Multi-Agent Architecture** — Supervisor → Coder → Reviewer → Tester
- ✅ **TDD Enforced** — RED → GREEN → REFACTOR (not optional)
- 🔒 **Code-Enforced Gates** — Hooks block bad commits, not just prompts
- 📊 **Progress Tracking** — 5-minute updates, learnings log
- ⚙️ **Configurable Models** — Choose opus/sonnet/haiku per agent
- 🆕 **New or Existing** — Set up fresh project or add to existing

## Prerequisites

1. **Claude Code CLI** installed and authenticated
   ```bash
   # Check if installed
   claude --version
   
   # If not, visit https://claude.ai/code
   ```

2. **Node.js 18+**
   ```bash
   node --version
   ```

## Installation

```bash
# Clone
git clone https://github.com/moltpill/bart.git
cd bart

# Install
npm install

# Make executable
chmod +x bin/bart.js
```

## Quick Start

```bash
# Run BART
npm start

# Or directly
node bin/bart.js
```

You'll see an interactive wizard:

```
┌  BART  — Autonomous Development Loop
│
◆  Project type:
│  ● New project (set up from scratch)
│  ○ Existing project (add to codebase)
└

◆  Select your PRD file:
│  ● examples/todo-api.md
│  ○ Enter custom path...
└

◆  Use default models? (Supervisor: opus, Coder: sonnet, Reviewer: sonnet, Tester: haiku)
│  ● Yes
│  ○ No, customize
└

◆  Operating mode:
│  ● Fully Autonomous
│  ○ Human Assisted
└
```

## How It Works

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SUPERVISOR AGENT (Long-Running)                   │
│  • Reports every 5 minutes                                          │
│  • Orchestrates phase transitions                                   │
│  • Helps stuck workers                                              │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│ CODER AGENT   │ │ CODER AGENT   │ │ CODER AGENT   │
│ (Fresh ctx)   │ │ (Fresh ctx)   │ │ (Fresh ctx)   │
│ Story 1       │ │ Story 2       │ │ Story N       │
└───────┬───────┘ └───────┬───────┘ └───────┬───────┘
        │                 │                 │
        └────────────────▼────────────────┘
                          │
                  ┌───────────────┐
                  │ REVIEWER      │
                  │ +Smoke tests  │
                  │ +API tests    │
                  │ +Integration  │
                  └───────┬───────┘
                          │
              ┌───────────────────────┐
              │   FINAL E2E REVIEW    │
              │ (Tester Agent)        │
              │ • Full test suite     │
              │ • Build verification  │
              │ • Deployment ready    │
              └───────────────────────┘
```

## Code-Enforced Quality Gates

BART installs hooks that **actually block** bad behavior (not just prompt suggestions):

| Hook | Trigger | Action |
|------|---------|--------|
| `inject-rules.sh` | Session Start | Re-inject rules (survives compaction) |
| `block-shortcuts.sh` | Bash Commands | Block SSH, docker exec, force push, skip-ci |
| `pre-commit-gate.sh` | git commit | Block if tests/typecheck/build fail |
| `post-edit-tests.sh` | File Edits | Run related tests (informational) |

## Agent Models

Configure different models for different roles:

| Agent | Default | Role |
|-------|---------|------|
| **Supervisor** | opus | Orchestrates, monitors, helps stuck stories |
| **Coder** | sonnet | Implements stories with TDD |
| **Reviewer** | sonnet | Reviews phases, adds tests |
| **Tester** | haiku | Final E2E verification |

Override during setup or customize all:

```
◆  Supervisor model (orchestrates everything):
│  ● Opus
│  ○ Sonnet
│  ○ Haiku
└
```

## Operating Modes

### Fully Autonomous
- Runs start-to-finish without intervention
- Reports every 5 minutes
- Only stops on critical blockers

### Human Assisted
- Pauses after each phase for approval
- Allows retry/skip/abort on failures
- Recommended for first run

## Project Types

### New Project
BART sets up everything from scratch:
- Project structure with best practices
- TypeScript configuration
- Testing framework (Vitest)
- Linting (ESLint)
- .gitignore
- Git initialization
- Initial commit

### Existing Project
BART analyzes and adapts:
- Auto-detects package manager
- Detects monorepo, Docker, TypeScript
- Shows project-specific gotchas
- Creates feature branch

## PRD Format

```markdown
# Feature: Your Feature Name

## Overview
What you're building and why.

## Requirements
- Requirement 1
- Requirement 2

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Technical Notes (optional)
- Use TypeScript
- Use Vitest for testing
```

## Files Created

| File | Purpose |
|------|---------|
| `.bart/prd.json` | Stories with status tracking |
| `.bart/progress.txt` | Append-only learnings log |
| `CLAUDE.md` | Entry point for Claude |
| `AGENTS.md` | Conventions, patterns, gotchas |
| `ARCHITECTURE.md` | System design |
| `.claude/hooks/*` | Code-enforced quality gates |

## The Rules (Non-Negotiable)

1. **GitHub is the Source of Truth**
   - Code → Commit → Push → CI/CD → Deploy
   - No hotfixes, no manual patches

2. **TDD is Mandatory**
   - RED → GREEN → REFACTOR
   - Write failing test first

3. **Pre-Commit Testing**
   - Tests must pass
   - Typecheck must pass
   - Build must pass
   - CI/CD should never fail

4. **Forbidden Actions** (Hooks block these)
   - ⛔ SSH into servers
   - ⛔ docker exec
   - ⛔ Force push to main
   - ⛔ Skip CI flags
   - ⛔ Hardcode values to pass tests

## Resuming

If BART stops (error, timeout, user interrupt):

1. Run `npm start` again
2. Select the same project directory
3. BART loads `.bart/prd.json` and continues from where it stopped

Stories marked `passes: true` are skipped.

## Example Run

```bash
npm start

# Select: New project
# Directory: ./my-todo-api
# Template: Node.js API
# PRD: examples/todo-api.md
# Models: Use defaults
# Mode: Fully Autonomous

# BART will:
# 1. Create project structure
# 2. Break PRD into 8-12 stories
# 3. Implement each with TDD
# 4. Review each phase
# 5. Run final E2E verification
# 6. Report completion
```

## License

MIT
