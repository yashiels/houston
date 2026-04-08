#!/usr/bin/env bash
# detect-project.sh — Detect a project's tech stack and output JSON.
# Identifies language, package manager, test/build/lint commands, monorepo
# and Docker support. Supports 13+ languages/frameworks.
#
# Usage: ./pipeline/detect-project.sh [project-path]
#   project-path — path to the project root (default: current directory)

set -euo pipefail

# --- Arguments ---
PROJECT_PATH="${1:-.}"
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

# --- Defaults ---
LANG="unknown"
PACKAGE_MANAGER=""
INSTALL_CMD=""
TEST_CMD=""
TEST_CMD_ROOT=""
TYPECHECK_CMD=""
TYPECHECK_CMD_ROOT=""
BUILD_CMD=""
LINT_CMD=""
E2E_CMD=""
MONOREPO=false
DOCKER=false
DOCKER_BUILD_CMD=""
TYPESCRIPT=false
TSCONFIG=""
LOCKFILE_PATTERN=""
SKIP_TEST_PATTERN=""
TEST_FILE_PATTERN=""

# --- Helper: check if file exists in project ---
has_file() {
  [[ -f "${PROJECT_PATH}/$1" ]]
}

# --- Helper: read a package.json script field (returns empty if missing) ---
pkg_script() {
  local field="$1"
  if command -v jq &>/dev/null && has_file "package.json"; then
    jq -r ".scripts[\"${field}\"] // empty" "${PROJECT_PATH}/package.json" 2>/dev/null || true
  fi
}

# --- TypeScript detection (within 3 levels) ---
detect_typescript() {
  if has_file "tsconfig.json"; then
    TYPESCRIPT=true
    TSCONFIG="tsconfig.json"
    return
  fi
  # Search up to 3 levels deep
  local found
  found="$(find "$PROJECT_PATH" -maxdepth 3 -name "tsconfig.json" -type f 2>/dev/null | head -1)"
  if [[ -n "$found" ]]; then
    TYPESCRIPT=true
    # Make path relative to project
    TSCONFIG="${found#"${PROJECT_PATH}/"}"
  fi
}

# --- Monorepo detection ---
detect_monorepo() {
  if has_file "pnpm-workspace.yaml"; then
    MONOREPO=true; return
  fi
  if has_file "lerna.json"; then
    MONOREPO=true; return
  fi
  if has_file "nx.json"; then
    MONOREPO=true; return
  fi
  if has_file "turbo.json"; then
    MONOREPO=true; return
  fi
  # Check for workspaces in package.json
  if has_file "package.json" && command -v jq &>/dev/null; then
    local ws
    ws="$(jq -r '.workspaces // empty' "${PROJECT_PATH}/package.json" 2>/dev/null || true)"
    if [[ -n "$ws" && "$ws" != "null" ]]; then
      MONOREPO=true
    fi
  fi
}

# --- Docker detection ---
detect_docker() {
  if has_file "docker-compose.yml" || has_file "docker-compose.yaml" || \
     has_file "compose.yml" || has_file "compose.yaml" || has_file "Dockerfile"; then
    DOCKER=true
    if has_file "docker-compose.yml"; then
      DOCKER_BUILD_CMD="docker compose -f docker-compose.yml up --build"
    elif has_file "docker-compose.yaml"; then
      DOCKER_BUILD_CMD="docker compose -f docker-compose.yaml up --build"
    elif has_file "compose.yml"; then
      DOCKER_BUILD_CMD="docker compose up --build"
    elif has_file "compose.yaml"; then
      DOCKER_BUILD_CMD="docker compose up --build"
    elif has_file "Dockerfile"; then
      DOCKER_BUILD_CMD="docker build ."
    fi
  fi
}

# --- Node.js detection ---
detect_node() {
  has_file "package.json" || return 1
  LANG="node"

  # Detect package manager from lockfiles
  if has_file "pnpm-lock.yaml"; then
    PACKAGE_MANAGER="pnpm"
    LOCKFILE_PATTERN=$'pnpm-lock\\.yaml'
  elif has_file "bun.lockb" || has_file "bun.lock"; then
    PACKAGE_MANAGER="bun"
    LOCKFILE_PATTERN=$'bun\\.lockb|bun\\.lock'
  elif has_file "yarn.lock"; then
    PACKAGE_MANAGER="yarn"
    LOCKFILE_PATTERN=$'yarn\\.lock'
  else
    PACKAGE_MANAGER="npm"
    LOCKFILE_PATTERN=$'package-lock\\.json'
  fi

  INSTALL_CMD="${PACKAGE_MANAGER} install"

  # Set default commands
  TEST_CMD="${PACKAGE_MANAGER} test"
  BUILD_CMD="${PACKAGE_MANAGER} run build"
  LINT_CMD="${PACKAGE_MANAGER} run lint"

  # Root commands for monorepos
  if [[ "$PACKAGE_MANAGER" == "pnpm" ]]; then
    TEST_CMD_ROOT="pnpm -r test"
  elif [[ "$PACKAGE_MANAGER" == "yarn" ]]; then
    TEST_CMD_ROOT="yarn workspaces run test"
  elif [[ "$PACKAGE_MANAGER" == "npm" ]]; then
    TEST_CMD_ROOT="npm run test --workspaces"
  elif [[ "$PACKAGE_MANAGER" == "bun" ]]; then
    TEST_CMD_ROOT="bun test"
  fi

  # TypeScript support
  detect_typescript
  if $TYPESCRIPT; then
    TYPECHECK_CMD="${PACKAGE_MANAGER} exec tsc --noEmit"
    if [[ "$PACKAGE_MANAGER" == "pnpm" ]]; then
      TYPECHECK_CMD_ROOT="pnpm -r exec tsc --noEmit"
    elif [[ "$PACKAGE_MANAGER" == "npm" ]]; then
      TYPECHECK_CMD="npx tsc --noEmit"
      TYPECHECK_CMD_ROOT="npm exec --workspaces -- tsc --noEmit"
    elif [[ "$PACKAGE_MANAGER" == "yarn" ]]; then
      TYPECHECK_CMD_ROOT="yarn workspaces run tsc --noEmit"
    elif [[ "$PACKAGE_MANAGER" == "bun" ]]; then
      TYPECHECK_CMD="bun x tsc --noEmit"
      TYPECHECK_CMD_ROOT="bun x tsc --noEmit"
    fi
  fi

  # Override from package.json scripts (only set if script exists)
  local s_test s_build s_lint s_typecheck s_e2e
  s_test="$(pkg_script "test")"
  s_build="$(pkg_script "build")"
  s_lint="$(pkg_script "lint")"
  s_typecheck="$(pkg_script "typecheck")"
  s_e2e="$(pkg_script "test:e2e")"

  if [[ -n "$s_test" ]]; then
    TEST_CMD="${PACKAGE_MANAGER} test"
  else
    TEST_CMD=""
    TEST_CMD_ROOT=""
  fi

  if [[ -n "$s_build" ]]; then
    BUILD_CMD="${PACKAGE_MANAGER} run build"
  else
    BUILD_CMD=""
  fi

  if [[ -n "$s_lint" ]]; then
    LINT_CMD="${PACKAGE_MANAGER} run lint"
  else
    LINT_CMD=""
  fi

  if [[ -n "$s_typecheck" ]]; then
    TYPECHECK_CMD="${PACKAGE_MANAGER} run typecheck"
    if [[ "$PACKAGE_MANAGER" == "pnpm" ]]; then
      TYPECHECK_CMD_ROOT="pnpm -r run typecheck"
    fi
  elif ! $TYPESCRIPT; then
    TYPECHECK_CMD=""
    TYPECHECK_CMD_ROOT=""
  fi

  if [[ -n "$s_e2e" ]]; then
    E2E_CMD="${PACKAGE_MANAGER} run test:e2e"
  fi

  # Test file patterns
  SKIP_TEST_PATTERN=$'\\.skip\\(|\\.only\\(|xit\\(|xdescribe\\(|fdescribe\\(|fit\\('
  TEST_FILE_PATTERN="*.test.*"

  return 0
}

# --- Python detection ---
detect_python() {
  has_file "pyproject.toml" || has_file "setup.py" || has_file "requirements.txt" || return 1
  LANG="python"

  if has_file "poetry.lock"; then
    PACKAGE_MANAGER="poetry"
    INSTALL_CMD="poetry install"
    TEST_CMD="poetry run pytest"
    BUILD_CMD="poetry build"
    LINT_CMD="poetry run ruff check ."
    LOCKFILE_PATTERN=$'poetry\\.lock'
  elif has_file "uv.lock"; then
    PACKAGE_MANAGER="uv"
    INSTALL_CMD="uv sync"
    TEST_CMD="uv run pytest"
    BUILD_CMD="uv build"
    LINT_CMD="uv run ruff check ."
    LOCKFILE_PATTERN=$'uv\\.lock'
  elif has_file "Pipfile.lock"; then
    PACKAGE_MANAGER="pipenv"
    INSTALL_CMD="pipenv install"
    TEST_CMD="pipenv run pytest"
    BUILD_CMD=""
    LINT_CMD="pipenv run ruff check ."
    LOCKFILE_PATTERN=$'Pipfile\\.lock'
  else
    PACKAGE_MANAGER="pip"
    INSTALL_CMD="pip install -r requirements.txt"
    TEST_CMD="pytest"
    BUILD_CMD=""
    LINT_CMD="ruff check ."
    LOCKFILE_PATTERN=$'requirements\\.txt'
  fi

  SKIP_TEST_PATTERN=$'@pytest\\.mark\\.skip|pytest\\.skip|@unittest\\.skip'
  TEST_FILE_PATTERN="test_*.py"

  return 0
}

# --- Go detection ---
detect_go() {
  has_file "go.mod" || return 1
  LANG="go"
  PACKAGE_MANAGER="go"
  INSTALL_CMD="go mod download"
  TEST_CMD="go test ./..."
  BUILD_CMD="go build ./..."
  LINT_CMD="golangci-lint run"
  LOCKFILE_PATTERN=$'go\\.sum'
  SKIP_TEST_PATTERN=$'t\\.Skip|testing\\.Short'
  TEST_FILE_PATTERN="*_test.go"
  return 0
}

# --- Rust detection ---
detect_rust() {
  has_file "Cargo.toml" || return 1
  LANG="rust"
  PACKAGE_MANAGER="cargo"
  INSTALL_CMD="cargo fetch"
  TEST_CMD="cargo test"
  BUILD_CMD="cargo build"
  LINT_CMD="cargo clippy"
  LOCKFILE_PATTERN=$'Cargo\\.lock'
  SKIP_TEST_PATTERN=$'#\\[ignore\\]'
  TEST_FILE_PATTERN="*.rs"
  return 0
}

# --- Flutter detection ---
detect_flutter() {
  has_file "pubspec.yaml" || return 1
  LANG="flutter"
  PACKAGE_MANAGER="flutter"
  INSTALL_CMD="flutter pub get"
  TEST_CMD="flutter test"
  BUILD_CMD="flutter build"
  LINT_CMD="dart analyze"
  LOCKFILE_PATTERN=$'pubspec\\.lock'
  SKIP_TEST_PATTERN=$'skip:\\s*true'
  TEST_FILE_PATTERN="*_test.dart"
  return 0
}

# --- Gradle detection (Java/Kotlin) ---
detect_gradle() {
  has_file "build.gradle" || has_file "build.gradle.kts" || return 1
  LANG="java"
  PACKAGE_MANAGER="gradle"
  INSTALL_CMD="./gradlew dependencies"
  TEST_CMD="./gradlew test"
  BUILD_CMD="./gradlew build"
  LINT_CMD="./gradlew check"
  LOCKFILE_PATTERN=$'gradle\\.lockfile'
  SKIP_TEST_PATTERN='@Disabled|@Ignore'
  TEST_FILE_PATTERN="*Test.java"
  return 0
}

# --- Maven detection (Java) ---
detect_maven() {
  has_file "pom.xml" || return 1
  LANG="java"
  PACKAGE_MANAGER="maven"
  INSTALL_CMD="mvn dependency:resolve"
  TEST_CMD="mvn test"
  BUILD_CMD="mvn package"
  LINT_CMD="mvn checkstyle:check"
  LOCKFILE_PATTERN=$'pom\\.xml'
  SKIP_TEST_PATTERN='@Disabled|@Ignore'
  TEST_FILE_PATTERN="*Test.java"
  return 0
}

# --- Elixir detection ---
detect_elixir() {
  has_file "mix.exs" || return 1
  LANG="elixir"
  PACKAGE_MANAGER="mix"
  INSTALL_CMD="mix deps.get"
  TEST_CMD="mix test"
  BUILD_CMD="mix compile"
  LINT_CMD="mix credo"
  LOCKFILE_PATTERN=$'mix\\.lock'
  SKIP_TEST_PATTERN='@tag :skip'
  TEST_FILE_PATTERN="*_test.exs"
  return 0
}

# --- Swift detection ---
detect_swift() {
  has_file "Package.swift" || return 1
  LANG="swift"
  PACKAGE_MANAGER="spm"
  INSTALL_CMD="swift package resolve"
  TEST_CMD="swift test"
  BUILD_CMD="swift build"
  LINT_CMD="swiftlint"
  LOCKFILE_PATTERN=$'Package\\.resolved'
  SKIP_TEST_PATTERN='XCTSkip'
  TEST_FILE_PATTERN="*Tests.swift"
  return 0
}

# --- C++ / CMake detection ---
detect_cmake() {
  has_file "CMakeLists.txt" || return 1
  LANG="cpp"
  PACKAGE_MANAGER="cmake"
  INSTALL_CMD="cmake -B build && cmake --build build"
  TEST_CMD="ctest --test-dir build"
  BUILD_CMD="cmake --build build"
  LINT_CMD="clang-tidy"
  LOCKFILE_PATTERN=""
  SKIP_TEST_PATTERN='DISABLED_'
  TEST_FILE_PATTERN="*_test.cpp"
  return 0
}

# --- Ruby detection ---
detect_ruby() {
  has_file "Gemfile" || return 1
  LANG="ruby"
  PACKAGE_MANAGER="bundler"
  INSTALL_CMD="bundle install"
  TEST_CMD="bundle exec rspec"
  BUILD_CMD=""
  LINT_CMD="bundle exec rubocop"
  LOCKFILE_PATTERN=$'Gemfile\\.lock'
  SKIP_TEST_PATTERN='skip|pending'
  TEST_FILE_PATTERN="*_spec.rb"
  return 0
}

# --- PHP detection ---
detect_php() {
  has_file "composer.json" || return 1
  LANG="php"
  PACKAGE_MANAGER="composer"
  INSTALL_CMD="composer install"
  TEST_CMD="./vendor/bin/phpunit"
  BUILD_CMD=""
  LINT_CMD="./vendor/bin/phpstan analyse"
  LOCKFILE_PATTERN=$'composer\\.lock'
  SKIP_TEST_PATTERN='@skip|markTestSkipped'
  TEST_FILE_PATTERN="*Test.php"
  return 0
}

# --- Run detection in priority order ---
detect_node || \
detect_python || \
detect_go || \
detect_rust || \
detect_flutter || \
detect_gradle || \
detect_maven || \
detect_elixir || \
detect_swift || \
detect_cmake || \
detect_ruby || \
detect_php || \
true

# --- Monorepo and Docker detection (always run) ---
detect_monorepo
detect_docker

# --- If not Node, still check for TypeScript ---
if [[ "$LANG" != "node" && "$LANG" != "unknown" ]]; then
  detect_typescript
fi

# --- Adjust root commands if not a monorepo ---
if ! $MONOREPO; then
  TEST_CMD_ROOT=""
  TYPECHECK_CMD_ROOT=""
fi

# --- Helper: JSON-escape a string ---
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# --- Output JSON ---
cat <<EOF
{
  "lang": "$(json_escape "$LANG")",
  "packageManager": "$(json_escape "$PACKAGE_MANAGER")",
  "installCmd": "$(json_escape "$INSTALL_CMD")",
  "testCmd": "$(json_escape "$TEST_CMD")",
  "testCmdRoot": "$(json_escape "$TEST_CMD_ROOT")",
  "typecheckCmd": "$(json_escape "$TYPECHECK_CMD")",
  "typecheckCmdRoot": "$(json_escape "$TYPECHECK_CMD_ROOT")",
  "buildCmd": "$(json_escape "$BUILD_CMD")",
  "lintCmd": "$(json_escape "$LINT_CMD")",
  "e2eCmd": "$(json_escape "$E2E_CMD")",
  "monorepo": ${MONOREPO},
  "docker": ${DOCKER},
  "dockerBuildCmd": "$(json_escape "$DOCKER_BUILD_CMD")",
  "typescript": ${TYPESCRIPT},
  "tsconfig": "$(json_escape "$TSCONFIG")",
  "lockfilePattern": "$(json_escape "$LOCKFILE_PATTERN")",
  "skipTestPattern": "$(json_escape "$SKIP_TEST_PATTERN")",
  "testFilePattern": "$(json_escape "$TEST_FILE_PATTERN")",
  "projectPath": "$(json_escape "$PROJECT_PATH")"
}
EOF
