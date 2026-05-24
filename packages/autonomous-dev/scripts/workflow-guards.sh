#!/usr/bin/env bash
# workflow-guards.sh - Safety guards for autonomous development workflow
# 
# Usage:
#   ./workflow-guards.sh pre-push <repo_path>                    # Run tests before push
#   ./workflow-guards.sh worktree-check <worktree_path>          # Check if worktree is clean
#   ./workflow-guards.sh rebase-develop <worktree_path>          # Rebase on develop
#   ./workflow-guards.sh linear-retry <command>                  # Linear API with retry
#   ./workflow-guards.sh validate-requirements <issue_id>        # Check if requirements clear
#   ./workflow-guards.sh ci-status <pr_number> <repo_path>       # Check CI status

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Resolve secrets from 1Password
resolve_secret() {
    local key_id="$1"
    local json='{"ids":["'"$key_id"'"]}'
    echo "$json" | python3 ~/.openclaw/scripts/op-resolve | python3 -c "import json,sys; print(json.load(sys.stdin)['values']['$key_id'])"
}

# 1. Pre-push: Run tests before pushing
cmd_pre_push() {
    local repo_path="$1"
    cd "$repo_path"
    
    log_info "Running pre-push checks..."
    
    # Detect project type and run appropriate tests
    if [[ -f "package.json" ]]; then
        log_info "Node.js project detected"
        
        # Lint
        if grep -q '"lint"' package.json; then
            log_info "Running lint..."
            if ! npm run lint; then
                log_error "Lint failed. Fix before pushing."
                return 1
            fi
            log_success "Lint passed"
        fi
        
        # Typecheck
        if grep -q '"typecheck"' package.json; then
            log_info "Running typecheck..."
            if ! npm run typecheck; then
                log_error "Typecheck failed. Fix before pushing."
                return 1
            fi
            log_success "Typecheck passed"
        fi
        
        # Tests (if available and not skipped)
        if [[ "${SKIP_TESTS:-}" != "true" ]] && grep -q '"test"' package.json; then
            log_info "Running tests..."
            if ! npm test; then
                log_error "Tests failed. Fix before pushing."
                return 1
            fi
            log_success "Tests passed"
        fi
        
    elif [[ -f "pubspec.yaml" ]]; then
        log_info "Flutter/Dart project detected"
        
        log_info "Running flutter analyze..."
        if ! flutter analyze; then
            log_error "Flutter analyze failed. Fix before pushing."
            return 1
        fi
        log_success "Flutter analyze passed"
        
        if [[ "${SKIP_TESTS:-}" != "true" ]]; then
            log_info "Running flutter test..."
            if ! flutter test; then
                log_error "Flutter tests failed. Fix before pushing."
                return 1
            fi
            log_success "Flutter tests passed"
        fi
        
    elif [[ -f "Cargo.toml" ]]; then
        log_info "Rust project detected"
        
        log_info "Running cargo check..."
        if ! cargo check; then
            log_error "Cargo check failed. Fix before pushing."
            return 1
        fi
        log_success "Cargo check passed"
        
        if [[ "${SKIP_TESTS:-}" != "true" ]]; then
            log_info "Running cargo test..."
            if ! cargo test; then
                log_error "Cargo tests failed. Fix before pushing."
                return 1
            fi
            log_success "Cargo tests passed"
        fi
    else
        log_warn "Unknown project type. Skipping automated tests."
    fi
    
    log_success "All pre-push checks passed!"
    return 0
}

# 5. Worktree check: Reuse if clean, prompt if dirty
cmd_worktree_check() {
    local worktree_path="$1"
    
    if [[ ! -d "$worktree_path" ]]; then
        echo "NOT_EXISTS"
        return 0
    fi
    
    cd "$worktree_path"
    
    # Check if there are uncommitted changes
    if git diff --quiet && git diff --staged --quiet; then
        # Check if there are untracked files
        if [[ -z $(git ls-files --others --exclude-standard) ]]; then
            echo "CLEAN"
            return 0
        fi
    fi
    
    echo "DIRTY"
    return 0
}

# Detect the default branch from remote
cmd_get_default_branch() {
    local repo_path="${1:-.}"
    cd "$repo_path"
    
    # Try gh CLI first (most reliable)
    if command -v gh &>/dev/null && gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null; then
        return 0
    fi
    
    # Fallback: check origin/HEAD symref
    local head_ref
    head_ref=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    if [[ -n "$head_ref" ]]; then
        echo "$head_ref"
        return 0
    fi
    
    # Fallback: check remote show origin
    local default
    default=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //')
    if [[ -n "$default" ]]; then
        echo "$default"
        return 0
    fi
    
    # Last resort: assume 'main' or 'master'
    if git rev-parse origin/main &>/dev/null; then
        echo "main"
    elif git rev-parse origin/master &>/dev/null; then
        echo "master"
    else
        echo "main"
    fi
}

# 7/8. Rebase on default branch before PR
cmd_rebase_develop() {
    cmd_rebase_default "$@"
}

cmd_rebase_default() {
    local worktree_path="$1"
    cd "$worktree_path"
    
    local current_branch
    current_branch=$(git branch --show-current)
    
    # Detect default branch
    local default_branch
    default_branch=$(cmd_get_default_branch "$worktree_path")
    
    log_info "Current branch: $current_branch"
    log_info "Detected default branch: $default_branch"
    log_info "Fetching latest $default_branch..."
    
    # Clean up .next build artifacts that cause rebase conflicts
    rm -rf .next 2>/dev/null || true
    
    git fetch origin "$default_branch"
    
    log_info "Rebasing on origin/$default_branch..."
    
    if git rebase "origin/$default_branch"; then
        log_success "Rebase successful on origin/$default_branch"
        return 0
    else
        log_error "Rebase failed. Conflicts detected."
        git rebase --abort 2>/dev/null || true
        echo "CONFLICTS"
        return 1
    fi
}

# 6. Linear API with retry
cmd_linear_retry() {
    local command="$1"
    local max_retries=3
    local retry_delay=2
    local attempt=1
    
    while [[ $attempt -le $max_retries ]]; do
        log_info "Linear API attempt $attempt/$max_retries"
        
        if output=$(~/.openclaw/workspace/skills/linear/scripts/linear-wrapper.sh "$command" 2>&1); then
            echo "$output"
            log_success "Linear API call succeeded"
            return 0
        fi
        
        log_warn "Attempt $attempt failed: $output"
        
        if [[ $attempt -lt $max_retries ]]; then
            log_info "Retrying in ${retry_delay}s..."
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))  # Exponential backoff
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Linear API failed after $max_retries attempts. Continuing in degraded mode."
    echo "DEGRADED"
    return 0
}

# 2. Validate requirements - check if issue is clear enough
cmd_validate_requirements() {
    local issue_id="$1"
    
    log_info "Fetching issue $issue_id..."
    
    local issue_json
    issue_json=$(cmd_linear_retry "issue $issue_id")
    
    if [[ "$issue_json" == "DEGRADED" ]]; then
        log_warn "Cannot fetch issue details. Proceeding with caution."
        echo "UNCERTAIN:Cannot fetch issue details"
        return 0
    fi
    
    # Check for key fields
    local title
    
    # Extract title and description from the output
    title=$(echo "$issue_json" | head -1 | sed 's/.*: //')
    
    # Check if description exists and is meaningful
    local has_description=0
    local has_acceptance_criteria=0
    
    if echo "$issue_json" | grep -qi "description\|acceptance\|criteria\|given\|when\|then"; then
        has_description=1
    fi
    
    # Calculate confidence score
    local confidence=50
    
    # Title clarity (does it have action words?)
    if echo "$title" | grep -qiE "add|remove|fix|update|create|delete|implement|refactor"; then
        confidence=$((confidence + 20))
    fi
    
    # Has description
    if [[ $has_description -eq 1 ]]; then
        confidence=$((confidence + 20))
    fi
    
    # Has acceptance criteria
    if [[ $has_acceptance_criteria -eq 1 ]]; then
        confidence=$((confidence + 20))
    fi
    
    if [[ $confidence -ge 80 ]]; then
        log_success "Requirements clear (confidence: $confidence%)"
        echo "CLEAR:$confidence:$title"
    elif [[ $confidence -ge 60 ]]; then
        log_warn "Requirements somewhat clear (confidence: $confidence%)"
        echo "UNCERTAIN:$confidence:$title"
    else
        log_error "Requirements unclear (confidence: $confidence%)"
        echo "UNCLEAR:$confidence:$title"
    fi
    
    return 0
}

# 4. Check CI status for PR
cmd_ci_status() {
    local pr_number="$1"
    local repo_path="${2:-.}"
    cd "$repo_path"
    
    log_info "Checking CI status for PR #$pr_number..."
    
    local status
    status=$(gh pr checks "$pr_number" 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "All CI checks passed"
        echo "PASSED"
        return 0
    elif echo "$status" | grep -q "pending"; then
        log_info "CI checks still running"
        echo "PENDING"
        return 0
    elif echo "$status" | grep -q "failing\|failed"; then
        log_error "CI checks failed"
        echo "FAILED:$status"
        return 1
    else
        log_warn "Unknown CI status"
        echo "UNKNOWN:$status"
        return 0
    fi
}

# Check PR review status
cmd_review_status() {
    local pr_number="$1"
    local repo_path="${2:-.}"
    cd "$repo_path"
    
    log_info "Checking review status for PR #$pr_number..."
    
    local review_status
    review_status=$(gh pr view "$pr_number" --json reviewDecision,mergeStateStatus -q '.reviewDecision, .mergeStateStatus')
    
    echo "$review_status"
}

# Main command dispatcher
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        pre-push)
            cmd_pre_push "$@"
            ;;
        worktree-check)
            cmd_worktree_check "$@"
            ;;
        rebase-develop)
            cmd_rebase_default "$@"
            ;;
        rebase-default)
            cmd_rebase_default "$@"
            ;;
        get-default-branch)
            cmd_get_default_branch "$@"
            ;;
        linear-retry)
            cmd_linear_retry "$@"
            ;;
        validate-requirements)
            cmd_validate_requirements "$@"
            ;;
        ci-status)
            cmd_ci_status "$@"
            ;;
        review-status)
            cmd_review_status "$@"
            ;;
        help|--help|-h)
            echo "Usage: $0 <command> [args]"
            echo ""
            echo "Commands:"
            echo "  pre-push <repo_path>              Run tests before push"
            echo "  worktree-check <path>             Check if worktree is clean"
            echo "  rebase-develop <path>             Rebase on default branch (alias)"
echo "  rebase-default <path>             Rebase on detected default branch"
echo "  get-default-branch [path]         Print detected default branch"
            echo "  linear-retry <cmd>                Linear API with retry"
            echo "  validate-requirements <issue_id>  Check if requirements clear"
            echo "  ci-status <pr_number> [repo]      Check CI status"
            echo "  review-status <pr_number> [repo]  Check review status"
            ;;
        *)
            log_error "Unknown command: $command"
            exit 1
            ;;
    esac
}

main "$@"
