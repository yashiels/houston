#!/bin/bash
# detect-project.sh — Detect project structure and output JSON config
# Usage: ./scripts/detect-project.sh [project-path]
# Output: JSON config for use by quality-gate.sh and other pipeline scripts
#
# Supports: Node.js (npm/pnpm/yarn/bun), Python, Go, Rust, Flutter,
#           Java/Kotlin (Gradle/Maven), Elixir, Swift, C++

set -euo pipefail

PROJECT_PATH="${1:-$(pwd)}"
cd "$PROJECT_PATH"

# ─── Language Detection ───

LANG="unknown"
PACKAGE_MANAGER=""
INSTALL_CMD=""
TEST_CMD=""
BUILD_CMD=""
TYPECHECK_CMD=""
LINT_CMD=""
E2E_CMD=""
LOCKFILE_PATTERN=""
SKIP_TEST_PATTERN=""
TEST_FILE_PATTERN=""

# Node.js detection
if [ -f "package.json" ]; then
  LANG="node"
  PACKAGE_MANAGER="npm"
  INSTALL_CMD="npm install"
  TEST_CMD="npm test"
  TYPECHECK_CMD="npx tsc --noEmit"
  BUILD_CMD="npm run build"
  LINT_CMD="npm run lint"
  LOCKFILE_PATTERN="package-lock\\.json"
  SKIP_TEST_PATTERN="\\.skip\\(|\\.only\\(|xit\\(|xdescribe\\(|fdescribe\\(|fit\\("
  TEST_FILE_PATTERN="*.test.*"

  if [ -f "pnpm-lock.yaml" ]; then
    PACKAGE_MANAGER="pnpm"
    INSTALL_CMD="pnpm install"
    TEST_CMD="pnpm test"
    TYPECHECK_CMD="pnpm exec tsc --noEmit"
    BUILD_CMD="pnpm build"
    LINT_CMD="pnpm lint"
    LOCKFILE_PATTERN="pnpm-lock\\.yaml"
  elif [ -f "yarn.lock" ]; then
    PACKAGE_MANAGER="yarn"
    INSTALL_CMD="yarn install"
    TEST_CMD="yarn test"
    TYPECHECK_CMD="yarn tsc --noEmit"
    BUILD_CMD="yarn build"
    LINT_CMD="yarn lint"
    LOCKFILE_PATTERN="yarn\\.lock"
  elif [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
    PACKAGE_MANAGER="bun"
    INSTALL_CMD="bun install"
    TEST_CMD="bun test"
    TYPECHECK_CMD="bunx tsc --noEmit"
    BUILD_CMD="bun run build"
    LINT_CMD="bun run lint"
    LOCKFILE_PATTERN="bun\\.lock(b)?"
  fi

# Python detection
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
  LANG="python"
  SKIP_TEST_PATTERN="@pytest\\.mark\\.skip|@unittest\\.skip|pytest\\.skip"
  TEST_FILE_PATTERN="test_*.py"

  if [ -f "pyproject.toml" ] && grep -q "poetry" pyproject.toml 2>/dev/null; then
    PACKAGE_MANAGER="poetry"
    INSTALL_CMD="poetry install"
    TEST_CMD="poetry run pytest"
    BUILD_CMD="poetry build"
    LINT_CMD="poetry run ruff check ."
    TYPECHECK_CMD="poetry run mypy ."
    LOCKFILE_PATTERN="poetry\\.lock"
  elif [ -f "pyproject.toml" ] && grep -q "uv" pyproject.toml 2>/dev/null; then
    PACKAGE_MANAGER="uv"
    INSTALL_CMD="uv sync"
    TEST_CMD="uv run pytest"
    BUILD_CMD="uv build"
    LINT_CMD="uv run ruff check ."
    TYPECHECK_CMD="uv run mypy ."
    LOCKFILE_PATTERN="uv\\.lock"
  elif [ -f "Pipfile" ]; then
    PACKAGE_MANAGER="pipenv"
    INSTALL_CMD="pipenv install"
    TEST_CMD="pipenv run pytest"
    BUILD_CMD=""
    LINT_CMD="pipenv run ruff check ."
    TYPECHECK_CMD="pipenv run mypy ."
    LOCKFILE_PATTERN="Pipfile\\.lock"
  else
    PACKAGE_MANAGER="pip"
    INSTALL_CMD="pip install -r requirements.txt"
    TEST_CMD="pytest"
    BUILD_CMD=""
    LINT_CMD="ruff check ."
    TYPECHECK_CMD="mypy ."
    LOCKFILE_PATTERN="requirements\\.txt"
  fi

# Go detection
elif [ -f "go.mod" ]; then
  LANG="go"
  PACKAGE_MANAGER="go"
  INSTALL_CMD="go mod download"
  TEST_CMD="go test ./..."
  BUILD_CMD="go build ./..."
  TYPECHECK_CMD="go vet ./..."
  LINT_CMD="golangci-lint run"
  LOCKFILE_PATTERN="go\\.sum"
  SKIP_TEST_PATTERN="t\\.Skip\\("
  TEST_FILE_PATTERN="*_test.go"

# Rust detection
elif [ -f "Cargo.toml" ]; then
  LANG="rust"
  PACKAGE_MANAGER="cargo"
  INSTALL_CMD="cargo fetch"
  TEST_CMD="cargo test"
  BUILD_CMD="cargo build"
  TYPECHECK_CMD="cargo check"
  LINT_CMD="cargo clippy -- -D warnings"
  LOCKFILE_PATTERN="Cargo\\.lock"
  SKIP_TEST_PATTERN="#\\[ignore\\]"
  TEST_FILE_PATTERN="*.rs"

# Flutter/Dart detection
elif [ -f "pubspec.yaml" ]; then
  LANG="flutter"
  PACKAGE_MANAGER="flutter"
  INSTALL_CMD="flutter pub get"
  TEST_CMD="flutter test"
  BUILD_CMD="flutter build"
  TYPECHECK_CMD="dart analyze"
  LINT_CMD="dart analyze"
  LOCKFILE_PATTERN="pubspec\\.lock"
  SKIP_TEST_PATTERN="skip:"
  TEST_FILE_PATTERN="*_test.dart"

# Java/Kotlin (Gradle) detection
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  LANG="java"
  PACKAGE_MANAGER="gradle"
  INSTALL_CMD="./gradlew dependencies"
  TEST_CMD="./gradlew test"
  BUILD_CMD="./gradlew build"
  TYPECHECK_CMD=""
  LINT_CMD="./gradlew lint"
  LOCKFILE_PATTERN="gradle\\.lockfile"
  SKIP_TEST_PATTERN="@Disabled|@Ignore"
  TEST_FILE_PATTERN="*Test.java"

# Java/Kotlin (Maven) detection
elif [ -f "pom.xml" ]; then
  LANG="java"
  PACKAGE_MANAGER="maven"
  INSTALL_CMD="mvn dependency:resolve"
  TEST_CMD="mvn test"
  BUILD_CMD="mvn package"
  TYPECHECK_CMD=""
  LINT_CMD="mvn checkstyle:check"
  LOCKFILE_PATTERN=""
  SKIP_TEST_PATTERN="@Disabled|@Ignore"
  TEST_FILE_PATTERN="*Test.java"

# Elixir detection
elif [ -f "mix.exs" ]; then
  LANG="elixir"
  PACKAGE_MANAGER="mix"
  INSTALL_CMD="mix deps.get"
  TEST_CMD="mix test"
  BUILD_CMD="mix compile"
  TYPECHECK_CMD="mix dialyzer"
  LINT_CMD="mix credo"
  LOCKFILE_PATTERN="mix\\.lock"
  SKIP_TEST_PATTERN="@tag :skip"
  TEST_FILE_PATTERN="*_test.exs"

# Swift detection
elif [ -f "Package.swift" ]; then
  LANG="swift"
  PACKAGE_MANAGER="spm"
  INSTALL_CMD="swift package resolve"
  TEST_CMD="swift test"
  BUILD_CMD="swift build"
  TYPECHECK_CMD=""
  LINT_CMD="swiftlint"
  LOCKFILE_PATTERN="Package\\.resolved"
  SKIP_TEST_PATTERN=""
  TEST_FILE_PATTERN="*Tests.swift"

# C++ detection (CMake)
elif [ -f "CMakeLists.txt" ]; then
  LANG="cpp"
  PACKAGE_MANAGER="cmake"
  INSTALL_CMD="cmake -B build && cmake --build build"
  TEST_CMD="cd build && ctest"
  BUILD_CMD="cmake --build build"
  TYPECHECK_CMD=""
  LINT_CMD="clang-tidy"
  LOCKFILE_PATTERN=""
  SKIP_TEST_PATTERN="DISABLED_"
  TEST_FILE_PATTERN="*_test.cpp"
fi

# ─── Monorepo Detection ───

MONOREPO=false
if [ -f "pnpm-workspace.yaml" ] || [ -f "lerna.json" ] || [ -f "nx.json" ] || [ -f "turbo.json" ]; then
  MONOREPO=true
fi
if [ -f "package.json" ] && command -v jq &>/dev/null; then
  if jq -e '.workspaces' package.json &>/dev/null; then
    MONOREPO=true
  fi
fi

# Adjust commands for monorepo
TEST_CMD_ROOT="$TEST_CMD"
TYPECHECK_CMD_ROOT="$TYPECHECK_CMD"
if [ "$MONOREPO" = "true" ] && [ "$LANG" = "node" ]; then
  case "$PACKAGE_MANAGER" in
    pnpm)
      TEST_CMD_ROOT="pnpm -r test"
      TYPECHECK_CMD_ROOT="pnpm -r exec tsc --noEmit"
      BUILD_CMD="pnpm -r build"
      ;;
    yarn)
      TEST_CMD_ROOT="yarn workspaces run test"
      TYPECHECK_CMD_ROOT="yarn workspaces run tsc --noEmit"
      ;;
    npm)
      TEST_CMD_ROOT="npm run test --workspaces"
      TYPECHECK_CMD_ROOT="npm run typecheck --workspaces"
      ;;
  esac
fi

# ─── Docker Detection ───

DOCKER=false
DOCKER_BUILD_CMD=""
if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] || [ -f "compose.yml" ] || [ -f "compose.yaml" ]; then
  DOCKER=true
  DOCKER_BUILD_CMD="docker compose build"
elif [ -f "Dockerfile" ]; then
  DOCKER=true
  IMAGE_NAME=$(basename "$PROJECT_PATH" | tr '[:upper:]' '[:lower:]')
  DOCKER_BUILD_CMD="docker build -t $IMAGE_NAME ."
fi

# ─── TypeScript Detection ───

TYPESCRIPT=false
TSCONFIG=""
if [ -f "tsconfig.json" ]; then
  TYPESCRIPT=true
  TSCONFIG="tsconfig.json"
elif find . -name "tsconfig.json" -not -path "*/node_modules/*" -maxdepth 3 2>/dev/null | grep -q .; then
  TYPESCRIPT=true
  TSCONFIG=$(find . -name "tsconfig.json" -not -path "*/node_modules/*" -maxdepth 3 2>/dev/null | head -1)
fi

# Override typecheck if not TypeScript and language is Node
if [ "$LANG" = "node" ] && [ "$TYPESCRIPT" = "false" ]; then
  TYPECHECK_CMD=""
  TYPECHECK_CMD_ROOT=""
fi

# ─── Check for Custom Scripts in package.json ───

if [ -f "package.json" ] && command -v jq &>/dev/null; then
  if jq -e '.scripts.typecheck' package.json &>/dev/null; then
    TYPECHECK_CMD="$PACKAGE_MANAGER run typecheck"
  fi
  if ! jq -e '.scripts.test' package.json &>/dev/null; then
    TEST_CMD=""
    TEST_CMD_ROOT=""
  fi
  if ! jq -e '.scripts.build' package.json &>/dev/null; then
    BUILD_CMD=""
  fi
  if ! jq -e '.scripts.lint' package.json &>/dev/null && [ "$LANG" = "node" ]; then
    LINT_CMD=""
  fi
  if jq -e '.scripts["test:e2e"]' package.json &>/dev/null; then
    E2E_CMD="$PACKAGE_MANAGER run test:e2e"
  elif jq -e '.scripts.e2e' package.json &>/dev/null; then
    E2E_CMD="$PACKAGE_MANAGER run e2e"
  fi
fi

# ─── Output JSON ───

cat <<EOF
{
  "lang": "$LANG",
  "packageManager": "$PACKAGE_MANAGER",
  "installCmd": "$INSTALL_CMD",
  "testCmd": "$TEST_CMD",
  "testCmdRoot": "${TEST_CMD_ROOT:-$TEST_CMD}",
  "typecheckCmd": "$TYPECHECK_CMD",
  "typecheckCmdRoot": "${TYPECHECK_CMD_ROOT:-$TYPECHECK_CMD}",
  "buildCmd": "$BUILD_CMD",
  "lintCmd": "$LINT_CMD",
  "e2eCmd": "$E2E_CMD",
  "monorepo": $MONOREPO,
  "docker": $DOCKER,
  "dockerBuildCmd": "$DOCKER_BUILD_CMD",
  "typescript": $TYPESCRIPT,
  "tsconfig": "$TSCONFIG",
  "lockfilePattern": "$(echo "$LOCKFILE_PATTERN" | sed 's/\\/\\\\/g')",
  "skipTestPattern": "$(echo "$SKIP_TEST_PATTERN" | sed 's/\\/\\\\/g')",
  "testFilePattern": "$TEST_FILE_PATTERN",
  "projectPath": "$PROJECT_PATH"
}
EOF
