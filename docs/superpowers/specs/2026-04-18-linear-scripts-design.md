# Linear Scripts Design

**Date:** 2026-04-18
**Branch:** feature/linear-scripts
**Status:** Approved

## Overview

Extend Houston with a suite of Linear API scripts and skills so that agents (Claude, Codex, or any dev's choice) can browse and manage Linear teams, projects, and issues through well-defined `/houston:linear-*` skill invocations. Builds on the existing `pipeline/linear.sh` GraphQL library and the profile system.

## Goals

- Agents can list teams, projects, and issues with smart defaults from their profile
- Agents can create and update issues (title, description, project, priority, assignee, labels, parent) and projects
- Agents can add comments to issues
- Two agent-identity profiles (`apex`, `astra`) scoped to Skyner Group / Nexion work
- All scripts output JSON; all mutations accept human-readable names (no UUID knowledge required by agent)

## Out of Scope

- Issue state updates (driven by GitHub PR lifecycle — already handled by `orchestrate.sh`)
- Issue fields: estimate, due date, cycle
- Multi-workspace search (single Skyner org for agent profiles)

---

## Section 1: Agent Profiles

### `profiles/apex.toml`

```toml
[profile]
name = "apex"
priority = 1
type = "agent"

[identity]
name = "Apex"
email = "apex@skyner.co.za"
git_user = "apex-skyner"

[linear]
api_key_env = "LINEAR_API_KEY"
org = "Skyner Group"
default_team = "Development"
teams = ["Development"]

[platforms.github]
orgs = ["yashiels", "skynergroup"]

[owners]
users = ["yashiels", "mphocodes"]

[detect]
remote_patterns = []
```

### `profiles/astra.toml`

```toml
[profile]
name = "astra"
priority = 1
type = "agent"

[identity]
name = "Astra"
email = "astra@skyner.co.za"
git_user = "astra-skyner"

[linear]
api_key_env = "ASTRA_LINEAR_API_KEY"
org = "Skyner Group"
default_team = "Development"
teams = ["Development"]

[platforms.github]
orgs = ["yashiels", "skynergroup"]

[owners]
users = ["yashiels", "mphocodes"]

[detect]
remote_patterns = []
```

### Profile Selection Order (all new scripts)

1. `--profile NAME` flag → load `profiles/NAME.toml`
2. `HOUSTON_PROFILE` env var → load `profiles/$HOUSTON_PROFILE.toml`
3. Git remote auto-detection (existing `detect-context.sh` behaviour)

### Schema Updates (`profiles/schema.toml`)

Two new optional fields documented:
- `[profile] type = ""` — `"agent"` or `"human"` (omit for human)
- `[owners] users = []` — for agent profiles: which human git users this agent works under

### Notes

- `detect.remote_patterns = []` — agent profiles never auto-activate from git remote; always require explicit selection
- `priority = 1` — lower than `personal` (5) and `stitch` (10), never wins ambiguous detection
- `apex` uses the existing `LINEAR_API_KEY` env var (already set in `~/.zshrc`)
- `astra` requires `ASTRA_LINEAR_API_KEY` added to `~/.zshrc` (astra already exists as a Linear member in the Skyner Group org)

---

## Section 2: Scripts (`scripts/`)

All scripts:
- Are standalone executables (`chmod +x`)
- Use `set -euo pipefail`
- Source `$HOUSTON_DIR/pipeline/linear.sh` for GraphQL primitives
- Source `$HOUSTON_DIR/pipeline/lib/parse-profile.sh` for profile loading
- Output JSON to stdout
- Write errors to stderr as `{"error":"..."}`
- Support `--profile NAME` flag for profile override

### Read Scripts

#### `linear-teams.sh`

```
Usage: linear-teams.sh [--profile NAME]
```

Lists all teams in the workspace. Output: array of `{id, name, key}`.

#### `linear-projects.sh`

```
Usage: linear-projects.sh [--team TEAM_NAME] [--profile NAME]
```

Lists projects. Defaults to `default_team` from profile if `--team` omitted.
Output: array of `{id, name, state, description, url}`.

Note: `state` is a scalar string on projects (`backlog`, `planned`, `started`, `paused`, `completed`, `cancelled`).

#### `linear-issues.sh`

```
Usage: linear-issues.sh [--project PROJECT_NAME] [--team TEAM_NAME]
                        [--state STATE] [--assignee NAME_OR_EMAIL]
                        [--limit N] [--profile NAME]
```

Lists issues with optional filters. Defaults to `default_team` from profile.
`--project` accepts either a project name ("Skyner Mono") or UUID — UUID is tried first, then name resolution.
Output: array of `{id, identifier, title, priority, state, assignee, project, labels, url}`.

Priority values: `0` = none, `1` = urgent, `2` = high, `3` = medium, `4` = low.

#### `linear-get-issue.sh`

```
Usage: linear-get-issue.sh <ISSUE-ID> [--profile NAME]
```

Full issue details. Output: single issue object with id, identifier, title, description, priority, state, assignee, project, labels, parent, children, relations, url, branchName.

### Write Scripts

#### `linear-create-issue.sh`

```
Usage: linear-create-issue.sh --title TITLE
                               [--team TEAM_NAME]
                               [--description DESC]
                               [--project PROJECT_NAME]
                               [--priority 0-4]
                               [--assignee NAME_OR_EMAIL]
                               [--labels "Bug,Feature"]
                               [--parent ISSUE-ID]
                               [--profile NAME]
```

Defaults `--team` to profile's `default_team`. Resolves all names to UUIDs internally.
Output: `{success, issue: {id, identifier, title, url}}`.

#### `linear-update-issue.sh`

```
Usage: linear-update-issue.sh <ISSUE-ID>
                               [--title TITLE]
                               [--description DESC]
                               [--project PROJECT_NAME]
                               [--priority 0-4]
                               [--assignee NAME_OR_EMAIL]
                               [--labels "Bug,Feature"]
                               [--parent ISSUE-ID]
                               [--profile NAME]
```

Only updates fields that are explicitly passed. Resolves names to UUIDs internally.
Output: `{success, issue: {id, identifier, title, url}}`.

#### `linear-create-project.sh`

```
Usage: linear-create-project.sh --name NAME
                                  [--team TEAM_NAME]
                                  [--description DESC]
                                  [--state backlog|planned|started|paused|completed|cancelled]
                                  [--profile NAME]
```

Defaults `--team` to profile's `default_team`. Default state: `backlog`.
Output: `{success, project: {id, name, state, url}}`.

#### `linear-update-project.sh`

```
Usage: linear-update-project.sh <PROJECT-ID>
                                  [--name NAME]
                                  [--description DESC]
                                  [--state STATE]
                                  [--profile NAME]
```

Accepts project name or UUID as first arg (resolves name → ID if needed).
Output: `{success, project: {id, name, state, url}}`.

#### `linear-comment.sh`

```
Usage: linear-comment.sh <ISSUE-ID> --body TEXT [--profile NAME]
```

Wraps existing `linear_add_comment()` library function as a standalone executable.
Output: `{success, comment: {id, body, createdAt}}`.

---

## Section 3: Library Extensions (`pipeline/linear.sh`)

New functions appended to the existing library. All follow the same conventions: positional args, optional `key_env` as last param defaulting to `LINEAR_API_KEY`, JSON output.

### Query Functions

| Function | Signature | Returns |
|----------|-----------|---------|
| `linear_list_teams` | `[key_env]` | Array of `{id, name, key}` |
| `linear_list_projects` | `[team_id] [key_env]` | Array of `{id, name, state, description, url}` |
| `linear_list_issues` | `[team_id] [project_id] [state] [assignee_id] [limit] [key_env]` | Array of `{id, identifier, title, priority, state, assignee, project, labels, url}` |

### Resolution Helpers

| Function | Signature | Returns |
|----------|-----------|---------|
| `linear_resolve_team_id` | `<name> [key_env]` | UUID string |
| `linear_resolve_project_id` | `<name> [team_id] [key_env]` | UUID string |
| `linear_resolve_member_id` | `<name_or_email> [key_env]` | UUID string |
| `linear_resolve_label_ids` | `<"L1,L2"> [team_id] [key_env]` | JSON array of UUIDs |

Resolution helpers output the UUID on stdout. On failure they write `{"error":"..."}` to stderr and return 1.

### Mutation Functions

| Function | Signature |
|----------|-----------|
| `linear_create_issue` | `<team_id> <title> [desc] [project_id] [priority] [assignee_id] [label_ids_json] [parent_id] [key_env]` |
| `linear_update_issue` | `<issue_id> [title] [desc] [project_id] [priority] [assignee_id] [label_ids_json] [parent_id] [key_env]` |
| `linear_create_project` | `<team_id> <name> [desc] [state] [key_env]` |
| `linear_update_project` | `<project_id> [name] [desc] [state] [key_env]` |

Scripts handle name→UUID resolution before calling mutation functions. Mutation functions only accept UUIDs.

---

## Section 4: Skills (`commands/`)

9 new command files following the existing minimal pattern. Each skill defines the agent's routine.

### Read Skills

**`linear-teams.md`** (`/houston:linear-teams`)
Run `linear-teams.sh`, display team names and keys as a table.

**`linear-projects.md`** (`/houston:linear-projects`)
Run `linear-projects.sh` (resolves `default_team` from profile if no `--team` given). Display project names, states, and URLs.

**`linear-issues.md`** (`/houston:linear-issues`)
Smart drill-down routine:
1. If `--project` not given, run `linear-projects.sh` first, present list, agent selects a project
2. Run `linear-issues.sh --project <uuid-from-projects-list>` with any other filters
3. Display identifier, title, state, assignee, priority

**`linear-get-issue.md`** (`/houston:linear-get-issue`)
Run `linear-get-issue.sh <ISSUE-ID>`. Display full issue card: title, description, state, assignee, priority, labels, project, parent/children, URL.

### Write Skills

**`linear-create-issue.md`** (`/houston:linear-create-issue`)
Routine: collect required fields (title; team from profile default) → confirm with user → run `linear-create-issue.sh` → display identifier and URL.

**`linear-update-issue.md`** (`/houston:linear-update-issue`)
Routine: run `linear-get-issue.sh` to show current state → confirm intended changes → run `linear-update-issue.sh` → display updated URL.

**`linear-create-project.md`** (`/houston:linear-create-project`)
Routine: collect name (team defaults from profile) → confirm → run `linear-create-project.sh` → display project URL.

**`linear-update-project.md`** (`/houston:linear-update-project`)
Routine: if no project ID given, run `linear-projects.sh` to pick one → confirm changes → run `linear-update-project.sh` → display updated URL.

**`linear-comment.md`** (`/houston:linear-comment`)
Run `linear-comment.sh <ISSUE-ID> --body TEXT`. Display confirmation with comment ID.

---

## File List

```
profiles/
  apex.toml                       new
  astra.toml                      new
  schema.toml                     updated (+type, +owners)

pipeline/
  linear.sh                       updated (+8 query/mutation/helper functions)

scripts/
  linear-teams.sh                 new
  linear-projects.sh              new
  linear-issues.sh                new
  linear-get-issue.sh             new
  linear-create-issue.sh          new
  linear-update-issue.sh          new
  linear-create-project.sh        new
  linear-update-project.sh        new
  linear-comment.sh               new

commands/
  linear-teams.md                 new
  linear-projects.md              new
  linear-issues.md                new
  linear-get-issue.md             new
  linear-create-issue.md          new
  linear-update-issue.md          new
  linear-create-project.md        new
  linear-update-project.md        new
  linear-comment.md               new
```

**Total: 2 profiles, 1 updated library, 9 scripts, 9 skills, 1 schema update.**

---

## Live API Validation

Tested against `LINEAR_API_KEY` (apex's key) on 2026-04-18:

- Org: **Skyner Group**
- Team: **Development** (key: `DEV`, id: `c442eb6e-...`)
- Members: `apex@skyner.co.za`, `astra@skyner.co.za`, `Yashiel Sookdeo`
- Labels: Bug, Feature, Improvement
- Projects: Couple Schedule, SkyStream, ContractSnap, SpazaBooks, StokvelManager, Skyner Mono, Signal Hub ZA (all `backlog`)
- `project.state` is a scalar string; `issue.state` is `{name}` object — library handles both correctly
