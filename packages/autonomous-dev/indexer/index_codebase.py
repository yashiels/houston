#!/usr/bin/env python3
"""
Codebase indexer for Qdrant — semantic code search via vector embeddings.

Usage:
  python3 index_codebase.py                          # Incremental update (default)
  python3 index_codebase.py --clean                  # Drop collection and rebuild
  python3 index_codebase.py --dry-run                # Count files without indexing
  python3 index_codebase.py --workspace /path/to/repo
  python3 index_codebase.py --collection my-project
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from qdrant_client import QdrantClient
from qdrant_client.models import Distance, PointStruct, VectorParams

# ── Configuration ────────────────────────────────────────────────────────────

QDRANT_URL = os.environ.get("AD_QDRANT_URL", "http://localhost:6333")
EMBEDDING_MODEL = "sentence-transformers/all-MiniLM-L6-v2"
VECTOR_SIZE = 384  # all-MiniLM-L6-v2 output dimension
CHUNK_MIN = 40     # start looking for boundary after this many lines
CHUNK_MAX = 80     # hard split if no boundary found
CHUNK_FALLBACK = 60  # split point when no boundary found within window
CHUNK_OVERLAP = 5  # lines of overlap before boundary

INCLUDE_EXTENSIONS = {
    # Web / JS ecosystem
    ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs",
    # Python
    ".py", ".pyi",
    # Go
    ".go",
    # Rust
    ".rs",
    # JVM
    ".kt", ".java", ".scala", ".gradle", ".kts",
    # Dart / Flutter
    ".dart",
    # Elixir
    ".ex", ".exs",
    # Swift / Apple
    ".swift",
    # C / C++
    ".c", ".h", ".cpp", ".hpp", ".cc", ".hh",
    # Ruby
    ".rb",
    # PHP
    ".php",
    # Lua
    ".lua",
    # Zig
    ".zig",
    # Config / Data
    ".json", ".yaml", ".yml", ".toml",
    ".xml", ".properties", ".gradle",
    # SQL
    ".sql",
    # Shell
    ".sh", ".bash", ".zsh",
    # Docs
    ".md",
}

EXCLUDE_DIRS = {
    "build", ".gradle", "node_modules", ".git",
    ".idea", "generated", "intermediates", "__pycache__",
    ".kotlin", "caches", "dist", ".next", ".turbo",
    ".astro", ".venv", "venv", "coverage", "target",
    ".tox", ".mypy_cache", ".pytest_cache", ".ruff_cache",
    "vendor", "_build", "deps", ".elixir_ls",
    ".dart_tool", ".flutter-plugins",
    "Pods", ".build", ".swiftpm",
    "cmake-build-debug", "cmake-build-release",
}

EXCLUDE_FILES = {
    ".qdrant-index-state.json",
    "package-lock.json",
    "yarn.lock",
    "pnpm-lock.yaml",
    "Cargo.lock",
    "go.sum",
    "Podfile.lock",
    "pubspec.lock",
    "mix.lock",
    "Gemfile.lock",
    "composer.lock",
}

# Regex patterns that indicate natural chunk boundaries
BOUNDARY_PATTERNS = {
    # Kotlin
    "kt": [
        r"^\s*(fun |class |object |interface |override fun |@Composable|companion object)",
    ],
    # Java
    "java": [
        r"^\s*(public |private |protected )?(static )?(class |interface |enum |void |[\w<>\[\]]+\s+\w+\s*\()",
    ],
    # TypeScript
    "ts": [
        r"^\s*(export |function |class |interface |const\s+\w+\s*=\s*\(|type\s+\w+)",
    ],
    "tsx": [
        r"^\s*(export |function |class |interface |const\s+\w+\s*=\s*\(|type\s+\w+)",
    ],
    # JavaScript
    "js": [
        r"^\s*(export |function |class |const\s+\w+\s*=\s*\(|module\.exports)",
    ],
    "jsx": [
        r"^\s*(export |function |class |const\s+\w+\s*=\s*\()",
    ],
    # Python
    "py": [
        r"^\s*(def |class |async def |@\w+)",
    ],
    "pyi": [
        r"^\s*(def |class |async def )",
    ],
    # Go
    "go": [
        r"^\s*(func |type |var |const )",
    ],
    # Rust
    "rs": [
        r"^\s*(pub\s+)?(fn |impl |struct |enum |mod |trait |type |const |static |use )",
    ],
    # Swift
    "swift": [
        r"^\s*(func |class |struct |enum |protocol |extension |var |let |@\w+)",
    ],
    # C / C++
    "c": [
        r"^\s*(void |int |char |float |double |long |short |unsigned |static |extern |struct |enum |typedef )",
    ],
    "h": [
        r"^\s*(void |int |char |float |double |long |short |unsigned |static |extern |struct |enum |typedef |#define |class )",
    ],
    "cpp": [
        r"^\s*(class |void |int |template |namespace |struct |enum |virtual |static |inline )",
    ],
    "hpp": [
        r"^\s*(class |void |int |template |namespace |struct |enum |virtual |static |inline )",
    ],
    "cc": [
        r"^\s*(class |void |int |template |namespace |struct |enum |virtual |static |inline )",
    ],
    # Dart
    "dart": [
        r"^\s*(class |void |Future |Stream |Widget |@override|mixin |extension )",
    ],
    # Elixir
    "ex": [
        r"^\s*(def |defp |defmodule |defmacro |defimpl |defprotocol |defstruct )",
    ],
    "exs": [
        r"^\s*(def |defp |defmodule |defmacro |test |describe |setup )",
    ],
    # Ruby
    "rb": [
        r"^\s*(def |class |module |describe |it |context )",
    ],
    # PHP
    "php": [
        r"^\s*(function |class |interface |trait |namespace |public |private |protected )",
    ],
    # Lua
    "lua": [
        r"^\s*(function |local function )",
    ],
    # Zig
    "zig": [
        r"^\s*(pub fn |fn |const |var |test )",
    ],
    # XML
    "xml": [
        r"^\s*<(?![\?!])\w+[\s>]",
    ],
    # YAML
    "yaml": [
        r"^---",
        r"^\w+:",
    ],
    "yml": [
        r"^---",
        r"^\w+:",
    ],
    # Markdown
    "md": [
        r"^#{1,3}\s",
    ],
    # Shell
    "sh": [
        r"^\s*(function |\w+\s*\(\)\s*\{)",
    ],
}


def _find_workspace(start: Path | None = None) -> Path:
    """Find workspace root by walking up to find .git/ directory."""
    d = (start or Path.cwd()).resolve()
    for _ in range(20):
        if (d / ".git").exists():
            return d
        if d.parent == d:
            break
        d = d.parent
    # Fallback: use current directory
    return (start or Path.cwd()).resolve()


def _detect_repo_type(workspace: Path) -> str:
    """Detect if workspace is a monorepo or single repo."""
    if (workspace / "pnpm-workspace.yaml").exists():
        return "pnpm-monorepo"
    if (workspace / "go.work").exists():
        return "go-monorepo"
    if (workspace / "turbo.json").exists():
        return "turbo-monorepo"
    if (workspace / "lerna.json").exists():
        return "lerna-monorepo"
    if (workspace / "nx.json").exists():
        return "nx-monorepo"
    return "single-repo"


def _get_repo_name(file_path: Path, workspace: Path, repo_type: str) -> str:
    """Determine the repo/package name for a file."""
    if repo_type == "single-repo":
        return workspace.name

    # For monorepos, try to identify the sub-package
    try:
        rel = file_path.relative_to(workspace)
        if len(rel.parts) >= 2:
            return rel.parts[0]
        return workspace.name
    except ValueError:
        return workspace.name


def _is_boundary(line: str, language: str) -> bool:
    """Check if a line matches a boundary pattern for the given language."""
    patterns = BOUNDARY_PATTERNS.get(language, [])
    for pat in patterns:
        if re.match(pat, line):
            return True
    return False


# ── Helpers ───────────────────────────────────────────────────────────────────


def should_index(path: Path) -> bool:
    """Return True if this file should be indexed."""
    if path.name in EXCLUDE_FILES:
        return False
    if path.suffix not in INCLUDE_EXTENSIONS:
        return False
    for part in path.parts:
        if part in EXCLUDE_DIRS:
            return False
    return True


def chunk_file(path: Path, workspace: Path, repo_type: str) -> list[dict]:
    """Split a file into chunks, preferring natural code boundaries."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []

    lines = text.splitlines()
    if not lines:
        return []

    language = path.suffix.lstrip(".")
    repo = _get_repo_name(path, workspace, repo_type)
    chunks = []
    start = 0

    while start < len(lines):
        end = min(start + CHUNK_FALLBACK, len(lines))

        if start + CHUNK_MIN < len(lines):
            boundary_found = False
            for candidate in range(start + CHUNK_MIN, min(start + CHUNK_MAX, len(lines))):
                if _is_boundary(lines[candidate], language):
                    end = candidate
                    boundary_found = True
                    break
            if not boundary_found:
                end = min(start + CHUNK_FALLBACK, len(lines))

        # Don't create tiny trailing chunks (< 10 lines), merge with previous
        if end < len(lines) and (len(lines) - end) < 10:
            end = len(lines)

        chunk_text = "\n".join(lines[start:end])
        if chunk_text.strip():
            chunk_id = hashlib.sha256(
                f"{path}:{start}:{end}:{chunk_text}".encode()
            ).hexdigest()

            formatted = f"File: {path}\nLines: {start+1}-{end}\n\n{chunk_text}"
            chunks.append({
                "id": chunk_id,
                "text": formatted,
                "payload": {
                    "document": formatted,
                    "file": str(path),
                    "repo": repo,
                    "language": language,
                    "line_start": start + 1,
                    "line_end": end,
                },
            })

        start = max(end - CHUNK_OVERLAP, start + 1) if end < len(lines) else end

    return chunks


def collect_files(workspace: Path) -> list[Path]:
    """Walk workspace and return all indexable files."""
    files = []
    for root, dirs, filenames in os.walk(workspace):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for fname in filenames:
            p = Path(root) / fname
            if should_index(p):
                files.append(p)
    return files


def find_git_repos(workspace: Path) -> list[Path]:
    """Find all git repositories under the workspace."""
    repos = []
    for root, dirs, _ in os.walk(workspace):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        if ".git" in os.listdir(root):
            repos.append(Path(root))
            dirs.clear()
    return repos


def get_git_head(repo: Path) -> str | None:
    """Get the current HEAD commit hash for a git repo."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=repo, capture_output=True, text=True, timeout=5,
        )
        return result.stdout.strip() if result.returncode == 0 else None
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None


def get_git_changed_files(repo: Path, since_hash: str) -> list[Path]:
    """Get files changed since a given commit hash."""
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=ACMR", since_hash, "HEAD"],
            cwd=repo, capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            return []
        return [repo / f.strip() for f in result.stdout.strip().splitlines() if f.strip()]
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return []


def get_git_deleted_files(repo: Path, since_hash: str) -> list[Path]:
    """Get files deleted since a given commit hash."""
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=D", since_hash, "HEAD"],
            cwd=repo, capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            return []
        return [repo / f.strip() for f in result.stdout.strip().splitlines() if f.strip()]
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return []


def load_state(state_file: Path) -> dict:
    """Load the index state file."""
    if state_file.exists():
        try:
            return json.loads(state_file.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return {"last_indexed": None, "git_repos": {}, "file_mtimes": {}}


def save_state(state: dict, state_file: Path):
    """Save the index state file."""
    state["last_indexed"] = datetime.now(timezone.utc).isoformat()
    state_file.write_text(json.dumps(state, indent=2))


def collect_incremental_changes(workspace: Path, state: dict) -> tuple[list[Path], list[Path]]:
    """Return (changed_files, deleted_files) since last index."""
    changed = []
    deleted = []

    git_repos = find_git_repos(workspace)
    git_covered_dirs = set()

    for repo in git_repos:
        rel = str(repo.relative_to(workspace))
        git_covered_dirs.add(repo)
        stored_hash = state["git_repos"].get(rel)
        current_hash = get_git_head(repo)

        if stored_hash and current_hash and stored_hash != current_hash:
            repo_changed = get_git_changed_files(repo, stored_hash)
            repo_deleted = get_git_deleted_files(repo, stored_hash)
            changed.extend(f for f in repo_changed if should_index(f))
            deleted.extend(f for f in repo_deleted if should_index(f))
        elif not stored_hash:
            for f in collect_files(repo):
                changed.append(f)

        if current_hash:
            state["git_repos"][rel] = current_hash

    # Handle non-git files
    stored_mtimes = state.get("file_mtimes", {})
    new_mtimes = {}

    for root, dirs, filenames in os.walk(workspace):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        root_path = Path(root)

        if any(root_path == repo or str(root_path).startswith(str(repo) + os.sep)
               for repo in git_covered_dirs):
            continue

        for fname in filenames:
            p = root_path / fname
            if not should_index(p):
                continue
            try:
                mtime = p.stat().st_mtime
            except OSError:
                continue

            file_key = str(p)
            new_mtimes[file_key] = mtime
            stored_mtime = stored_mtimes.get(file_key)
            if stored_mtime is None or mtime > stored_mtime:
                changed.append(p)

    for file_key in stored_mtimes:
        if file_key not in new_mtimes and not any(
            file_key.startswith(str(repo)) for repo in git_covered_dirs
        ):
            deleted.append(Path(file_key))

    state["file_mtimes"] = new_mtimes
    return changed, deleted


def _embed_and_upsert(client: QdrantClient, embedder, all_chunks: list[dict], collection_name: str):
    """Embed chunks and upsert into Qdrant in batches."""
    batch_size = 100
    texts = [c["text"] for c in all_chunks]
    total = len(all_chunks)
    indexed = 0

    print(f"Indexing {total} chunks in batches of {batch_size}...")
    for i in range(0, total, batch_size):
        batch_chunks = all_chunks[i : i + batch_size]
        batch_texts = texts[i : i + batch_size]

        embeddings = list(embedder.embed(batch_texts))

        points = [
            PointStruct(
                id=int(c["id"][:8], 16),
                vector={"fast-all-minilm-l6-v2": list(emb)},
                payload=c["payload"],
            )
            for c, emb in zip(batch_chunks, embeddings)
        ]

        client.upsert(collection_name=collection_name, points=points)
        indexed += len(points)

        pct = indexed / total * 100
        print(f"  {indexed}/{total} ({pct:.0f}%)", end="\r")

    print()


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Index codebase into Qdrant for semantic search")
    parser.add_argument("--workspace", type=str, default=None,
                        help="Path to workspace root (default: auto-detect via .git)")
    parser.add_argument("--collection", type=str, default=None,
                        help="Qdrant collection name (default: codebase-<dirname>)")
    parser.add_argument("--qdrant-url", type=str, default=None,
                        help="Qdrant URL (default: $AD_QDRANT_URL or http://localhost:6333)")
    parser.add_argument("--clean", action="store_true",
                        help="Drop and rebuild collection from scratch")
    parser.add_argument("--dry-run", action="store_true",
                        help="Count files without indexing")
    parser.add_argument("--incremental", action="store_true", default=True,
                        help="Only reindex changed files (default)")
    parser.add_argument("--full", action="store_true",
                        help="Full reindex of all files")
    args = parser.parse_args()

    # Resolve workspace
    workspace = Path(args.workspace).resolve() if args.workspace else _find_workspace()
    if not workspace.exists():
        print(f"ERROR: Workspace not found: {workspace}")
        sys.exit(1)

    # Resolve collection name
    collection_name = args.collection or f"codebase-{workspace.name}"

    # Resolve Qdrant URL
    qdrant_url = args.qdrant_url or QDRANT_URL

    # Detect repo type
    repo_type = _detect_repo_type(workspace)

    # State file lives next to this script
    state_file = Path(__file__).parent / ".qdrant-index-state.json"

    print(f"Workspace: {workspace}")
    print(f"Collection: {collection_name}")
    print(f"Repo type: {repo_type}")
    print(f"Qdrant: {qdrant_url}")

    if args.dry_run:
        files = collect_files(workspace)
        print(f"\nFound {len(files)} indexable files")
        for f in files[:20]:
            try:
                print(f"  {f.relative_to(workspace)}")
            except ValueError:
                print(f"  {f}")
        if len(files) > 20:
            print(f"  ... and {len(files) - 20} more")
        return

    client = QdrantClient(url=qdrant_url)

    # Health check
    try:
        client.get_collections()
    except Exception as e:
        print(f"ERROR: Cannot connect to Qdrant at {qdrant_url}")
        print("  Is Docker running? Try: docker start qdrant")
        print(f"  Details: {e}")
        sys.exit(1)

    # Clean mode: drop existing collection
    if args.clean:
        collections = [c.name for c in client.get_collections().collections]
        if collection_name in collections:
            print(f"Dropping collection '{collection_name}'...")
            client.delete_collection(collection_name)

    # Ensure collection exists
    collections = [c.name for c in client.get_collections().collections]
    if collection_name not in collections:
        print(f"Creating collection '{collection_name}'...")
        client.create_collection(
            collection_name=collection_name,
            vectors_config={"fast-all-minilm-l6-v2": VectorParams(size=VECTOR_SIZE, distance=Distance.COSINE)},
        )

    # Full reindex or clean → do full
    if args.full or args.clean:
        print(f"Scanning {workspace}...")
        files = collect_files(workspace)
        print(f"Found {len(files)} indexable files")

        print("Chunking files...")
        all_chunks = []
        for f in files:
            all_chunks.extend(chunk_file(f, workspace, repo_type))
        print(f"Generated {len(all_chunks)} chunks")

        from fastembed import TextEmbedding
        print(f"Loading embedding model '{EMBEDDING_MODEL}'...")
        embedder = TextEmbedding(model_name=EMBEDDING_MODEL)

        _embed_and_upsert(client, embedder, all_chunks, collection_name)

        # Save state after full index
        state = load_state(state_file)
        for repo in find_git_repos(workspace):
            rel = str(repo.relative_to(workspace))
            head = get_git_head(repo)
            if head:
                state["git_repos"][rel] = head
        save_state(state, state_file)

        print(f"\nDone. {len(all_chunks)} chunks indexed into '{collection_name}'.")
        return

    # Incremental mode (default)
    state = load_state(state_file)
    print(f"Scanning {workspace} for changes...")
    changed, deleted_files = collect_incremental_changes(workspace, state)

    if not changed and not deleted_files:
        print("Index up to date. No changes detected.")
        save_state(state, state_file)
        return

    print(f"Found {len(changed)} changed files, {len(deleted_files)} deleted files")

    # Delete chunks for deleted files
    if deleted_files:
        from qdrant_client.models import Filter, FieldCondition, MatchValue
        for df in deleted_files:
            client.delete(
                collection_name=collection_name,
                points_selector=Filter(
                    must=[FieldCondition(key="file", match=MatchValue(value=str(df)))]
                ),
            )
        print(f"Removed chunks for {len(deleted_files)} deleted files")

    # Delete old chunks for changed files before re-inserting
    if changed:
        from qdrant_client.models import Filter, FieldCondition, MatchValue
        for cf in changed:
            client.delete(
                collection_name=collection_name,
                points_selector=Filter(
                    must=[FieldCondition(key="file", match=MatchValue(value=str(cf)))]
                ),
            )

    # Chunk and index changed files
    all_chunks = []
    for f in changed:
        if f.exists():
            all_chunks.extend(chunk_file(f, workspace, repo_type))
    print(f"Generated {len(all_chunks)} chunks from changed files")

    if all_chunks:
        from fastembed import TextEmbedding
        embedder = TextEmbedding(model_name=EMBEDDING_MODEL)
        _embed_and_upsert(client, embedder, all_chunks, collection_name)

    save_state(state, state_file)
    print(f"Done. Reindexed {len(changed)} files ({len(all_chunks)} chunks).")


if __name__ == "__main__":
    main()
