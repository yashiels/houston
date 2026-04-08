# PR/MR Comment Reply Guidelines

## Rules

1. **Always reply in-thread.** Never post standalone comments in response to review feedback.
2. **Fix first, reply second.** Make the code change, then reply with what you changed.
3. **Be specific.** "Fixed" is not enough. Say what you changed and why.
4. **Don't argue.** If you disagree with feedback, explain your reasoning briefly. If the reviewer insists, defer.

## Reply Format

### For actionable feedback (you'll fix it):
```
Fixed — [what you changed]. [one sentence why this is better]
```

### For feedback you've already addressed:
```
Already handled in [commit hash] — [brief description]
```

### For feedback you disagree with:
```
I kept [current approach] because [reason]. Happy to change if you prefer [alternative].
```

### For questions:
```
[Direct answer]. [Additional context if helpful]
```

## Platform Commands

### GitHub
```bash
gh pr comment <PR-NUMBER> --body "reply text"
# For review comments, use the API:
gh api repos/OWNER/REPO/pulls/PR/comments/COMMENT_ID/replies -f body="reply"
```

### GitLab
```bash
glab mr note <MR-ID> --message "reply text"
# For discussion threads:
glab api projects/ID/merge_requests/MR/discussions/DISC_ID/notes -f body="reply"
```
