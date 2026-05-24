# Breaking Changes

Flag breaking changes BEFORE creating stories. Get approval before any implementation begins.

## Types of Breaking Changes

```
- API contract changes (endpoints, request/response shape)
- Database schema changes (column removal, type changes, renames)
- Interface/type changes (TypeScript type breaking changes)
- Feature removals
- Authentication flow changes
- Configuration format changes
- Dependency major version bumps with API changes
```

## Detection (During PRD Analysis)

Before writing a single story:
1. Read the PRD and identify potential breaking changes
2. Flag each one explicitly with type and impact
3. Wait for user approval on each
4. Document approved changes in prd.json under `approvedBreakingChanges`

```json
"approvedBreakingChanges": [
  {
    "type": "API contract",
    "description": "Rename /api/user to /api/users",
    "approvedAt": "2026-01-01T00:00:00Z",
    "migrationPlan": "Keep /api/user as deprecated alias for 30 days"
  }
]
```

## Approval Flow

```
Identify breaking change
        |
        v
Flag to user: type, what breaks, who is affected
        |
        v
Propose migration path
        |
        v
Wait for explicit approval
        |
       / \
      /   \
APPROVED  REJECTED
    |         |
    v         v
Document  Redesign
in prd    to avoid
```

## External API — Golden Rule

```
EXTERNAL APIs: NEVER BREAK BACKWARDS COMPATIBILITY

NEVER:
- Remove endpoints
- Change response structure
- Change required parameters
- Remove fields from responses
- Change authentication requirements

ALWAYS:
- ADD new optional fields
- ADD new versioned endpoints (/api/v2/)
- DEPRECATE with warning headers (Deprecation: true)
- MAINTAIN old endpoints until migration complete
- DOCUMENT migration paths in CHANGELOG
```

If a breaking change to an external API is truly unavoidable:
1. Create new versioned endpoint
2. Keep old endpoint working
3. Add `Deprecation: true` header to old endpoint
4. Document migration in CHANGELOG
5. Communicate deprecation timeline to consumers

## Test Compatibility

New tests must NOT break existing tests unless:

| Scenario | Required Action |
|----------|----------------|
| Valid refactor | Update test + code together, document why |
| Approved breaking change | Flag in planning, get explicit approval |
| Old test was wrong | Document why, get user approval |
| Unexpected failure | STOP — investigate and report before proceeding |
