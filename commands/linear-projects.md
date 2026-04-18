---
description: "List Linear projects in a team"
argument-hint: "[--team TEAM_NAME] [--profile NAME]"
---

Run `$HOUSTON_DIR/scripts/linear-projects.sh $ARGUMENTS` and display the results.

If no `--team` is given, the script uses the default team from the active profile.

Present projects as a list: name, state, and URL.

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
