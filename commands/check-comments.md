---
description: "Fetch unresolved PR/MR review comments as JSON"
argument-hint: "[--pr <number>] [--branch <name>]"
---

Run `$HOUSTON_DIR/scripts/check-comments.sh $ARGUMENTS` and display the actionable comments.

If there are actionable comments, summarize each one: who said it, what file/line, what they want.

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
