# Autonomous Development Methodology

Background theory on the frameworks this skill combines.

## Operating Modes

**Fully Autonomous** — Supervisor runs start-to-finish. Only alerts on critical blockers.
Best for: well-defined PRDs, established codebases.

**Human Assisted** — Pauses at phase boundaries for approval, more frequent check-ins.
Best for: first runs, complex projects, unfamiliar codebases.

## Ralph Loop (snarktank/ralph)

Core insight: **Fresh context each iteration**. Memory persists via files, not conversation.

Each story worker starts with a clean session and reads only what it needs:
- `prd.json` → assigned story
- `progress.txt` → recent learnings
- `AGENTS.md` → project conventions
- Relevant source files → found via grep, not bulk reads

This prevents context pollution across stories. One story's confusion can't affect the next.

## Superpowers TDD (obra/superpowers)

Mandatory TDD workflow:
1. **RED** — Write failing test for each acceptance criterion
2. **GREEN** — Write minimal code to make tests pass
3. **REFACTOR** — Clean up while tests still pass

Two-stage code review:
- **Spec compliance**: Does it meet all acceptance criteria?
- **Code quality**: Clean, follows project patterns, no obvious bugs?

## Context Budget Per Story

Target: keep reads under 50% of context window to leave room for generation.

```
Bootstrap reads (always):
  prd.json (single story)     ~500 tokens
  progress.txt (tail -50)     ~1000 tokens
  AGENTS.md                   ~1000 tokens
  ARCHITECTURE.md (if needed) ~1000 tokens
  Total bootstrap             ~3500 tokens

On-demand reads:
  Relevant source files        ~5000-10000 tokens
  Test files                   ~2000 tokens
  Total working set            ~15000 tokens

Reserved for generation:       50000+ tokens
```

Anti-patterns that cause context bloat:
- Reading entire `src/` directory upfront
- Loading all tests before knowing what to change
- Passing full `prd.json` in the spawn task (pass only the story ID)
- Reading files "just in case"

## Story Sizing Guidelines

Right-sized stories (15-30 minutes each):
- Add a database column and migration
- Create a UI component
- Add an API endpoint
- Implement a utility function
- Add form validation
- Write integration tests for a feature

Too big — split these:
- "Build the dashboard" → individual widgets
- "Add authentication" → login, register, session, logout as separate stories
- "Refactor the API" → specific endpoints

Splitting strategy: ask "What's the smallest useful increment?"

## Progress.txt Format

```markdown
# Progress Log

Started: 2026-01-01 15:00

## STORY-001: Add login form
- [15:05] Started implementation
- [15:12] Tests written, all failing (RED)
- [15:22] All tests passing (GREEN)
- [15:23] Committed: abc123
- Learning: Project uses react-hook-form, not controlled inputs

## STORY-002: Add login API
- [15:30] Started
- [15:35] Discovered auth utility already exists in src/lib/auth
- Learning: Check src/lib/ for existing utilities before creating new ones
- [15:45] Complete, committed: def456
```

## AGENTS.md Conventions

Workers update AGENTS.md when they discover reusable patterns:

```markdown
# Project Conventions

## Stack
- Framework: Next.js 15 (App Router)
- Testing: Vitest (run: pnpm test)
- Typecheck: pnpm exec tsc --noEmit

## Utilities
- Auth helpers: src/lib/auth.ts
- API client: src/lib/api.ts

## Gotchas
- Must run `pnpm db:generate` after schema changes
- API routes need auth middleware wrapper
- Forms need "use client" directive
```

## ARCHITECTURE.md Structure

Workers update ARCHITECTURE.md when they change system structure:

```markdown
# Architecture

## Overview
Brief description of the system.

## Directory Structure
src/
  app/        # Next.js pages + API routes
  components/ # React components
  lib/        # Shared utilities
  services/   # Business logic

## Data Flow
1. User action → Server Action or API Route
2. Route → Service layer
3. Service → Database

## Design Decisions
- Why key choices were made
```

## Handling Edge Cases

**Flaky tests** — Worker retries once. If still flaky, note in progress.txt. Supervisor decides: fix or skip.

**Missing dependencies** — Worker documents what's needed. Supervisor installs or creates prerequisite story.

**Architectural decisions** — Workers flag for supervisor review. Supervisor asks user if unclear.

**External API issues** — Mock for tests where possible. Document dependencies and rate limits.
