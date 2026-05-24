import * as p from '@clack/prompts';
import pc from 'picocolors';
import fs from 'fs';
import path from 'path';
import { spawn } from 'child_process';
import { detectProject } from './project/detect.js';
import { setupNewProject } from './project/setup-new.js';
import { setupExistingProject } from './project/setup-existing.js';
import { parsePRD } from './prd/parser.js';
import { createBreakdown } from './prd/breakdown.js';
import { installHooks } from './hooks/install.js';
import { runSupervisor } from './agents/supervisor.js';
import { DEFAULT_CONFIG } from './config.js';

export async function main() {
  console.clear();
  
  p.intro(pc.bgMagenta(pc.white(' BART ')) + pc.dim(' — Autonomous Development Loop'));

  // Check Claude Code is installed
  const claudeOk = await checkClaude();
  if (!claudeOk) {
    p.log.error('Claude Code CLI not found.');
    p.log.info('Install from: https://claude.ai/code');
    p.log.info('Then run: claude login');
    process.exit(1);
  }
  p.log.success('Claude Code CLI detected');

  // Step 1: New or Existing Project?
  const projectType = await p.select({
    message: 'Project type:',
    options: [
      { value: 'new', label: 'New project', hint: 'Set up from scratch with best practices' },
      { value: 'existing', label: 'Existing project', hint: 'Add to existing codebase' },
    ],
  });

  if (p.isCancel(projectType)) {
    p.cancel('Cancelled');
    return;
  }

  let projectDir;
  let projectContext;

  if (projectType === 'new') {
    // New project setup
    const result = await setupNewProject();
    if (!result) return;
    projectDir = result.dir;
    projectContext = result.context;
  } else {
    // Existing project
    const result = await setupExistingProject();
    if (!result) return;
    projectDir = result.dir;
    projectContext = result.context;
  }

  // Step 2: Select PRD
  const prdPath = await selectPRD(projectDir);
  if (!prdPath) return;

  // Step 3: Configure agent models
  const models = await configureModels();
  if (!models) return;

  // Step 4: Select operating mode
  const mode = await p.select({
    message: 'Operating mode:',
    options: [
      { value: 'autonomous', label: 'Fully Autonomous', hint: 'Runs to completion, alerts only on blockers' },
      { value: 'assisted', label: 'Human Assisted', hint: 'Pauses at phase boundaries for approval' },
    ],
  });

  if (p.isCancel(mode)) {
    p.cancel('Cancelled');
    return;
  }

  // Step 5: Parse PRD and analyze for breaking changes
  const spin = p.spinner();
  spin.start('Parsing PRD...');

  const prdContent = fs.readFileSync(prdPath, 'utf-8');
  const prd = parsePRD(prdContent, path.basename(prdPath, '.md'));

  spin.stop(`Parsed: ${pc.cyan(prd.title)}`);

  // Show PRD summary
  p.note(
    [
      `${pc.bold('Title:')} ${prd.title}`,
      `${pc.bold('Requirements:')} ${prd.requirements.length}`,
      `${pc.bold('Acceptance Criteria:')} ${prd.acceptanceCriteria.length}`,
      '',
      `${pc.bold('Project:')} ${projectContext.name || path.basename(projectDir)}`,
      `${pc.bold('Type:')} ${projectType}`,
      `${pc.bold('Package Manager:')} ${projectContext.packageManager}`,
      projectContext.isMonorepo ? `${pc.bold('Monorepo:')} Yes` : '',
      projectContext.hasDocker ? `${pc.bold('Docker:')} Yes` : '',
      projectContext.hasTypeScript ? `${pc.bold('TypeScript:')} Yes` : '',
      '',
      `${pc.bold('Models:')}`,
      `  Supervisor: ${models.supervisor}`,
      `  Coder: ${models.coder}`,
      `  Reviewer: ${models.reviewer}`,
      `  Tester: ${models.tester}`,
    ].filter(Boolean).join('\n'),
    'Configuration'
  );

  // Step 6: Confirm
  const confirmed = await p.confirm({
    message: 'Ready to start autonomous development?',
  });

  if (p.isCancel(confirmed) || !confirmed) {
    p.cancel('Cancelled');
    return;
  }

  // Step 7: Setup project files and hooks
  spin.start('Setting up project...');

  // Create BART directory
  const bartDir = path.join(projectDir, '.bart');
  fs.mkdirSync(bartDir, { recursive: true });

  // Install code-enforced hooks
  await installHooks(projectDir);

  // Create tracking files
  createTrackingFiles(projectDir, prd, projectContext);

  spin.stop('Project setup complete');

  // Step 8: Breakdown PRD into phases and stories
  spin.start('Breaking down PRD into phases and stories...');

  const breakdown = await createBreakdown(prd, projectDir, models.supervisor);

  // Save breakdown
  fs.writeFileSync(
    path.join(bartDir, 'prd.json'),
    JSON.stringify(breakdown, null, 2)
  );

  spin.stop(`Created ${pc.cyan(breakdown.phases.length)} phases with ${pc.cyan(breakdown.stories.length)} stories`);

  // Check for breaking changes
  if (breakdown.breakingChanges && breakdown.breakingChanges.length > 0) {
    p.log.warn('Breaking changes detected:');
    for (const bc of breakdown.breakingChanges) {
      console.log(pc.yellow(`  ⚠️  ${bc.type}: ${bc.description}`));
      console.log(pc.dim(`     Impact: ${bc.impact}`));
    }

    const proceedWithBreaking = await p.confirm({
      message: 'Proceed with these breaking changes?',
      initialValue: false,
    });

    if (p.isCancel(proceedWithBreaking) || !proceedWithBreaking) {
      p.cancel('Cancelled due to breaking changes');
      return;
    }
  }

  // Show breakdown
  const breakdownLines = breakdown.phases.map(phase => {
    const phaseStories = breakdown.stories.filter(s => s.phase === phase.id);
    return `${pc.bold(phase.name)} — ${phaseStories.length} stories`;
  });
  p.note(breakdownLines.join('\n'), 'Phases');

  // Step 9: Run Supervisor
  p.log.step('Starting autonomous development...');
  console.log();

  await runSupervisor({
    projectDir,
    breakdown,
    models,
    mode,
    projectContext,
    prd,
  });

  p.outro(pc.green('✨ BART complete!'));
}

async function checkClaude() {
  return new Promise((resolve) => {
    const proc = spawn('claude', ['--version'], { stdio: 'pipe' });
    proc.on('close', (code) => resolve(code === 0));
    proc.on('error', () => resolve(false));
  });
}

async function selectPRD(projectDir) {
  const mdFiles = findMdFiles(projectDir);

  if (mdFiles.length === 0) {
    const customPath = await p.text({
      message: 'Enter path to your PRD file:',
      placeholder: './prd.md',
      validate: (value) => {
        if (!value) return 'Please enter a path';
        return undefined;
      },
    });

    if (p.isCancel(customPath)) {
      p.cancel('Cancelled');
      return null;
    }

    const resolved = path.resolve(projectDir, customPath);
    if (!fs.existsSync(resolved)) {
      p.log.error('File not found');
      return null;
    }

    return resolved;
  }

  const options = mdFiles.map(f => ({
    value: f,
    label: path.relative(projectDir, f),
  }));
  options.push({ value: '_custom', label: 'Enter custom path...' });

  const selected = await p.select({
    message: 'Select your PRD file:',
    options,
  });

  if (p.isCancel(selected)) {
    p.cancel('Cancelled');
    return null;
  }

  if (selected === '_custom') {
    const customPath = await p.text({
      message: 'Enter path:',
      placeholder: './prd.md',
    });

    if (p.isCancel(customPath)) {
      p.cancel('Cancelled');
      return null;
    }

    return path.resolve(projectDir, customPath);
  }

  return selected;
}

async function configureModels() {
  const useDefaults = await p.confirm({
    message: `Use default models? (Supervisor: opus, Coder: sonnet, Reviewer: sonnet, Tester: haiku)`,
    initialValue: true,
  });

  if (p.isCancel(useDefaults)) {
    p.cancel('Cancelled');
    return null;
  }

  if (useDefaults) {
    return DEFAULT_CONFIG.models;
  }

  const modelOptions = [
    { value: 'opus', label: 'Opus', hint: 'Most capable, best for complex tasks' },
    { value: 'sonnet', label: 'Sonnet', hint: 'Balanced, good for most tasks' },
    { value: 'haiku', label: 'Haiku', hint: 'Fastest, good for simple tasks' },
  ];

  const supervisor = await p.select({
    message: 'Supervisor model (orchestrates everything):',
    options: modelOptions,
    initialValue: 'opus',
  });
  if (p.isCancel(supervisor)) return null;

  const coder = await p.select({
    message: 'Coder model (implements stories):',
    options: modelOptions,
    initialValue: 'sonnet',
  });
  if (p.isCancel(coder)) return null;

  const reviewer = await p.select({
    message: 'Reviewer model (reviews phases, adds tests):',
    options: modelOptions,
    initialValue: 'sonnet',
  });
  if (p.isCancel(reviewer)) return null;

  const tester = await p.select({
    message: 'Tester model (final E2E review):',
    options: modelOptions,
    initialValue: 'haiku',
  });
  if (p.isCancel(tester)) return null;

  return { supervisor, coder, reviewer, tester };
}

function findMdFiles(dir, depth = 0, maxDepth = 2) {
  if (depth > maxDepth) return [];

  const results = [];

  try {
    const entries = fs.readdirSync(dir, { withFileTypes: true });

    for (const entry of entries) {
      if (entry.name.startsWith('.') || entry.name === 'node_modules') continue;

      const fullPath = path.join(dir, entry.name);

      if (entry.isFile() && entry.name.endsWith('.md')) {
        const lower = entry.name.toLowerCase();
        if (lower.includes('prd') || lower.includes('spec') || lower.includes('requirement')) {
          results.unshift(fullPath);
        } else if (!lower.includes('readme') && !lower.includes('changelog')) {
          results.push(fullPath);
        }
      } else if (entry.isDirectory()) {
        results.push(...findMdFiles(fullPath, depth + 1, maxDepth));
      }
    }
  } catch (e) {
    // Ignore
  }

  return results.slice(0, 10);
}

function createTrackingFiles(projectDir, prd, projectContext) {
  const bartDir = path.join(projectDir, '.bart');

  // progress.txt
  fs.writeFileSync(
    path.join(bartDir, 'progress.txt'),
    `# BART Progress Log\n\nStarted: ${new Date().toISOString()}\nPRD: ${prd.title}\n\n`
  );

  // Create CLAUDE.md if not exists
  if (!fs.existsSync(path.join(projectDir, 'CLAUDE.md'))) {
    fs.writeFileSync(
      path.join(projectDir, 'CLAUDE.md'),
      createClaudeMd(prd, projectContext)
    );
  }

  // Create AGENTS.md if not exists
  if (!fs.existsSync(path.join(projectDir, 'AGENTS.md'))) {
    fs.writeFileSync(
      path.join(projectDir, 'AGENTS.md'),
      createAgentsMd(projectContext)
    );
  }

  // Create ARCHITECTURE.md if not exists
  if (!fs.existsSync(path.join(projectDir, 'ARCHITECTURE.md'))) {
    fs.writeFileSync(
      path.join(projectDir, 'ARCHITECTURE.md'),
      createArchitectureMd(prd)
    );
  }
}

function createClaudeMd(prd, ctx) {
  const pkg = ctx.packageManager || 'npm';
  return `# ${prd.title}

## Quick Commands
- Test: \`${pkg} test\`
- Build: \`${pkg} run build\`
${ctx.hasTypeScript ? `- Typecheck: \`${pkg} run typecheck\`\n` : ''}- Lint: \`${pkg} run lint\`

## Before You Code
1. Read \`AGENTS.md\` — Conventions, patterns, gotchas
2. Read \`ARCHITECTURE.md\` — System design
3. Check \`.bart/progress.txt\` — Recent learnings (tail -50)
4. Check \`.bart/prd.json\` — Your assigned story

## TDD Workflow (MANDATORY)
1. Write failing test (RED)
2. Implement to pass (GREEN)
3. Refactor if needed
4. Run: \`${pkg} test && ${pkg} run typecheck\`
5. Only commit after ALL checks pass

## Hooks
Code-enforced hooks will block:
- Commits with failing tests
- SSH, docker exec, force push
- Skip-ci flags
`;
}

function createAgentsMd(ctx) {
  return `# Project Conventions

## Stack
- Package Manager: ${ctx.packageManager || 'npm'}
${ctx.hasTypeScript ? '- Language: TypeScript\n' : ''}- Testing: (to be determined)

## Patterns
<!-- Add patterns as you discover them -->

## Utilities
<!-- Document useful utilities here -->

## Gotchas
${ctx.isMonorepo ? '- MONOREPO: Check for duplicate types across packages\n' : ''}${ctx.hasDocker ? '- DOCKER: Regenerate lockfile after adding deps\n' : ''}`;
}

function createArchitectureMd(prd) {
  return `# Architecture

## Overview
${prd.title}

${prd.description || ''}

## Components
<!-- Document major components here -->

## Data Flow
<!-- Document data flow here -->

## Key Decisions
<!-- Document architectural decisions here -->
`;
}
