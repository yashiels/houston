import * as p from '@clack/prompts';
import pc from 'picocolors';
import fs from 'fs';
import path from 'path';
import { runClaudeAutonomous } from './claude.js';
import { runPhaseReview } from './reviewer.js';
import { runFinalReview } from './tester.js';
import { DEFAULT_CONFIG } from '../config.js';

/**
 * Supervisor agent that orchestrates the entire development process
 */
export async function runSupervisor({ projectDir, breakdown, models, mode, projectContext, prd }) {
  const bartDir = path.join(projectDir, '.bart');
  const prdPath = path.join(bartDir, 'prd.json');
  const progressPath = path.join(bartDir, 'progress.txt');

  let progressInterval;

  // Start progress reporting (every 5 min in autonomous mode)
  if (mode === 'autonomous') {
    progressInterval = setInterval(() => {
      const current = loadBreakdown(prdPath);
      reportProgress(current);
    }, DEFAULT_CONFIG.progressInterval);
  }

  try {
    // Execute each phase
    for (const phase of breakdown.phases) {
      console.log();
      console.log(pc.bold(pc.cyan(`━━━ Phase: ${phase.name} ━━━`)));
      console.log(pc.dim(phase.description));
      console.log();

      const phaseStories = breakdown.stories.filter(s => s.phase === phase.id);

      // Execute stories in this phase
      for (const story of phaseStories) {
        if (story.passes) {
          console.log(pc.dim(`  ✓ ${story.id}: ${story.title} (already done)`));
          continue;
        }

        // Execute story with fresh Claude context
        const result = await executeStory({
          story,
          projectDir,
          models,
          prd,
          projectContext,
          progressPath,
        });

        // Update breakdown
        const current = loadBreakdown(prdPath);
        const storyIndex = current.stories.findIndex(s => s.id === story.id);
        if (storyIndex !== -1) {
          current.stories[storyIndex] = {
            ...current.stories[storyIndex],
            ...result,
          };
          saveBreakdown(prdPath, current);
        }

        if (!result.passes) {
          // Story failed
          console.log(pc.red(`  ✗ ${story.id}: ${story.title}`));
          
          if (mode === 'assisted') {
            const action = await p.select({
              message: `Story ${story.id} failed. What to do?`,
              options: [
                { value: 'retry', label: 'Retry this story' },
                { value: 'skip', label: 'Skip and continue' },
                { value: 'abort', label: 'Abort execution' },
              ],
            });

            if (p.isCancel(action) || action === 'abort') {
              throw new Error('Aborted by user');
            }

            if (action === 'retry') {
              // Re-queue this story (simple approach: decrement index)
              phaseStories.unshift(story);
              continue;
            }
            // skip: just continue to next story
          }
        } else {
          console.log(pc.green(`  ✓ ${story.id}: ${story.title}`));
        }
      }

      // Phase review
      console.log();
      console.log(pc.dim('Running phase review...'));

      await runPhaseReview({
        phase,
        projectDir,
        models,
        prd,
        progressPath,
      });

      console.log(pc.green(`✓ Phase ${phase.name} complete`));

      // In assisted mode, pause for approval
      if (mode === 'assisted') {
        const continuePhase = await p.confirm({
          message: `Phase "${phase.name}" complete. Continue to next phase?`,
          initialValue: true,
        });

        if (p.isCancel(continuePhase) || !continuePhase) {
          throw new Error('Paused by user after phase');
        }
      }
    }

    // Final E2E review
    console.log();
    console.log(pc.bold(pc.cyan('━━━ Final E2E Review ━━━')));

    await runFinalReview({
      projectDir,
      breakdown,
      models,
      prd,
      progressPath,
    });

    console.log(pc.green('✓ Final review complete'));

    // Report final status
    const final = loadBreakdown(prdPath);
    reportFinalStatus(final);

  } finally {
    if (progressInterval) {
      clearInterval(progressInterval);
    }
  }
}

async function executeStory({ story, projectDir, models, prd, projectContext, progressPath }) {
  const spin = p.spinner();
  spin.start(`${story.id}: ${story.title}`);

  const prompt = buildStoryPrompt(story, prd, projectContext);

  let attempts = 0;
  const maxAttempts = DEFAULT_CONFIG.retries.maxPerStory;

  while (attempts < maxAttempts) {
    attempts++;

    try {
      const result = await runClaudeAutonomous({
        prompt,
        model: models.coder,
        cwd: projectDir,
        timeout: DEFAULT_CONFIG.timeouts.story,
      });

      // Append to progress
      const timestamp = new Date().toISOString().slice(11, 19);
      fs.appendFileSync(progressPath, `\n[${timestamp}] ${story.id}: ${story.title}\n`);

      if (result.success && (result.output.includes('STORY_COMPLETE') || !result.error)) {
        // Extract learnings
        const learnings = extractLearnings(result.output);
        if (learnings) {
          fs.appendFileSync(progressPath, `  Learning: ${learnings}\n`);
        }

        spin.stop(pc.green(`✓ ${story.id}: ${story.title}`));

        return {
          passes: true,
          status: 'done',
          completedAt: new Date().toISOString(),
          attempts,
        };
      }

      // Check if blocked
      if (result.output.includes('STORY_BLOCKED') || result.error) {
        const error = result.error || extractBlockReason(result.output);
        fs.appendFileSync(progressPath, `  Blocked: ${error}\n`);

        if (attempts < maxAttempts) {
          spin.message(`${story.id}: Retrying (attempt ${attempts + 1}/${maxAttempts})...`);
          continue;
        }

        spin.stop(pc.red(`✗ ${story.id}: ${story.title} (blocked)`));

        return {
          passes: false,
          status: 'blocked',
          error,
          attempts,
        };
      }

    } catch (e) {
      fs.appendFileSync(progressPath, `  Error: ${e.message}\n`);

      if (attempts < maxAttempts) {
        spin.message(`${story.id}: Error, retrying (attempt ${attempts + 1}/${maxAttempts})...`);
        continue;
      }

      spin.stop(pc.red(`✗ ${story.id}: ${story.title} (error)`));

      return {
        passes: false,
        status: 'error',
        error: e.message,
        attempts,
      };
    }
  }

  spin.stop(pc.red(`✗ ${story.id}: ${story.title} (max attempts)`));

  return {
    passes: false,
    status: 'max_attempts',
    attempts,
  };
}

function buildStoryPrompt(story, prd, projectContext) {
  const pkg = projectContext.packageManager || 'npm';

  return `You are implementing a story for: ${prd.title}

## Bootstrap (DO THIS FIRST)
1. Read CLAUDE.md for project overview
2. Read AGENTS.md for conventions
3. Read ARCHITECTURE.md for system design
4. Check .bart/progress.txt (last 50 lines) for recent learnings
5. Check .bart/prd.json for story details

## Your Story: ${story.id}
**Title:** ${story.title}
**Description:** ${story.description}

## Acceptance Criteria
${story.acceptanceCriteria.map(c => `- [ ] ${c}`).join('\n')}

## TDD Approach (MANDATORY)
**Write this test first:** ${story.testFirst}

1. Write the failing test (RED)
2. Run: \`${pkg} test\` - confirm it fails
3. Write minimal code to pass (GREEN)
4. Run: \`${pkg} test\` - confirm it passes
5. Refactor if needed
6. Run full verification: \`${pkg} test && ${pkg} run typecheck\`

## Pre-Commit Verification
Before committing:
- \`${pkg} test\` must pass
- \`${pkg} run typecheck\` must pass (if TypeScript)
- \`${pkg} run build\` must pass (if build exists)

## Commit Format
\`\`\`bash
git add -A
git commit -m "${story.id}: ${story.title}"
\`\`\`

## Context Rules
- Keep context usage under 50%
- Read files on-demand, not upfront
- Use grep to find relevant files

## Output
When complete, output:
STORY_COMPLETE
LEARNING: <one line summary of what you learned>

If blocked:
STORY_BLOCKED: <reason>`;
}

function extractLearnings(output) {
  const match = output.match(/LEARNING:\s*(.+)/i);
  return match ? match[1].trim() : null;
}

function extractBlockReason(output) {
  const match = output.match(/STORY_BLOCKED:\s*(.+)/i);
  return match ? match[1].trim() : 'Unknown reason';
}

function loadBreakdown(prdPath) {
  return JSON.parse(fs.readFileSync(prdPath, 'utf-8'));
}

function saveBreakdown(prdPath, breakdown) {
  fs.writeFileSync(prdPath, JSON.stringify(breakdown, null, 2));
}

function reportProgress(breakdown) {
  const total = breakdown.stories.length;
  const done = breakdown.stories.filter(s => s.passes).length;
  const blocked = breakdown.stories.filter(s => s.status === 'blocked').length;
  const percent = Math.round((done / total) * 100);

  console.log();
  console.log(pc.dim('─'.repeat(50)));
  console.log(pc.bold(`📊 Progress: ${done}/${total} (${percent}%)`));
  if (blocked > 0) {
    console.log(pc.yellow(`⚠️  Blocked: ${blocked}`));
  }
  console.log(pc.dim('─'.repeat(50)));
  console.log();
}

function reportFinalStatus(breakdown) {
  const total = breakdown.stories.length;
  const done = breakdown.stories.filter(s => s.passes).length;
  const blocked = breakdown.stories.filter(s => s.status === 'blocked').length;

  console.log();
  console.log(pc.bold('═'.repeat(50)));
  console.log(pc.bold(pc.green(`✨ BART Complete: ${done}/${total} stories`)));
  console.log(`   Phases: ${breakdown.phases.length}`);
  console.log(`   Stories: ${done} done, ${blocked} blocked, ${total - done - blocked} skipped`);
  console.log(pc.bold('═'.repeat(50)));
  console.log();
}
