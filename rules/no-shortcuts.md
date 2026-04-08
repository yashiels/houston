# No Shortcuts

The #1 rule: all changes go through the proper pipeline.

## Forbidden

- Hotfixes directly on production/main
- SSH into servers to patch code
- Docker exec to modify running containers
- `git push --force` to main/master
- `--no-verify` on any git command
- Skipping CI/CD pipeline
- Committing without running tests
- Disabling or skipping tests (.skip, @Ignore, @Disabled)

## Required Path

Every change must follow:
1. Code change on feature branch
2. Tests written and passing
3. Typecheck passing (if applicable)
4. Build passing
5. Commit to feature branch
6. Push to remote
7. PR/MR created with reviewers
8. CI/CD passes
9. Merge via PR/MR (not direct push)

## Enforcement

These rules are enforced by Houston hooks:
- `block-shortcuts.sh` — prevents forbidden commands
- `pre-commit-gate.sh` — blocks commits without passing tests
- `post-edit-tests.sh` — runs tests after file edits
