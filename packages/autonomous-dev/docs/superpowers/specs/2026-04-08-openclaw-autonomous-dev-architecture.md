# OpenClaw + Autonomous-Dev Architecture

**Date:** 2026-04-08
**Status:** Approved
**Author:** Yashiel Sookdeo

## Problem

The autonomous-dev pipeline running through OpenClaw Discord has multiple architectural failures:

1. Heartbeat bleeds into Discord thread sessions, injecting BOOT.md into pipeline conversations
2. ACP sessions spawn on threads but ACP is globally disabled, causing permission errors
3. Context pruning (cache-ttl 1h) destroys pipeline state, causing 207x init replay
4. GLM models can't reliably construct complex Claude Code CLI commands
5. quality-gate.sh uses relative paths that don't resolve in project repos
6. Cron jobs hit OpenRouter free-tier rate limits, cascade to expensive fallbacks
7. No bash-level pipeline driver — LLM was driving the orchestrate.sh loop and hallucinating

## Architecture

### Layer Model

```
YOU (Discord)
  Chat, trigger pipelines, review gates
    |
Tashmia (GLM-4.7) — Chat & Relay
  Reads messages, kicks off pipelines, relays status.
  Never writes code. Never drives the pipeline loop.
    |
run-pipeline.sh (Bash) — Pipeline Driver
  Calls orchestrate.sh next/complete in a while loop.
  Dispatches spawns, handles timeouts, notifies via openclaw system event.
  No LLM. Cannot hallucinate. Cannot loop.
    |
spawn-coder.sh → Claude Code (Sonnet/Opus) — Coding
  Implements stories, writes tests, commits.
  Anthropic OAuth. Full tool suite (Edit, Glob, Grep).
    |
orchestrate.sh — State Machine
  Source of truth. Never advances without explicit complete.
  Crash recovery = resume from state.json.
```

### Model Routing

| Role | Model | Cost | Why |
|------|-------|------|-----|
| Chat (Tashmia) | zai/glm-4.7 | $0.39/$1.75 | Cheap, reliable for messages. No tool-calling complexity. |
| Heartbeat | google-vertex/gemini-2.5-flash | $0.50/$3.00 | Light, isolated, runs every 5m |
| Pipeline driver | Bash (no model) | $0 | Cannot hallucinate |
| Coder | claude-sonnet-4-6 (via Claude Code) | $3/$15 | Reliable tool calling, Anthropic OAuth |
| Coder (premium) | claude-opus-4-6 (via Claude Code) | $5/$25 | Complex stories |
| Cron (email digests) | zai/glm-4.5-flash | $0/$0 | Free, no rate limits |
| Cron (briefing/scans) | zai/glm-4.7-flash | $0.07/$0.40 | Cheap, reasoning-capable |

### Session Architecture

| Session Type | Scope | Reset | Pruning |
|-------------|-------|-------|---------|
| Main (heartbeat) | agent:main:main | Isolated, no thread bleed | Off |
| Discord channels | Per-channel | Idle 2h | Off |
| Discord threads | Per-thread, isolated | Idle 30d | Off |
| Cron jobs | Isolated per-run | Per-run | N/A |
| Subagent spawns | Stateless (LCM skip) | Per-run | N/A |

### Heartbeat Isolation

Heartbeat runs in an isolated session with no delivery target. It never enters thread sessions.

```json
{
  "every": "5m",
  "model": "google-vertex/gemini-2.5-flash",
  "session": "main",
  "isolatedSession": true,
  "target": "none",
  "lightContext": true,
  "activeHours": {
    "start": "07:00",
    "end": "23:00",
    "timezone": "Africa/Johannesburg"
  }
}
```

### Pipeline Flow

1. User says in Discord thread: "build this PRD"
2. Tashmia runs: `run-pipeline.sh /path/to/project --mode autonomous --preset balanced`
3. run-pipeline.sh loops:
   - `orchestrate.sh resume` + `verify-state`
   - `orchestrate.sh next` → parse JSON action
   - For `spawn` (story-execute): `spawn-coder.sh STORY-XXX /path` → Claude Code
   - For `spawn` (reviewer/research): Claude Code with resolved template
   - For `run`: execute commands from worktree
   - For `ask`/`gate`: pause (exit 2), write pending-gate.json, notify Discord
   - For `blocked`/`error`: notify and stop
   - For `complete`: report PR URL
   - `orchestrate.sh complete <step>` after each action
4. Notifications via `openclaw system event` → Tashmia relays to Discord
5. Gates: Tashmia prompts user in Discord, user responds, Tashmia restarts runner

### Exit Codes (run-pipeline.sh)

| Code | Meaning | Tashmia Action |
|------|---------|----------------|
| 0 | Pipeline complete | Report PR URL |
| 1 | Fatal error | Report error, investigate |
| 2 | Paused for human input | Relay gate prompt, wait for reply, restart runner |

### Quality Gate Path Resolution

Templates use `__PIPELINE_DIR__/scripts/quality-gate.sh` instead of `./scripts/quality-gate.sh`. The `__PIPELINE_DIR__` placeholder is resolved alongside `__PROJECT_PATH__`, `__CO_AUTHOR__`, and `__BRANCH_NAME__` during template substitution.

### Lossless-Claw Tuning

```json
{
  "freshTailCount": 64,
  "contextThreshold": 0.75,
  "incrementalMaxDepth": 1,
  "customInstructions": "When summarizing pipeline sessions, preserve: current phase, step name, last command executed, pending verification items."
}
```

## Config Changes Summary

| Setting | Before | After |
|---------|--------|-------|
| heartbeat.isolatedSession | not set | true |
| heartbeat.session | not set | "main" |
| heartbeat.target | not set | "none" |
| heartbeat.activeHours | not set | 07:00-23:00 SAST |
| heartbeat.lightContext | not set | true |
| threadBindings.spawnAcpSessions | true | false |
| contextPruning.mode | "cache-ttl" | "off" |
| session.reset.mode | daily (default) | "idle" |
| session.resetByType.thread | not set | idle 43200min (30d) |
| session.resetByType.direct | not set | idle 60min |
| session.resetByType.group | not set | idle 120min |
| lossless-claw.freshTailCount | 32 | 64 |
| lossless-claw.incrementalMaxDepth | -1 | 1 |
| plugins.allow | not set | ["lossless-claw"] |
| cron models | openrouter/free | zai/glm-4.5-flash or glm-4.7-flash |

## Scripts

| Script | Purpose | Exists |
|--------|---------|--------|
| run-pipeline.sh | Bash loop driver | New |
| spawn-coder.sh | Claude Code story spawner | Exists |
| coder-status.sh | Running coder checker | Exists |
| orchestrate.sh | State machine | Exists (line 829 fix needed) |
| quality-gate.sh | Quality gates | Exists (path references need fixing) |
