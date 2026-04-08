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

## Key Scripts for Agents

Agents should call these directly instead of reimplementing the logic:

- `$HOUSTON_DIR/scripts/create-pr.sh <TICKET-ID>` — Creates PR (GitHub) or MR (GitLab). Auto-detects platform, loads reviewers from profile, formats title as `type(area): description [TICKET-ID]`, body is 2 bullet points. Enables squash, delete source branch, auto-merge.
- `$HOUSTON_DIR/pipeline/quality-gate.sh --scope story|phase|final --config <path>` — Runs quality gates. 3 tiers of increasing rigor with baseline diffing.
- `$HOUSTON_DIR/pipeline/detect-project.sh <path>` — Detects tech stack, outputs JSON with test/build/lint commands.
- `$HOUSTON_DIR/pipeline/detect-context.sh <path>` — Detects profile from git remote, outputs JSON with identity/reviewers/platform.

## Key Conventions

- All scripts use `set -euo pipefail` (except orchestrate.sh which uses `set -u`)
- Detection scripts output JSON to stdout
- State files live in `~/.houston/runs/<ticket-id>/`, never in the target repo
- Profile credentials are referenced by env var name, never stored directly
- PR/MR title format: `feat|fix|chore(area): description [TICKET-ID]`
- PR/MR body: 2 bullet points only (CodeRabbit summarizes the rest)
- Always enable: squash commits, delete source branch, auto-merge
