---
description: "Update fields on an existing Linear issue"
argument-hint: "<ISSUE-ID> [--title TITLE] [--description DESC] [--project NAME] [--priority 0-4] [--assignee NAME_OR_EMAIL] [--labels L1,L2] [--parent ISSUE-ID] [--profile NAME]"
---

1. Run `$HOUSTON_DIR/scripts/linear-get-issue.sh <ISSUE-ID>` to show the current state.
2. Confirm the intended changes with the user.
3. Run `$HOUSTON_DIR/scripts/linear-update-issue.sh $ARGUMENTS`.

On success, display the updated issue URL.

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
