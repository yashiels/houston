# CLAUDE.md Best Practices

Guidelines for writing effective CLAUDE.md files in autonomous development.

## What is CLAUDE.md?

A special file that Claude Code reads at the **start of every session**. It goes into the system prompt automatically, making it the highest-leverage configuration point.

## The Golden Rule: Less is More

| Metric | Recommendation |
|--------|----------------|
| Lines | <60 ideal, <300 max |
| Instructions | Keep to essential only |
| Content | Universally applicable to ALL tasks |

**Why?**
- LLMs can reliably follow ~150-200 instructions max
- Claude Code's system prompt already uses ~50 instructions
- As instruction count increases, compliance decreases **uniformly** (not just for new ones)
- Claude Code may **ignore** CLAUDE.md entirely if it seems irrelevant

## Structure: WHAT, WHY, HOW

```markdown
# Project: my-app

## WHAT (Tech Stack)
- Framework: Next.js 15
- Database: PostgreSQL + Prisma
- Testing: Vitest

## WHY (Purpose)
E-commerce platform for artisan goods.

## HOW (Workflows)
- Build: `npm run build`
- Test: `npm test`
- Typecheck: `npm run typecheck`

## Before You Code
Read these for details:
- `AGENTS.md` — Conventions, patterns, gotchas
- `ARCHITECTURE.md` — System design, data flow
```

## Progressive Disclosure

Don't put everything in CLAUDE.md. Point to other files:

```
CLAUDE.md (minimal, ~40 lines)
    |
    +---> AGENTS.md (conventions, patterns)
    |
    +---> ARCHITECTURE.md (system design)
    |
    +---> progress.txt (recent learnings)
    |
    +---> prd.json (current tasks)
```

Workers read CLAUDE.md first, then load other docs as needed.

## What NOT to Include

- **Code style rules** — Use linters and formatters instead
- **Edge case handling** — Put in AGENTS.md
- **Full API documentation** — Point to files
- **Database schemas** — Reference ARCHITECTURE.md
- **Every possible command** — Just the common ones

## What TO Include

- **Build/test/typecheck commands** — Universal
- **Pointers to key docs** — Progressive disclosure
- **Workflow summary** — TDD, commit conventions
- **Project name/purpose** — Quick orientation

## Template for Autonomous Dev

```markdown
# Project: [NAME]

## Quick Start
- Build: `npm run build`
- Test: `npm test`
- Typecheck: `npm run typecheck`

## Before You Code
Read these files first:
- `AGENTS.md` — Conventions, patterns, gotchas
- `ARCHITECTURE.md` — System design, components
- `progress.txt` — Recent learnings (tail -50)
- `prd.json` — Your assigned story

## Workflow
1. Read story from prd.json
2. TDD: RED -> GREEN -> REFACTOR
3. Run quality gates before commit
4. Update AGENTS.md if you discover patterns
5. Commit (free-form during dev, squashed on merge)
```

## Relationship to Other Files

| File | Purpose | Size |
|------|---------|------|
| `CLAUDE.md` | Entry point, commands, pointers | <60 lines |
| `AGENTS.md` | Conventions, patterns, gotchas | Grows over time |
| `ARCHITECTURE.md` | System design, components | Grows over time |
| `progress.txt` | Session learnings | Append-only |

CLAUDE.md stays small. AGENTS.md and ARCHITECTURE.md grow as workers discover things.

## Key Insight

> "CLAUDE.md is the highest leverage point of the harness. A bad line in CLAUDE.md affects every phase of your workflow and every artifact produced."

Don't auto-generate it. Craft it carefully. Every line should earn its place.
