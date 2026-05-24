# autonomous-dev

> Autonomous AI-driven development: PRD to merge-ready PR.
> Works with Claude Code, OpenCode, Gemini CLI, or any LLM.

Take a product requirement, run a multi-agent pipeline (research, plan, build, test, review), and produce a merge-ready pull request — with quality gates at every stage.

## Quick Start

### Option A: Standalone CLI

```bash
git clone https://github.com/skyner-group/autonomous-dev.git
cd autonomous-dev
./ac.sh /path/to/your/project
```

The CLI walks you through mode selection, model presets, and drives the full pipeline interactively.

### Option B: OpenClaw Skill

```bash
# Copy to OpenClaw skills directory
cp -r autonomous-dev/ ~/.openclaw/workspace/skills/autonomous-dev/

# Then tell your agent:
# "Run autonomous-dev pipeline on /path/to/project"
```

### Option C: Claude Code Session (Programmatic)

```bash
PIPELINE_DIR=/path/to/autonomous-dev

# Initialize
$PIPELINE_DIR/scripts/init-pipeline.sh /path/to/project

# Drive the state machine
$PIPELINE_DIR/scripts/orchestrate.sh init /path/to/project
$PIPELINE_DIR/scripts/orchestrate.sh next      # Get next instruction (JSON)
# ... execute instruction ...
$PIPELINE_DIR/scripts/orchestrate.sh complete <step>
# ... repeat until complete ...
```

## How It Works

```
  PRD / Feature Request
          |
          v
  +-------------------+
  | MODE & MODEL      |  Select: supervised / autonomous / human-assisted
  | SELECTION         |  Select: budget / balanced / premium
  +-------------------+
          |
          v
  +-------------------+
  | RESEARCHER        |  Audit codebase, understand architecture
  | (one-shot, 30m)   |  Output: research/findings.md
  +-------------------+
          |
     [Review Gate]  <-- blocks in supervised & human-assisted modes
          |
          v
  +-------------------+
  | PLANNER           |  PRD + findings -> phased execution plan
  | (one-shot, 30m)   |  Output: prd.json + wiring-checklist.json
  +-------------------+
          |
     [Review Gate]
          |
          v
  +-------------------+     +-------------------+
  | PHASE SUPERVISOR  | --> | CODER (per story) |  TDD: test -> implement -> refactor
  | (disposable, 2h)  |     | (disposable)      |  Quality gate after each story
  +-------------------+     +-------------------+
          |
     [Phase Gate]  <-- blocks only in human-assisted mode
          |
          v
      (repeat for each phase)
          |
          v
  +-------------------+
  | FINAL REVIEWER    |  E2E review of all changes
  | (one-shot, 45m)   |
  +-------------------+
          |
          v
  +-------------------+
  | PR CREATE         |  Push branch, create PR, monitor CI
  | + CI MONITOR      |
  +-------------------+
          |
          v
     Merge-Ready PR
```

## Modes

| Mode | Research Gate | Plan Gate | Phase Gates | BLOCKED |
|------|-------------|-----------|-------------|---------|
| **Supervised Start** (default) | Blocks | Blocks | Skip | Always stops |
| **Fully Autonomous** | Summary only | Summary only | Skip | Always stops |
| **Human Assisted** | Blocks | Blocks | Blocks | Always stops |

- **Supervised Start:** You review the research and plan, then the pipeline builds autonomously.
- **Fully Autonomous:** Pipeline runs end-to-end, only stopping on BLOCKED signals.
- **Human Assisted:** You review at every phase boundary.

## Model Presets

| Preset | Researcher | Planner | Supervisor | Coder | Tester | Reviewer |
|--------|-----------|---------|------------|-------|--------|----------|
| **budget** | flash | flash | flash | flash | flash | flash |
| **balanced** | flash | pro | flash | sonnet | flash | pro |
| **premium** | pro | opus | flash | opus | pro | opus |
| **custom** | user-specified per role |

Model aliases (flash, sonnet, pro, opus, haiku) map to your LLM CLI's model names. Configure in `.autonomous-dev.conf`.

## Multi-Stack Support

The pipeline auto-detects your project stack and adapts test, build, and typecheck commands accordingly.

| Stack | Detection | Test | Build | Typecheck |
|-------|-----------|------|-------|-----------|
| **Node.js** | package.json | `npm test` / `pnpm test` | `npm run build` | `npx tsc --noEmit` |
| **Python** | pyproject.toml, setup.py | `pytest` | `python -m build` | `mypy .` |
| **Go** | go.mod | `go test ./...` | `go build ./...` | `go vet ./...` |
| **Rust** | Cargo.toml | `cargo test` | `cargo build` | `cargo check` |
| **Flutter/Dart** | pubspec.yaml | `flutter test` | `flutter build` | `dart analyze` |
| **JVM (Kotlin)** | build.gradle.kts | `./gradlew test` | `./gradlew build` | (compiler) |
| **JVM (Java)** | pom.xml | `mvn test` | `mvn package` | (compiler) |
| **Elixir** | mix.exs | `mix test` | `mix compile` | `mix dialyzer` |
| **Swift** | Package.swift | `swift test` | `swift build` | (compiler) |
| **C++** | CMakeLists.txt | `ctest` | `cmake --build` | (compiler) |
| **Ruby** | Gemfile | `bundle exec rspec` | (n/a) | `bundle exec rubocop` |
| **PHP** | composer.json | `vendor/bin/phpunit` | (n/a) | `vendor/bin/phpstan` |

## Quality Gates

Three tiers of quality checks, each building on the previous:

### Tier 1: Story Gate (~30s)
Run after each story is implemented.
- Package-level tests
- Root typecheck
- Anti-pattern scan

### Tier 2: Phase Gate (~3-5 min)
Run after all stories in a phase are complete.
- Full test suite
- Full build
- Wiring checklist verification
- Reachability check (no test-only exports)

### Tier 3: Final Gate (~10 min)
Run before PR creation.
- Everything from Tier 2
- Docker build (if applicable)
- E2E tests (if applicable)

**Baseline diffing:** At pipeline init, existing failures are captured. Workers never chase pre-existing bugs.

```bash
scripts/quality-gate.sh --scope story    # Tier 1
scripts/quality-gate.sh --scope phase    # Tier 2
scripts/quality-gate.sh --scope final    # Tier 3
scripts/quality-gate.sh --baseline capture  # Snapshot pre-existing failures
```

## Qdrant Vector Indexer (Optional)

Semantic code search via vector embeddings. Useful for large codebases where agents need to find relevant code.

### Setup

```bash
# One-command setup (requires Docker)
indexer/setup.sh /path/to/your/project
```

This will:
1. Start a Qdrant container
2. Create a Python virtualenv
3. Install dependencies
4. Run initial full index

### Session Reindex

Hook into your editor/agent session start for automatic incremental reindexing:

```bash
# Manual
indexer/session-reindex.sh --project-dir /path/to/project

# Claude Code hooks.json
{
  "hooks": {
    "SessionStart": [{
      "command": "/path/to/autonomous-dev/indexer/session-reindex.sh"
    }]
  }
}
```

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `AD_QDRANT_URL` | `http://localhost:6333` | Qdrant endpoint |
| `--workspace` | auto-detect via `.git` | Project root |
| `--collection` | `codebase-<dirname>` | Collection name |
| `--incremental` | default | Only reindex changed files |
| `--full` | off | Reindex everything |
| `--clean` | off | Drop collection and rebuild |
| `--dry-run` | off | Count files without indexing |

## Claude Code Hooks

The `hooks/` directory contains enforcement hooks for Claude Code sessions:

- **inject-rules** — Inject no-shortcuts rules on session start
- **pre-commit-gate** — Block commits without passing tests
- **post-edit-tests** — Run relevant tests after file edits
- **block-shortcuts** — Block ssh, docker exec, force push, skip CI

See `hooks/README.md` for installation instructions.

## Configuration

Copy `config.example.sh` to your project root as `.autonomous-dev.conf`:

```bash
cp /path/to/autonomous-dev/config.example.sh /path/to/project/.autonomous-dev.conf
```

Key settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `AD_LLM_CLI` | `claude` | LLM CLI to use (claude, opencode, gemini, aider) |
| `AD_DEFAULT_MODE` | `supervised` | Pipeline mode |
| `AD_DEFAULT_PRESET` | `balanced` | Model preset |
| `AD_CO_AUTHOR` | (none) | Git co-author line |
| `AD_REVIEWERS` | (none) | GitHub PR reviewers |
| `AD_QDRANT_URL` | `http://localhost:6333` | Qdrant endpoint |
| `AD_TEST_CMD` | auto-detect | Custom test command |
| `AD_BUILD_CMD` | auto-detect | Custom build command |
| `AD_TYPECHECK_CMD` | auto-detect | Custom typecheck command |

## Project Structure

```
autonomous-dev/
|-- ac.sh                          # CLI entry point
|-- bin/autonomous-dev             # Symlink-friendly binary
|-- SKILL.md                       # Agent skill manifest
|-- config.example.sh              # Configuration template
|-- scripts/
|   |-- orchestrate.sh             # Pipeline state machine
|   |-- init-pipeline.sh           # Pipeline initialization
|   |-- quality-gate.sh            # 3-tier quality gates
|   |-- detect-project.sh          # Stack auto-detection
|   |-- validate-prd.sh            # PRD schema validation
|   |-- anti-pattern-scan.sh       # Anti-pattern detection
|   |-- wiring-check.sh            # Wiring checklist verification
|   |-- reachability-check.sh      # Test-only export detection
|   \-- resume.sh                  # Crash recovery
|-- templates/
|   |-- researcher.md              # Research agent template
|   |-- planner.md                 # Planning agent template
|   |-- phase-supervisor.md        # Phase execution template
|   |-- coder.md                   # TDD coder template
|   |-- reviewer.md                # Phase reviewer template
|   |-- final-review.md            # Final E2E review template
|   \-- code-simplify.md           # Code simplification template
|-- rules/
|   |-- no-shortcuts.md            # No-shortcuts enforcement
|   |-- breaking-changes.md        # Breaking change detection
|   |-- quality-gates.md           # Gate definitions
|   \-- anti-patterns.json         # Pattern definitions
|-- hooks/                         # Claude Code hooks
|-- indexer/
|   |-- index_codebase.py          # Qdrant vector indexer
|   |-- session-reindex.sh         # Session startup reindex
|   |-- setup.sh                   # One-command indexer setup
|   \-- requirements.txt           # Python dependencies
|-- references/
|   |-- methodology.md             # Background theory
|   |-- quick-commands.md          # Copy-paste commands
|   |-- claude-md-guide.md         # CLAUDE.md authoring guide
|   \-- contract-testing.md        # Contract testing patterns
\-- LICENSE                        # MIT
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/your-feature`
3. Make changes and ensure all scripts remain executable
4. Test with at least one real project
5. Submit a PR with a clear description

## License

MIT - see [LICENSE](LICENSE) for details.
