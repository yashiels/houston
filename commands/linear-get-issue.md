---
description: "Fetch full details for a Linear issue"
argument-hint: "<ISSUE-ID> [--profile NAME]"
---

Run `$HOUSTON_DIR/scripts/linear-get-issue.sh $ARGUMENTS` and display the results.

Present as a structured card:
- Title, identifier, URL
- State, priority, assignee
- Project, labels
- Description (truncated to 500 chars if long)
- Parent / children if present

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
