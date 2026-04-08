---
name: houston
description: Launch autonomous development pipelines across multiple contexts, orgs, and platforms.
argument-hint: "<TICKET-ID... | prompt | --spec path | --from-plan path | status | resume TICKET-ID>"
---

# Houston Pipeline Launcher

Parse `$ARGUMENTS` to determine mode and execute.

## Setup

- Houston directory: Find it via `HOUSTON_DIR` env var, or search common locations:
  - `~/.houston/repo`
  - `~/Developer/houston`
  - Look for a directory containing `pipeline/orchestrate.sh`

## Invocation Modes

### Mode: status (argument is "status")

Run `$HOUSTON_DIR/scripts/status.sh` and display the output.

### Mode: resume (argument starts with "resume")

Extract the ticket ID from arguments. Run `$HOUSTON_DIR/pipeline/resume.sh <ticket-id>` and display the output.

### Mode: From ticket ID (argument matches pattern like SWITCH-167, DEV-42, CARD-123)

Pattern: one or more uppercase letters, a dash, one or more digits. Can be multiple ticket IDs space-separated.

1. **Single ticket:**
   a. Use `$HOUSTON_DIR/pipeline/linear.sh` functions to look up the ticket via `linear_find_ticket`
   b. Get the ticket title, description, and branchName
   c. Detect which profile matches by checking which API key found the ticket
   d. Generate a spec from the ticket details using the spec template at `$HOUSTON_DIR/templates/spec-template.md`
   e. Ask 1-3 clarifying questions if the ticket description is vague
   f. Save spec to `~/.houston/runs/<TICKET-ID>/spec.md`
   g. Ask user to confirm: profile, mode (supervised/autonomous/human-assisted), and spec look correct
   h. Run `$HOUSTON_DIR/scripts/dispatch.sh <ticket-id> <repo-path> [mode] [--profile name]`
   i. Report the session name and how to monitor

2. **Multiple tickets:**
   a. Look up all tickets via `linear_find_ticket`
   b. Check for dependency relations between them (parent/child, blocks/blocked-by)
   c. Display the dependency graph
   d. Ask user to confirm
   e. Run `$HOUSTON_DIR/scripts/dispatch-multi.sh <repo-path> <ticket-ids...>`
   f. Report all sessions

### Mode: From prompt (no special flags, not a ticket ID)

1. Detect profile from current repo (run `$HOUSTON_DIR/pipeline/detect-context.sh`)
2. Ask 1-3 clarifying questions if the prompt is ambiguous
3. Generate spec using `$HOUSTON_DIR/templates/spec-template.md`
4. Create a Linear ticket in the profile's default team:
   - Use `linear_create_sub_issue` or direct creation
   - Get the branchName from the created ticket
5. Save spec to `~/.houston/runs/<TICKET-ID>/spec.md`
6. Ask user to confirm profile, mode, and spec
7. Dispatch

### Mode: From spec (argument starts with --spec)

1. Read the spec file at the provided path
2. Detect profile from current repo
3. Create Linear ticket
4. Save spec to run directory
5. Ask user to confirm
6. Dispatch

### Mode: From plan (argument starts with --from-plan)

1. Read the plan file
2. Detect profile from current repo
3. Create Linear ticket if needed
4. Save plan as spec (agent skips research, goes to implementation)
5. Ask user to confirm
6. Dispatch

## Profile Override

If the user says "use personal profile" or "use stitch profile", override auto-detection.

## Default Mode

Default pipeline mode is `supervised`. User can say "autonomous" or "run it autonomously" to change.

## Repo Path

Use the current working directory as the repo path unless the user specifies otherwise.

## Key Scripts (for agents in the pipeline)

These scripts are called by agents directly — no need to reimplement the logic:
- `$HOUSTON_DIR/scripts/create-pr.sh <TICKET-ID>` — Creates PR/MR with correct format, reviewers, squash, delete branch, auto-merge
- `$HOUSTON_DIR/pipeline/quality-gate.sh --scope story|phase|final --config <path>` — Runs quality gates
- `$HOUSTON_DIR/pipeline/detect-project.sh <path>` — Detects tech stack, outputs JSON

## Output After Dispatch

```
Pipeline launched for <TICKET-ID>
  Session: <ticket-id-lowercase>
  Profile: <profile-name>
  Mode:    <mode>
  Branch:  <branch-name>

Monitor: Run 'agent-deck' or 'tmux attach -t <session-name>'
Status:  Run '/houston status'
```
