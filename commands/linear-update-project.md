---
description: "Update an existing Linear project"
argument-hint: "<PROJECT-ID-OR-NAME> [--name NAME] [--description DESC] [--state STATE] [--profile NAME]"
---

If no project is specified:
1. Run `$HOUSTON_DIR/scripts/linear-projects.sh` to list available projects.
2. Present the list and ask the user to select one.
3. Run `$HOUSTON_DIR/scripts/linear-update-project.sh <selected-id> $ARGUMENTS`.

If a project name or ID is provided, run `$HOUSTON_DIR/scripts/linear-update-project.sh $ARGUMENTS` directly.

On success, display the updated project URL.

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
