# Houston

Multi-context autonomous development orchestrator for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Dispatches development pipelines via [agent-deck](https://github.com/asheshgoplani/agent-deck) across multiple orgs, Linear workspaces, and source control platforms.

One command — research, plan, code (TDD), review, PR, CI monitor.

## Quick Start

```bash
git clone https://github.com/yashiels/houston.git
cd houston
./scripts/install.sh
```

Then in any repo:

```bash
/houston SWITCH-167                        # from Linear ticket
/houston SWITCH-167 SWITCH-168 DEV-42      # multi-ticket (dependency-aware)
/houston Add retry logic to the webhook    # from prompt
/houston --spec tasks/retry-spec.md        # from spec file
/houston --from-plan tasks/plan.md         # from pre-approved plan
/houston status                            # running pipelines
/houston resume SWITCH-167                 # resume a crashed pipeline
```

## How It Works

```
/houston SWITCH-167
        │
        ▼
   ┌─────────────┐     ┌──────────────┐
   │ Detect      │────▶│ Load Profile │ (stitch / personal)
   │ Context     │     │ + Credentials│
   └─────────────┘     └──────┬───────┘
                               │
        ┌──────────────────────┘
        ▼
   ┌─────────────┐
   │ agent-deck  │  launches tmux session
   │ launch      │  with credential isolation
   └──────┬──────┘
          │
          ▼
   ┌──────────────────────────────────────┐
   │        Orchestrator (orchestrate.sh) │
   │                                      │
   │  init → detect → baseline            │
   │    → RESEARCH → GRILL                │
   │    → [gate] → PLAN → GRILL           │
   │    → [gate] → PRE-FLIGHT             │
   │    → PHASE-1 → quality-gate          │
   │    → PHASE-2 → quality-gate          │
   │    → FINAL-REVIEW → CODE-SIMPLIFY    │
   │    → PR-CREATE → CI-MONITOR          │
   │    → LINEAR-UPDATE → complete        │
   │                                      │
   │  Each AI stage = disposable Claude   │
   │  State persisted to disk between     │
   └──────────────────────────────────────┘
```

Each ticket gets one agent-deck session visible in the TUI. The orchestrator shell script inside that session spawns fresh Claude sessions per stage — no context window exhaustion.

## Profiles

Houston uses TOML profiles to manage multiple development contexts. Auto-detected from git remote.

```toml
# profiles/stitch.toml
[profile]
name = "stitch"
priority = 10

[identity]
name = "Yashiel Sookdeo"
email = "yashiel.sookdeo@stitch.money"

[linear]
api_key_env = "LINEAR_API_KEY"
org = "Stitch"
default_team = "Card - Switch"

[reviewers.github]
"stitch-Money/*" = ["damgene", "jeremy-stitch", "shivekiyer"]

[reviewers.gitlab]
"pos/exi-terminal-*" = ["talha535", "pratham.patel", "christopher.cann"]
"*" = ["michael.willans", "shivekiyer", "jamesmaina"]

[detect]
remote_patterns = ["stitch", "exipay"]
```

Profile detection: git remote URL → match against `remote_patterns` → load credentials, reviewers, Linear workspace. If ambiguous, highest `priority` wins.

## Pipeline Modes

| Mode | Behavior | Use case |
|------|----------|----------|
| **Supervised** (default) | Pauses at research + plan gates for review | New repos, complex tickets |
| **Autonomous** | No gates, alerts only on BLOCKED | Known codebases, routine work |
| **Human-assisted** | Pauses at every phase gate | Critical work, learning a codebase |

## Multi-Ticket Dispatch

```bash
/houston SWITCH-167 SWITCH-168 DEV-42
```

Houston looks up all tickets in Linear, checks for dependency relations (blocks/blocked-by), and:
- Launches independent tickets in parallel
- Sequences dependent tickets automatically
- Works across Linear workspaces (tries each API key)

## Quality Gates

Three tiers of increasing rigor, with baseline diffing (pre-existing failures warn, new failures block):

| Tier | Runs when | Checks |
|------|-----------|--------|
| **Story** | After each story | Unit tests, typecheck, anti-pattern scan |
| **Phase** | After each phase | Full tests, build, lint |
| **Final** | Before PR creation | Everything + E2E, docker, security scan |

## Agent Templates

Each pipeline stage uses a disposable Claude session with a focused prompt template:

| Template | Role |
|----------|------|
| `researcher.md` | Audit codebase before development |
| `planner.md` | Convert spec → phased implementation plan (prd.json) |
| `coder.md` | TDD implementation per story |
| `phase-supervisor.md` | Manage one phase, spawn coders, detect drift |
| `grill-research.md` | Adversarial review of research findings |
| `grill-plan.md` | Adversarial review of implementation plan |
| `reviewer.md` | Phase quality review |
| `final-review.md` | E2E review before PR |
| `code-simplify.md` | Post-implementation cleanup |

## Stack Detection

Auto-detects 13+ tech stacks and their tooling:

Node.js (npm/pnpm/yarn/bun), Python (poetry/uv/pip), Go, Rust, Flutter, Java/Kotlin (Gradle/Maven), Elixir, Swift, C++, Ruby, PHP

Plus: monorepo detection, Docker detection, TypeScript detection.

## Linear Integration

- Ticket lookup across multiple workspaces
- Status updates (In Progress → In Review → Done)
- Sub-ticket creation with parent linking
- PR/MR attachment to tickets
- Dependency relation checking

## Hooks

Copied into target repos at pipeline init to enforce discipline:

| Hook | Purpose |
|------|---------|
| `block-shortcuts.sh` | Blocks force push, --no-verify, ssh hacks |
| `pre-commit-gate.sh` | Warns if no recent test run before commit |
| `post-edit-tests.sh` | Reminds to run tests after source edits |

## Project Structure

```
houston/
├── profiles/          TOML profile configs (identity, orgs, reviewers)
├── pipeline/          Core scripts (orchestrator, detection, spawner, Linear API)
├── templates/         Agent prompt templates (10 templates)
├── rules/             Anti-patterns, no-shortcuts, quality gate docs
├── hooks/             Claude Code enforcement hooks
├── scripts/           Dispatch, status, install
├── skills/            /houston Claude Code skill
├── references/        Methodology, PR comment guidelines
└── tests/             Bats test suite (47 tests)
```

## Consolidated Packages

This monorepo also includes the following autonomous development tools under `packages/`:

| Package | Origin | Description |
|---------|--------|-------------|
| [`packages/autonomous-dev`](packages/autonomous-dev) | [skynergroup/autonomous-dev](https://github.com/skynergroup/autonomous-dev) | PRD-to-PR autonomous development tool (Shell + Python) |
| [`packages/bart`](packages/bart) | [yashiels/bart](https://github.com/yashiels/bart) (fork of [moltpill/bart](https://github.com/moltpill/bart)) | Autonomous development loop (Shell + Python) |

## State

All runtime state lives in `~/.houston/runs/<ticket-id>/` — never in the target repo.

```
~/.houston/runs/SWITCH-167/
├── state.json                 Pipeline state (current step, mode, profile)
├── context.json               Detected profile + platform
├── project.json               Detected tech stack
├── spec.md                    Ticket spec
├── prd.json                   Implementation plan (phases + stories)
├── research/
│   ├── findings.md            Research output
│   └── grill-report.md        Research review
├── plan-grill-report.md       Plan review
├── memory/
│   ├── learnings.md           Cross-phase insights
│   └── phase-1-summary.md     Per-phase summaries
├── progress.txt               Human-readable log
└── logs/                      Per-stage logs
```

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [agent-deck](https://github.com/asheshgoplani/agent-deck)
- `jq`, `git`, `curl`
- Linear API key(s) in environment variables

## References

Built on patterns from:
- [skynergroup/autonomous-dev](https://github.com/skynergroup/autonomous-dev) — Pipeline patterns, quality gates, templates
- [asheshgoplani/agent-deck](https://github.com/asheshgoplani/agent-deck) — Session management, TUI
- [thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) — Persistent memory (optional integration)
- [martian-engineering/lossless-claw](https://github.com/martian-engineering/lossless-claw) — Context compression (optional)

## License

MIT
