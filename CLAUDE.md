# Houston

Multi-context autonomous development orchestrator. Dispatches development pipelines via agent-deck across multiple orgs, Linear workspaces, and source control platforms.

## Project Structure

- `profiles/` — TOML config files defining development contexts (credentials, orgs, reviewers)
- `pipeline/` — Shell scripts: state machine orchestrator, stage spawner, detection logic
- `templates/` — Agent prompt templates for each pipeline stage
- `rules/` — Enforcement rules (no-shortcuts, quality gates, anti-patterns)
- `hooks/` — Claude Code hooks copied into target repos at pipeline init
- `scripts/` — Dispatch and utility scripts
- `skills/` — Claude Code skill definitions (/houston entry point)
- `tests/` — Bats test suite for shell scripts

## Key Conventions

- All scripts use `set -euo pipefail`
- Detection scripts output JSON to stdout
- State files live in `~/.houston/runs/<ticket-id>/`, never in the target repo
- Profile credentials are referenced by env var name, never stored directly
- Scripts are POSIX-compatible where possible, bash where necessary
