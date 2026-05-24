import pc from 'picocolors';
import fs from 'fs';
import { runClaudeAutonomous } from './claude.js';
import { DEFAULT_CONFIG } from '../config.js';

/**
 * Final E2E review agent
 * Comprehensive verification before completion
 */
export async function runFinalReview({ projectDir, breakdown, models, prd, progressPath }) {
  const prompt = buildFinalReviewPrompt(breakdown, prd);

  const result = await runClaudeAutonomous({
    prompt,
    model: models.tester,
    cwd: projectDir,
    timeout: DEFAULT_CONFIG.timeouts.finalReview,
  });

  // Log to progress
  const timestamp = new Date().toISOString().slice(11, 19);
  fs.appendFileSync(progressPath, `\n[${timestamp}] FINAL E2E REVIEW\n`);

  if (result.success) {
    fs.appendFileSync(progressPath, `  All checks passed\n`);
  } else {
    fs.appendFileSync(progressPath, `  Review completed with warnings: ${result.error || 'Unknown'}\n`);
  }

  return result;
}

function buildFinalReviewPrompt(breakdown, prd) {
  const phases = breakdown.phases.map(p => `- ${p.name}`).join('\n');
  const storiesDone = breakdown.stories.filter(s => s.passes).length;
  const storiesTotal = breakdown.stories.length;

  return `You are the FINAL E2E REVIEW AGENT for: ${prd.title}

## Summary
- Phases: ${breakdown.phases.length}
${phases}
- Stories: ${storiesDone}/${storiesTotal} complete

## Your Comprehensive Checklist

### 1. Full Test Suite
\`\`\`bash
npm test
npm run typecheck
npm run build
\`\`\`
All must pass with zero errors.

### 2. E2E Tests
Run any end-to-end tests:
\`\`\`bash
npm run test:e2e || echo "No E2E tests configured"
\`\`\`

### 3. Build Verification
\`\`\`bash
npm run build
ls -la dist/ || ls -la build/ || ls -la .next/
\`\`\`
Verify build output exists and is valid.

### 4. Integration Check
- All imports resolve correctly
- No circular dependencies
- Environment variables documented

### 5. API Backwards Compatibility (if applicable)
\`\`\`bash
git diff main...HEAD --name-only | grep -E "(api|routes)"
\`\`\`
Verify:
- ✅ No endpoints removed
- ✅ No response structure changes
- ✅ New fields are optional

### 6. Documentation Review
- README is up to date
- AGENTS.md has patterns discovered
- ARCHITECTURE.md reflects current state

### 7. Security Check
- No hardcoded secrets
- No sensitive data in logs
- Auth checks in place

### 8. Deployment Readiness
- Dependencies are locked
- Build produces deployable artifacts
- No dev-only code in production paths

## Output
When complete:
E2E_REVIEW_COMPLETE
TESTS_TOTAL: <number>
TESTS_PASSING: <number>
ISSUES_FOUND: <number>
READY_FOR_MERGE: yes/no

If critical issues:
E2E_REVIEW_BLOCKED: <reason>`;
}
