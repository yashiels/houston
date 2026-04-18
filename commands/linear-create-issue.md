---
description: "Create a new Linear issue"
argument-hint: "--title TITLE [--team NAME] [--description DESC] [--project NAME] [--priority 0-4] [--assignee NAME_OR_EMAIL] [--labels L1,L2] [--parent ISSUE-ID] [--profile NAME]"
---

Confirm the fields with the user before creating, then run:
`$HOUSTON_DIR/scripts/linear-create-issue.sh $ARGUMENTS`

On success, display the issue identifier and URL from the JSON response.

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
