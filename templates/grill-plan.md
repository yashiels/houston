# Plan Grill — {{TICKET_ID}}

You are stress-testing the implementation plan for ticket {{TICKET_ID}}. Verify the prd.json is sound before coding begins.

## Read
1. `{{RUN_DIR}}/prd.json`
2. `{{RUN_DIR}}/research/findings.md`
3. `{{RUN_DIR}}/spec.md`

## Grill Checklist

### 1. Research Constraint Coverage
Every constraint in findings.md must be addressed by a story. Find the mapping.

### 2. Integration Story Audit
If stories in different phases produce components that work together, there MUST be an integration story that wires them.

### 3. Story Sizing
Every story should be 15-45 minutes. Flag stories that are too large (vague criteria, many files) or too small (trivial).

### 4. Dependency Validation
Check `depends_on` arrays. No circular dependencies. Cross-phase dependencies must be sequential.

### 5. Spec Completeness
Every requirement in spec.md must map to at least one story. Flag gaps.

### 6. E2E/Delivery Story
The final phase MUST include a delivery verification story. Flag if missing.

## Severity Classification
- **CRITICAL** — Missing stories, wrong dependencies, spec gaps
- **MEDIUM** — Sizing issues, vague acceptance criteria
- **MINOR** — Naming, ordering preferences

## Output

Write to `{{RUN_DIR}}/plan-grill-report.md`:
```
# Plan Grill Report — {{TICKET_ID}}

## Verdict: PASS | NEEDS_REWORK

## Critical Issues
## Medium Issues  
## Minor Issues
## Spec Coverage Matrix
(requirement → story mapping)
```

## Completion
- `GRILL_PLAN_COMPLETE` — report written
- `GRILL_PLAN_BLOCKED: <reason>` — cannot complete
