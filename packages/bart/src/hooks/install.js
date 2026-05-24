import fs from 'fs';
import path from 'path';

/**
 * Install Claude Code hooks for code-enforced quality gates
 */
export async function installHooks(projectDir) {
  const claudeDir = path.join(projectDir, '.claude');
  const hooksDir = path.join(claudeDir, 'hooks');

  fs.mkdirSync(hooksDir, { recursive: true });

  // Write settings.json
  fs.writeFileSync(
    path.join(claudeDir, 'settings.json'),
    JSON.stringify(SETTINGS, null, 2)
  );

  // Write all hook scripts
  fs.writeFileSync(path.join(hooksDir, 'inject-rules.sh'), INJECT_RULES_SH);
  fs.writeFileSync(path.join(hooksDir, 'block-shortcuts.sh'), BLOCK_SHORTCUTS_SH);
  fs.writeFileSync(path.join(hooksDir, 'pre-commit-gate.sh'), PRE_COMMIT_GATE_SH);
  fs.writeFileSync(path.join(hooksDir, 'post-edit-tests.sh'), POST_EDIT_TESTS_SH);

  // Make executable
  fs.chmodSync(path.join(hooksDir, 'inject-rules.sh'), 0o755);
  fs.chmodSync(path.join(hooksDir, 'block-shortcuts.sh'), 0o755);
  fs.chmodSync(path.join(hooksDir, 'pre-commit-gate.sh'), 0o755);
  fs.chmodSync(path.join(hooksDir, 'post-edit-tests.sh'), 0o755);
}

const SETTINGS = {
  hooks: {
    SessionStart: [{
      matcher: '',
      hooks: [{
        type: 'command',
        command: '"$CLAUDE_PROJECT_DIR"/.claude/hooks/inject-rules.sh'
      }]
    }],
    PreToolUse: [{
      matcher: 'Bash',
      hooks: [
        {
          type: 'command',
          command: '"$CLAUDE_PROJECT_DIR"/.claude/hooks/block-shortcuts.sh'
        },
        {
          type: 'command',
          command: '"$CLAUDE_PROJECT_DIR"/.claude/hooks/pre-commit-gate.sh'
        }
      ]
    }],
    PostToolUse: [{
      matcher: 'Edit|Write',
      hooks: [{
        type: 'command',
        command: '"$CLAUDE_PROJECT_DIR"/.claude/hooks/post-edit-tests.sh'
      }]
    }],
    Stop: [{
      matcher: '',
      hooks: [{
        type: 'command',
        command: "echo '✅ Task complete. Run full test suite before committing.'"
      }]
    }]
  }
};

const INJECT_RULES_SH = `#!/bin/bash
# inject-rules.sh
# Re-injects critical rules on session start (survives compaction)

cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════╗
║                   🚨 BART RULES (NON-NEGOTIABLE) 🚨                    ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                        ║
║  1. GITHUB IS THE SOURCE OF TRUTH                                     ║
║     Every change: Code → Commit → Push → CI/CD → Deploy               ║
║     There is NO other path to production.                             ║
║                                                                        ║
║  2. TDD IS MANDATORY                                                   ║
║     RED → GREEN → REFACTOR                                            ║
║     Write failing test first, then implement.                         ║
║                                                                        ║
║  3. PRE-COMMIT TESTING (Enforced by hooks)                            ║
║     - Tests must pass BEFORE commit                                   ║
║     - Typecheck must pass BEFORE commit                               ║
║     - Build must pass BEFORE commit                                   ║
║     - CI/CD should NEVER see a failing test                          ║
║                                                                        ║
║  4. FORBIDDEN ACTIONS (Hooks will block these)                        ║
║     ⛔ SSH into servers                                               ║
║     ⛔ docker exec into containers                                    ║
║     ⛔ kubectl exec into pods                                         ║
║     ⛔ Force push to main/master                                      ║
║     ⛔ Skip CI flags                                                  ║
║     ⛔ Hardcode values to pass tests                                  ║
║     ⛔ Comment out failing tests                                      ║
║                                                                        ║
║  5. CONTEXT MANAGEMENT                                                 ║
║     - Read CLAUDE.md, AGENTS.md, ARCHITECTURE.md at start            ║
║     - Check .bart/progress.txt for learnings                          ║
║     - Check .bart/prd.json for your assigned story                   ║
║     - Keep context usage under 50%                                    ║
║                                                                        ║
╚══════════════════════════════════════════════════════════════════════╝

These rules are CODE-ENFORCED by hooks. You cannot bypass them.
EOF

exit 0
`;

const BLOCK_SHORTCUTS_SH = `#!/bin/bash
# block-shortcuts.sh
# Blocks commands that bypass proper CI/CD
# Exit 2 = block, Exit 0 = allow

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$COMMAND" ] && exit 0

# SSH into servers
if echo "$COMMAND" | grep -qE "^ssh\\s"; then
  echo "🚨 BLOCKED: SSH into servers is forbidden." >&2
  echo "Fix issues through code → commit → CI/CD → deploy" >&2
  exit 2
fi

# Docker exec
if echo "$COMMAND" | grep -qE "docker\\s+(exec|attach)"; then
  echo "🚨 BLOCKED: docker exec/attach is forbidden." >&2
  echo "Don't patch running containers. Fix in code." >&2
  exit 2
fi

# Kubectl exec
if echo "$COMMAND" | grep -qE "kubectl\\s+exec"; then
  echo "🚨 BLOCKED: kubectl exec is forbidden." >&2
  exit 2
fi

# Direct database mods in prod
if echo "$COMMAND" | grep -qE "(psql|mysql|mongo|redis-cli).*prod"; then
  echo "🚨 BLOCKED: Direct production database access is forbidden." >&2
  exit 2
fi

# Force push to main/master
if echo "$COMMAND" | grep -qE "git\\s+push.*(-f|--force).*(main|master)"; then
  echo "🚨 BLOCKED: Force push to main/master is forbidden." >&2
  exit 2
fi

# Direct push to main/master
if echo "$COMMAND" | grep -qE "git\\s+push\\s+(origin\\s+)?(main|master)$"; then
  echo "🚨 BLOCKED: Direct push to main/master is forbidden." >&2
  echo "Use a feature branch and PR workflow." >&2
  exit 2
fi

# Skip CI
if echo "$COMMAND" | grep -qE "\\[skip ci\\]|\\[ci skip\\]|--no-verify"; then
  echo "🚨 BLOCKED: Skipping CI is forbidden." >&2
  exit 2
fi

exit 0
`;

const PRE_COMMIT_GATE_SH = `#!/bin/bash
# pre-commit-gate.sh
# Blocks git commit if tests or typecheck fail
# Exit 2 = block, Exit 0 = allow

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept git commit
if ! echo "$COMMAND" | grep -qE "^git\\s+commit"; then
  exit 0
fi

echo "🔒 Pre-commit gate: Verifying before commit..." >&2

# Detect package manager
if [ -f "pnpm-lock.yaml" ]; then PKG="pnpm"
elif [ -f "yarn.lock" ]; then PKG="yarn"
elif [ -f "bun.lockb" ]; then PKG="bun"
else PKG="npm"; fi

# Typecheck if TypeScript
if [ -f "tsconfig.json" ]; then
  echo "📘 Running typecheck..." >&2
  if ! $PKG run typecheck 2>&1; then
    echo "❌ BLOCKED: Typecheck failed." >&2
    exit 2
  fi
  echo "✅ Typecheck passed" >&2
fi

# Run tests
if [ -f "package.json" ] && grep -q '"test"' package.json; then
  echo "🧪 Running tests..." >&2
  if ! $PKG test 2>&1; then
    echo "❌ BLOCKED: Tests failed." >&2
    exit 2
  fi
  echo "✅ Tests passed" >&2
fi

# Run build if exists
if [ -f "package.json" ] && grep -q '"build"' package.json; then
  echo "🏗️ Running build..." >&2
  if ! $PKG run build 2>&1; then
    echo "❌ BLOCKED: Build failed." >&2
    exit 2
  fi
  echo "✅ Build passed" >&2
fi

echo "✅ All pre-commit checks passed" >&2
exit 0
`;

const POST_EDIT_TESTS_SH = `#!/bin/bash
# post-edit-tests.sh
# Runs tests after file edits (informational, not blocking)

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Skip non-code files
if echo "$FILE_PATH" | grep -qE "\\.(md|txt|json|yaml|yml|toml|lock)$"; then
  exit 0
fi

# Skip test files
if echo "$FILE_PATH" | grep -qE "\\.(test|spec)\\.(ts|tsx|js|jsx)$"; then
  exit 0
fi

# Skip if no package.json
[ ! -f "package.json" ] && exit 0

# Detect package manager
if [ -f "pnpm-lock.yaml" ]; then PKG="pnpm"
elif [ -f "yarn.lock" ]; then PKG="yarn"
elif [ -f "bun.lockb" ]; then PKG="bun"
else PKG="npm"; fi

echo "🧪 Post-edit check after $FILE_PATH..." >&2

# Typecheck (quick feedback)
if [ -f "tsconfig.json" ]; then
  if ! $PKG run typecheck 2>&1 >/dev/null; then
    echo "⚠️ Typecheck failing after edit" >&2
  fi
fi

# Run related test or full suite
timeout 60 $PKG test 2>&1 || echo "⚠️ Some tests failing" >&2

exit 0
`;
