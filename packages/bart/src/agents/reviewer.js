import pc from 'picocolors';
import fs from 'fs';
import { runClaudeAutonomous } from './claude.js';
import { DEFAULT_CONFIG } from '../config.js';

/**
 * Review agent that runs after each phase
 * Adds smoke tests, API tests, UI tests, integration tests
 */
export async function runPhaseReview({ phase, projectDir, models, prd, progressPath }) {
  const prompt = buildReviewPrompt(phase, prd);

  const result = await runClaudeAutonomous({
    prompt,
    model: models.reviewer,
    cwd: projectDir,
    timeout: DEFAULT_CONFIG.timeouts.review,
  });

  // Log to progress
  const timestamp = new Date().toISOString().slice(11, 19);
  fs.appendFileSync(progressPath, `\n[${timestamp}] REVIEW: Phase ${phase.name}\n`);

  if (result.success) {
    const testsAdded = extractTestsAdded(result.output);
    if (testsAdded > 0) {
      fs.appendFileSync(progressPath, `  Added ${testsAdded} tests\n`);
      console.log(pc.dim(`  Added ${testsAdded} tests`));
    }
  } else {
    fs.appendFileSync(progressPath, `  Review completed with warnings\n`);
  }

  return result;
}

function buildReviewPrompt(phase, prd) {
  return `You are a REVIEW AGENT for: ${prd.title}

## Phase Completed: ${phase.name}
${phase.description}

## Your Task

1. **Verify All Tests Pass**
   \`\`\`bash
   npm test
   npm run typecheck
   npm run build
   \`\`\`

2. **Add Missing Tests**
   For each new feature in this phase, ensure we have:

   **Smoke Tests:**
   - Happy path works
   - Basic error handling

   **API Tests (if API endpoints added):**
   - Request/response validation
   - Auth checks
   - Error responses
   - Backwards compatibility

   **UI Tests (if UI components added):**
   - Component renders
   - User interactions work
   - Accessibility basics

   **Integration Tests:**
   - Cross-component flows
   - API → UI paths

3. **Check Test Compatibility**
   - New tests must NOT break existing tests
   - If old tests fail, investigate why

4. **Update Documentation**
   - Add patterns discovered to AGENTS.md
   - Update ARCHITECTURE.md if structure changed

## Rules
- Don't skip adding tests
- Don't hardcode values to pass tests
- All tests must actually test something meaningful

## Output
When complete:
REVIEW_COMPLETE
TESTS_ADDED: <number>
ISSUES_FOUND: <number>

If blocked:
REVIEW_BLOCKED: <reason>`;
}

function extractTestsAdded(output) {
  const match = output.match(/TESTS_ADDED:\s*(\d+)/i);
  return match ? parseInt(match[1], 10) : 0;
}
