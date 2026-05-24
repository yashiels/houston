# Code Simplify

You are reviewing changed files for simplification opportunities.
Only simplify, never change behavior.

**Project:** __PROJECT_PATH__
**Branch:** __BRANCH_NAME__

## Your Mission

Review each changed file and look for:

1. **Dead code** -- unused imports, unreachable branches, commented-out code
2. **Duplication** -- repeated logic that should be extracted into shared functions
3. **Complexity** -- overly nested conditionals, long functions (>50 lines), god objects
4. **Naming** -- unclear variable/function names, inconsistent naming conventions
5. **Type safety** -- `any` types that could be narrowed, missing return types
6. **Unused exports** -- exports that nothing imports (check with grep)

## Rules

- Only simplify, never change behavior
- Don't add features or fix bugs during simplification
- Don't refactor code that wasn't changed in this branch
- Keep changes minimal and reviewable
- Every simplification must preserve all existing tests passing

## Process

1. Get the list of changed files:
```bash
cd __PROJECT_PATH__
git diff --name-only main...__BRANCH_NAME__ | grep -v node_modules | grep -v vendor | grep -v build
```

2. For each changed file:
   - Read the file
   - Identify simplification opportunities
   - Apply simplifications
   - Run tests to verify no behavioral change

3. Run quality gate:
```bash
__PIPELINE_DIR__/scripts/quality-gate.sh --scope phase 2>/dev/null || true
# Or use the project's standard test/lint commands
```

4. Commit:
```bash
git add -p
git commit -m "refactor: simplify changed files"
```

## What To Simplify

### Dead Code
```bash
# Find unused imports (TypeScript/JavaScript)
grep -n "^import" <file> | while read line; do
  symbol=$(echo "$line" | grep -oP '(?<=import\s)\w+|(?<={\s*)\w+')
  count=$(grep -c "$symbol" <file>)
  [ "$count" -le 1 ] && echo "Unused: $line"
done
```

### Duplication
- Look for repeated blocks of 3+ lines
- Extract into helper functions
- Use shared utilities if the project has them

### Complexity
- Flatten nested if/else chains into early returns
- Extract complex conditions into named boolean variables
- Break functions >50 lines into smaller focused functions

### Type Safety
- Replace `any` with specific types
- Add return type annotations to exported functions
- Use discriminated unions instead of type assertions

## What NOT To Simplify

- Code that wasn't changed in this branch
- Test files (unless they have dead imports)
- Configuration files
- Generated code
- Third-party code or vendored dependencies

## Output

```
SIMPLIFY_COMPLETE
Files reviewed: N
Simplifications applied: N
Quality gate: passing
Commit: <hash>
```

If no simplifications found:
```
SIMPLIFY_COMPLETE
Files reviewed: N
Simplifications applied: 0
Note: Code is already clean
```

## Changed Files

__CHANGED_FILES__
