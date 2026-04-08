#!/usr/bin/env bats

# test_orchestrate.bats — Tests for the orchestrator state machine (pipeline/orchestrate.sh)

TICKET="TEST-ORCH"

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ORCHESTRATE="$REPO_ROOT/pipeline/orchestrate.sh"
  RUN_DIR="$HOME/.houston/runs/$TICKET"

  # Create a temp git repo with a remote
  TEMP_REPO="$(mktemp -d)"
  git init "$TEMP_REPO" >/dev/null 2>&1
  git -C "$TEMP_REPO" remote add origin git@github.com:stitch-Money/test.git 2>/dev/null || true
  # Create an initial commit so branch operations work
  touch "$TEMP_REPO/.gitkeep"
  git -C "$TEMP_REPO" add .gitkeep >/dev/null 2>&1
  git -C "$TEMP_REPO" commit -m "init" >/dev/null 2>&1

  # Create run directory and state.json
  mkdir -p "$RUN_DIR"
  cat > "$RUN_DIR/state.json" <<EOF
{
  "version": 1,
  "ticket_id": "$TICKET",
  "profile": "stitch",
  "repo_path": "$TEMP_REPO",
  "branch": "test-branch",
  "mode": "supervised",
  "platform": "github",
  "cli": "gh",
  "current_step": "init",
  "steps_completed": [],
  "created_at": "2026-04-08T12:00:00Z",
  "updated_at": "2026-04-08T12:00:00Z"
}
EOF

  # Create minimal context.json
  cat > "$RUN_DIR/context.json" <<EOF
{
  "profile": {"name": "stitch", "priority": 10},
  "identity": {"name": "Test", "email": "test@test.com", "git_user": "test"},
  "detected": {
    "platform": "github",
    "cli": "gh",
    "remote": "git@github.com:stitch-Money/test.git",
    "normalized": "github.com/stitch-money/test",
    "repo_path": "$TEMP_REPO"
  }
}
EOF

  # Create minimal project.json
  cat > "$RUN_DIR/project.json" <<EOF
{
  "lang": "node",
  "packageManager": "pnpm",
  "typescript": true,
  "testCmd": "pnpm test",
  "lintCmd": "pnpm lint",
  "buildCmd": "pnpm build"
}
EOF
}

teardown() {
  # Clean up run directory
  rm -rf "$HOME/.houston/runs/$TICKET"
  # Clean up temp repo
  if [[ -n "${TEMP_REPO:-}" && -d "${TEMP_REPO:-}" ]]; then
    rm -rf "$TEMP_REPO"
  fi
}

# Helper: set the current step and optionally the mode
set_state() {
  local step="$1"
  local mode="${2:-supervised}"
  local run_dir="$HOME/.houston/runs/$TICKET"
  jq --arg step "$step" --arg mode "$mode" \
    '.current_step = $step | .mode = $mode' \
    "$run_dir/state.json" > "$run_dir/state.tmp" && mv "$run_dir/state.tmp" "$run_dir/state.json"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "status shows current state" {
  run "$ORCHESTRATE" status "$TICKET"
  [ "$status" -eq 0 ]
  action="$(echo "$output" | jq -r '.action')"
  tid="$(echo "$output" | jq -r '.ticket_id')"
  [ "$action" = "status" ]
  [ "$tid" = "$TICKET" ]
}

@test "next from init auto-advances through mechanical steps" {
  run "$ORCHESTRATE" next "$TICKET"
  [ "$status" -eq 0 ]
  action="$(echo "$output" | jq -r '.action')"
  step="$(echo "$output" | jq -r '.step')"
  [ "$action" = "spawn" ]
  [ "$step" = "RESEARCH" ]
}

@test "complete RESEARCH advances to GRILL-RESEARCH" {
  set_state "RESEARCH"
  run "$ORCHESTRATE" complete "$TICKET" RESEARCH
  [ "$status" -eq 0 ]
  action="$(echo "$output" | jq -r '.action')"
  step="$(echo "$output" | jq -r '.step')"
  [ "$action" = "spawn" ]
  [ "$step" = "GRILL-RESEARCH" ]
}

@test "complete GRILL-RESEARCH hits gate in supervised mode" {
  set_state "GRILL-RESEARCH"
  run "$ORCHESTRATE" complete "$TICKET" GRILL-RESEARCH
  [ "$status" -eq 0 ]
  action="$(echo "$output" | jq -r '.action')"
  step="$(echo "$output" | jq -r '.step')"
  [ "$action" = "gate" ]
  [ "$step" = "research-review" ]
}

@test "autonomous mode skips gates" {
  set_state "GRILL-RESEARCH" "autonomous"
  run "$ORCHESTRATE" complete "$TICKET" GRILL-RESEARCH
  [ "$status" -eq 0 ]
  action="$(echo "$output" | jq -r '.action')"
  step="$(echo "$output" | jq -r '.step')"
  [ "$action" = "spawn" ]
  [ "$step" = "PLAN" ]
}

@test "gate-response CONTINUE advances past gate" {
  set_state "research-review"
  run "$ORCHESTRATE" gate-response "$TICKET" CONTINUE
  [ "$status" -eq 0 ]
  action="$(echo "$output" | jq -r '.action')"
  step="$(echo "$output" | jq -r '.step')"
  [ "$action" = "spawn" ]
  [ "$step" = "PLAN" ]
}

@test "gate-response STOP blocks pipeline" {
  set_state "research-review"
  run "$ORCHESTRATE" gate-response "$TICKET" STOP
  [ "$status" -eq 0 ]
  action="$(echo "$output" | jq -r '.action')"
  [ "$action" = "blocked" ]
}

@test "nonexistent ticket returns error" {
  run "$ORCHESTRATE" status NONEXISTENT
  # Either non-zero exit or action=error in output
  if [ "$status" -eq 0 ]; then
    action="$(echo "$output" | jq -r '.action')"
    [ "$action" = "error" ]
  fi
}
