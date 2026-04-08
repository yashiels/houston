---
name: houston
description: Multi-context autonomous development orchestrator. Dispatches pipelines across orgs, Linear workspaces, and platforms via agent-deck.
---

# Houston

Autonomous development pipeline orchestrator for Claude Code.

## Skills

- `/houston <TICKET-ID | prompt | --spec path | --from-plan path>` — Launch a development pipeline
- `/houston status` — Show running pipelines
- `/houston resume <TICKET-ID>` — Resume a failed pipeline

## Profiles

Houston uses TOML profiles in `profiles/` to define development contexts. Each profile maps to a git identity, Linear workspace, platform orgs, and reviewer list. Auto-detected from git remote.

## Pipeline

Research → Plan → Code (TDD, phased) → Review → PR → CI Monitor

Each stage is a disposable Claude session. State persists to `~/.houston/runs/`.
