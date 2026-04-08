#!/usr/bin/env bats

# test_dispatch.bats — Tests for dispatch and status scripts

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Create a temp git repo with a remote for profile detection
  TEST_REPO="$(mktemp -d)"
  cd "$TEST_REPO"
  git init -q
  git remote add origin git@github.com:stitch-Money/test-service.git
}

teardown() {
  rm -rf "$TEST_REPO"
  rm -rf "$HOME/.houston/runs/TEST-DISPATCH-"*
}

# ---------------------------------------------------------------------------
# status.sh tests
# ---------------------------------------------------------------------------

@test "status shows no pipelines when none exist" {
  # Ensure no runs directory for this test
  rm -rf "$HOME/.houston/runs/TEST-DISPATCH-"*
  run "$REPO_ROOT/scripts/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No active pipelines"* ]] || [[ "$output" == *"pipeline"* ]]
}

@test "status shows existing pipeline" {
  mkdir -p "$HOME/.houston/runs/TEST-DISPATCH-001"
  cat > "$HOME/.houston/runs/TEST-DISPATCH-001/state.json" <<'EOF'
{
  "version": 1,
  "ticket_id": "TEST-DISPATCH-001",
  "profile": "stitch",
  "repo_path": "/tmp/test",
  "branch": "feat/test-dispatch-001",
  "mode": "supervised",
  "current_step": "RESEARCH",
  "steps_completed": ["init"],
  "created_at": "2026-04-08T12:00:00Z",
  "updated_at": "2026-04-08T12:00:00Z"
}
EOF
  run "$REPO_ROOT/scripts/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST-DISPATCH-001"* ]]
}

# ---------------------------------------------------------------------------
# dispatch.sh tests
# ---------------------------------------------------------------------------

@test "dispatch fails without agent-deck" {
  if command -v agent-deck &>/dev/null; then
    skip "agent-deck is installed — cannot test missing-tool path"
  fi
  run "$REPO_ROOT/scripts/dispatch.sh" "TEST-123" "$TEST_REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"agent-deck"* ]]
}

# ---------------------------------------------------------------------------
# dispatch-multi.sh tests
# ---------------------------------------------------------------------------

@test "dispatch-multi requires repo path" {
  run "$REPO_ROOT/scripts/dispatch-multi.sh"
  [ "$status" -ne 0 ]
}
