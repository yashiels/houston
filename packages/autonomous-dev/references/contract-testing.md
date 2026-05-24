# Contract Testing Reference

When a story generates config, API payloads, or structured output consumed by an external system, follow this guide.

## Why Contract Tests Are Necessary

Your unit tests validate YOUR code — they don't validate the consumer's schema. A config that compiles, serializes, and passes all unit tests can still crash at runtime if the shape doesn't match what the external system expects. The only way to be sure is to verify against the source of truth.

## Step 1 — Verify External Contracts Before Writing Code

**Before writing any implementation**, check: does this story generate config or output consumed by an external system?

If YES:
1. **Read the acceptance criteria for exact schemas** — the planner should have included verbatim expected output
2. **Find a working example** — grep the codebase for existing usage of this config/API format
3. **Consult official docs** — if the story references docs, use `web_fetch` to read them
4. **If no schema is provided**: check the external system's validation code or docs before guessing a structure

## Step 2 — Write a Contract Test

Write at least one contract test that asserts the EXACT output shape against the documented schema. This is separate from functional tests:

```typescript
// Contract test: validates output matches external system's expected schema
it('generates memorySearch config matching OpenClaw schema', () => {
  const config = generateConfig(/* ... */);

  // Assert exact structure — not just "has provider", but the full nesting
  expect(config).toMatchObject({
    provider: 'openai',
    model: expect.any(String),
    remote: {
      baseUrl: expect.any(String),
      apiKey: expect.any(String),
    },
  });

  // Negative assertions: keys that would be rejected by the consumer
  expect(config).not.toHaveProperty('apiKey');
  expect(config).not.toHaveProperty('baseUrl');
});
```

## Step 3 — Run External Validation (If Available)

If the external system provides a validation command, run it against a generated sample as part of the quality gate:

| System | Validation command |
|--------|-------------------|
| Docker Compose | `docker compose config` |
| Terraform | `terraform validate` |
| Kubernetes | `kubectl apply --dry-run=client` |

If no validation command is available, compare against a known-good example from the codebase.

## For Planners: Specifying Contracts in Stories

When writing acceptance criteria for stories that touch external systems:

1. Include the EXACT expected schema — not a description, but a verbatim JSON/YAML example
2. Add a contract test criterion: "A test validates the generated output against the documented schema"
3. Reference the authoritative docs URL in the story description

**Example acceptance criterion:**
```
Given vector memory is enabled, the generated config MUST match this exact structure:
{
  "agents": { "defaults": { "memorySearch": {
    "provider": "openai",
    "model": "text-embedding-3-small",
    "remote": { "baseUrl": "https://...", "apiKey": "sk-..." }
  }}}
}
```

Workers implement what the PRD specifies. Vague schema descriptions produce code that passes tests but fails at runtime. Be exact in the spec.
