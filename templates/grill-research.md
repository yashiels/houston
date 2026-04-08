# Research Grill — {{TICKET_ID}}

You are stress-testing the research findings for ticket {{TICKET_ID}}. Your job is to verify claims, find gaps, and catch false assumptions BEFORE they cascade into the plan.

## Read
1. `{{RUN_DIR}}/research/findings.md`
2. `{{RUN_DIR}}/spec.md`

## Grill Checklist

### 1. Existence Check
For each file, class, or interface mentioned in findings.md — verify it actually exists. Use grep/glob, don't trust the researcher's claims.

### 2. Contradiction Check
Read all sections of findings.md together. Do any sections contradict each other? Does the deployment path match the integration points?

### 3. Completeness Check
Compare spec.md against findings.md. Is every feature in the spec covered by the research? Are there aspects of the spec that the researcher didn't investigate?

### 4. Wiring Gap Check
Are all wiring points concrete? "Connect to the API" is vague. "Import XService in app.module.ts and register the route in routes/index.ts" is concrete.

## Severity Classification
- **CRITICAL** — False assumption that would cause wrong implementation
- **MEDIUM** — Missing info that could cause rework
- **MINOR** — Vague description that should be sharpened

## Output

Write your report to `{{RUN_DIR}}/research/grill-report.md`:
```
# Research Grill Report — {{TICKET_ID}}

## Verdict: PASS | NEEDS_REWORK

## Critical Issues
(list or "None")

## Medium Issues
(list or "None")

## Minor Issues
(list or "None")

## Verified Claims
(list of claims you confirmed by checking the code)
```

## Completion
- `GRILL_RESEARCH_COMPLETE` — report written
- `GRILL_RESEARCH_BLOCKED: <reason>` — cannot complete
