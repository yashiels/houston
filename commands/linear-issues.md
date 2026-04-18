---
description: "List Linear issues with optional filters"
argument-hint: "[--project NAME_OR_UUID] [--team NAME] [--state STATE] [--assignee NAME_OR_EMAIL] [--limit N] [--profile NAME]"
---

If `--project` is not given:
1. Run `$HOUSTON_DIR/scripts/linear-projects.sh` to list available projects.
2. Present the list and ask the user to select one.
3. Run `$HOUSTON_DIR/scripts/linear-issues.sh --project <uuid-from-step-2> $ARGUMENTS`.

If `--project` is given, run `$HOUSTON_DIR/scripts/linear-issues.sh $ARGUMENTS` directly.

Present issues as a table: identifier, title, state, assignee, priority label (none/urgent/high/medium/low).

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
