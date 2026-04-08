#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$REPO_ROOT/tests/fixtures"
  TEST_PROJECT="$(mktemp -d)"

  # Create a minimal project config
  cat > "$TEST_PROJECT/project.json" << 'EOF'
{
  "lang": "node",
  "packageManager": "npm",
  "testCmd": "echo TESTS_PASS",
  "testCmdRoot": "echo TESTS_PASS",
  "typecheckCmd": "echo TYPECHECK_PASS",
  "typecheckCmdRoot": "echo TYPECHECK_PASS",
  "buildCmd": "echo BUILD_PASS",
  "lintCmd": "echo LINT_PASS",
  "e2eCmd": "",
  "monorepo": false,
  "docker": false,
  "dockerBuildCmd": "",
  "typescript": true,
  "skipTestPattern": "",
  "testFilePattern": "*.test.*"
}
EOF

  # Init git repo so anti-pattern scan can work
  cd "$TEST_PROJECT"
  git init -q
  git -c user.email="test@test.com" -c user.name="Test" commit --allow-empty -m "init" -q
}

teardown() {
  rm -rf "$TEST_PROJECT"
}

@test "quality gate story scope passes with good config" {
  run bash "$REPO_ROOT/pipeline/quality-gate.sh" \
    --scope story \
    --config "$TEST_PROJECT/project.json" \
    --project-dir "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "quality gate phase scope passes" {
  run bash "$REPO_ROOT/pipeline/quality-gate.sh" \
    --scope phase \
    --config "$TEST_PROJECT/project.json" \
    --project-dir "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "quality gate final scope passes" {
  run bash "$REPO_ROOT/pipeline/quality-gate.sh" \
    --scope final \
    --config "$TEST_PROJECT/project.json" \
    --project-dir "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "quality gate fails on test failure" {
  cat > "$TEST_PROJECT/project-fail.json" << 'EOF'
{
  "lang": "node",
  "packageManager": "npm",
  "testCmd": "exit 1",
  "testCmdRoot": "exit 1",
  "typecheckCmd": "echo TYPECHECK_PASS",
  "typecheckCmdRoot": "echo TYPECHECK_PASS",
  "buildCmd": "",
  "lintCmd": "",
  "e2eCmd": "",
  "monorepo": false,
  "docker": false,
  "dockerBuildCmd": "",
  "typescript": true,
  "skipTestPattern": "",
  "testFilePattern": "*.test.*"
}
EOF
  run bash "$REPO_ROOT/pipeline/quality-gate.sh" \
    --scope story \
    --config "$TEST_PROJECT/project-fail.json" \
    --project-dir "$TEST_PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "quality gate skips unconfigured commands" {
  cat > "$TEST_PROJECT/project-nobuild.json" << 'EOF'
{
  "lang": "node",
  "packageManager": "npm",
  "testCmd": "echo TESTS_PASS",
  "testCmdRoot": "echo TESTS_PASS",
  "typecheckCmd": "echo TYPECHECK_PASS",
  "typecheckCmdRoot": "echo TYPECHECK_PASS",
  "buildCmd": "",
  "lintCmd": "echo LINT_PASS",
  "e2eCmd": "",
  "monorepo": false,
  "docker": false,
  "dockerBuildCmd": "",
  "typescript": true,
  "skipTestPattern": "",
  "testFilePattern": "*.test.*"
}
EOF
  run bash "$REPO_ROOT/pipeline/quality-gate.sh" \
    --scope phase \
    --config "$TEST_PROJECT/project-nobuild.json" \
    --project-dir "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP [build]"* ]]
}

@test "baseline capture creates file" {
  # Need a failing gate so baseline file gets created
  cat > "$TEST_PROJECT/project-baseline.json" << 'EOF'
{
  "lang": "node",
  "packageManager": "npm",
  "testCmd": "exit 1",
  "testCmdRoot": "exit 1",
  "typecheckCmd": "echo TYPECHECK_PASS",
  "typecheckCmdRoot": "echo TYPECHECK_PASS",
  "buildCmd": "echo BUILD_PASS",
  "lintCmd": "echo LINT_PASS",
  "e2eCmd": "",
  "monorepo": false,
  "docker": false,
  "dockerBuildCmd": "",
  "typescript": true,
  "skipTestPattern": "",
  "testFilePattern": "*.test.*"
}
EOF
  run bash "$REPO_ROOT/pipeline/quality-gate.sh" \
    --scope phase \
    --baseline capture \
    --config "$TEST_PROJECT/project-baseline.json" \
    --project-dir "$TEST_PROJECT"
  # Script exits non-zero due to failures, but baseline file should still exist
  [ -f "$TEST_PROJECT/.baseline-failures.txt" ]
}

@test "invalid scope fails" {
  run bash "$REPO_ROOT/pipeline/quality-gate.sh" \
    --scope invalid \
    --config "$TEST_PROJECT/project.json" \
    --project-dir "$TEST_PROJECT"
  [ "$status" -ne 0 ]
}
