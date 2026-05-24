# Autonomous Dev Hooks

Claude Code hooks that enforce the autonomous development pipeline rules.

## What's Included

| Hook | Trigger | Purpose |
|------|---------|---------|
| `inject-rules.sh` | SessionStart | Re-injects core rules after context compaction |
| `block-shortcuts.sh` | PreToolUse | Blocks ssh, docker exec, kubectl exec, force push, --no-verify |
| `pre-commit-gate.sh` | PreToolUse (git commit) | Blocks commits if tests haven't passed recently |
| `post-edit-tests.sh` | PostToolUse (Edit/Write) | Runs relevant tests after source file edits |
| `pipeline-guard.sh` | PreToolUse (Edit/Write) | Blocks source edits without an active pipeline |

## Installation

```bash
# Copy hooks to your project
cp -r hooks/.claude/ /path/to/your/project/.claude/

# Make all hook scripts executable
chmod +x /path/to/your/project/.claude/hooks/*.sh
```

## Configuration

The hooks are configured via `.claude/settings.json`. After copying, the hooks will be active for all Claude Code sessions in your project.

### Customization

- **Disable a hook**: Remove its entry from `settings.json`
- **Adjust timeouts**: Change the `timeout` value (in milliseconds)
- **Add Qdrant-first enforcement**: Uncomment the relevant line in `inject-rules.sh`

## Requirements

- Claude Code with hooks support
- `python3` (for JSON parsing in hook scripts)
- `jq` (for project detection)
- Project-specific test runner (npm/pnpm/yarn/pytest/go/cargo/etc.)

## How It Works

1. **SessionStart**: `inject-rules.sh` prints core rules to stdout, which Claude Code includes in context
2. **PreToolUse**: Before any tool call, `block-shortcuts.sh` checks for forbidden commands and `pipeline-guard.sh` verifies an active pipeline exists
3. **PostToolUse**: After Edit/Write, `post-edit-tests.sh` finds and runs relevant tests
4. **Pre-commit**: Before `git commit`, `pre-commit-gate.sh` checks for a recent test pass marker
