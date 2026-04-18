---
description: "Create a new Linear project"
argument-hint: "--name NAME [--team TEAM_NAME] [--description DESC] [--state STATE] [--profile NAME]"
---

Confirm the project name and team with the user, then run:
`$HOUSTON_DIR/scripts/linear-create-project.sh $ARGUMENTS`

On success, display the project name and URL from the JSON response.

If `HOUSTON_DIR` is not set, try `~/Developer/houston`.
