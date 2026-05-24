import fs from 'fs';
import path from 'path';
import { runClaude } from '../agents/claude.js';
import { formatPRDForPrompt } from './parser.js';

/**
 * Use Claude to break down a PRD into phases and stories
 */
export async function createBreakdown(prd, projectDir, model) {
  const prompt = buildBreakdownPrompt(prd);

  // Run Claude to get breakdown
  const response = await runClaude({
    prompt,
    model,
    cwd: projectDir,
  });

  // Parse the response
  return parseBreakdownResponse(response, prd);
}

function buildBreakdownPrompt(prd) {
  return `You are analyzing a PRD to create an implementation plan.

${formatPRDForPrompt(prd)}

## Your Task

1. **Identify Breaking Changes**: Look for API changes, database schema changes, interface changes that could break existing code. List them explicitly.

2. **Create Phases**: Group related work into logical phases. Each phase should be independently deployable.

3. **Create Stories**: Break each phase into small stories (15-30 min each). Each story must:
   - Be completable in one coding session
   - Have clear acceptance criteria
   - Include what test to write first (TDD)

## Output Format

Return ONLY valid JSON (no markdown, no explanation):

{
  "breakingChanges": [
    {
      "type": "API Change",
      "description": "What is changing",
      "impact": "What could break",
      "migration": "How to handle it"
    }
  ],
  "phases": [
    {
      "id": "PHASE-1",
      "name": "Foundation",
      "description": "Core setup and data models"
    }
  ],
  "stories": [
    {
      "id": "STORY-001",
      "phase": "PHASE-1",
      "title": "Short title (max 60 chars)",
      "description": "What to implement",
      "acceptanceCriteria": ["Criterion 1", "Criterion 2"],
      "testFirst": "Describe the test to write first",
      "estimatedMinutes": 20
    }
  ]
}

## Rules

1. Stories must be SMALL (15-30 minutes)
2. Order by dependency (foundational first)
3. Each story must have testFirst defined
4. Include clear acceptance criteria
5. Use empty array for breakingChanges if none detected

Output ONLY the JSON.`;
}

function parseBreakdownResponse(response, prd) {
  // Try to extract JSON
  let jsonStr = response;

  // Check for JSON in code blocks
  const codeBlockMatch = response.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (codeBlockMatch) {
    jsonStr = codeBlockMatch[1];
  }

  // Try to find raw JSON
  const rawJsonMatch = response.match(/\{[\s\S]*"phases"[\s\S]*"stories"[\s\S]*\}/);
  if (rawJsonMatch) {
    jsonStr = rawJsonMatch[0];
  }

  try {
    const parsed = JSON.parse(jsonStr.trim());

    return {
      prdTitle: prd.title,
      createdAt: new Date().toISOString(),
      breakingChanges: parsed.breakingChanges || [],
      phases: parsed.phases || [],
      stories: (parsed.stories || []).map((s, i) => ({
        ...s,
        id: s.id || `STORY-${String(i + 1).padStart(3, '0')}`,
        status: 'pending',
        passes: false,
      })),
    };
  } catch (e) {
    // Fallback: create simple breakdown
    console.error('Failed to parse breakdown response:', e.message);

    return {
      prdTitle: prd.title,
      createdAt: new Date().toISOString(),
      breakingChanges: [],
      phases: [
        { id: 'PHASE-1', name: 'Implementation', description: 'Main implementation' }
      ],
      stories: [
        {
          id: 'STORY-001',
          phase: 'PHASE-1',
          title: `Implement ${prd.title}`,
          description: prd.description || prd.title,
          acceptanceCriteria: prd.acceptanceCriteria.length > 0
            ? prd.acceptanceCriteria
            : ['Implementation complete', 'Tests pass'],
          testFirst: 'Write a test for the main functionality',
          estimatedMinutes: 30,
          status: 'pending',
          passes: false,
        },
      ],
    };
  }
}
