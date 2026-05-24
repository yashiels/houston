import * as p from '@clack/prompts';
import pc from 'picocolors';
import fs from 'fs';
import path from 'path';
import { spawn } from 'child_process';
import { detectProject, getProjectGotchas } from './detect.js';

/**
 * Setup for an existing project
 */
export async function setupExistingProject() {
  // Get project directory
  const projectDir = await p.text({
    message: 'Project directory:',
    placeholder: './',
    initialValue: './',
    validate: (value) => {
      if (!value) return 'Please enter a directory';
      return undefined;
    },
  });

  if (p.isCancel(projectDir)) {
    p.cancel('Cancelled');
    return null;
  }

  const resolvedDir = path.resolve(projectDir);

  if (!fs.existsSync(resolvedDir)) {
    p.log.error('Directory does not exist');
    return null;
  }

  const spin = p.spinner();
  spin.start('Analyzing project...');

  // Auto-detect project configuration
  const context = detectProject(resolvedDir);

  spin.stop('Project analyzed');

  // Show detected configuration
  const detectedInfo = [
    `${pc.bold('Directory:')} ${resolvedDir}`,
    `${pc.bold('Package Manager:')} ${context.packageManager}`,
    `${pc.bold('TypeScript:')} ${context.hasTypeScript ? 'Yes' : 'No'}`,
    `${pc.bold('Monorepo:')} ${context.isMonorepo ? 'Yes' : 'No'}`,
    `${pc.bold('Docker:')} ${context.hasDocker ? 'Yes' : 'No'}`,
    `${pc.bold('Tests:')} ${context.hasTests ? 'Detected' : 'Not found'}`,
    context.framework ? `${pc.bold('Framework:')} ${context.framework}` : null,
  ].filter(Boolean);

  p.note(detectedInfo.join('\n'), 'Detected Configuration');

  // Show gotchas
  const gotchas = getProjectGotchas(context);
  if (gotchas.length > 0) {
    p.log.warn('Project-specific considerations:');
    for (const g of gotchas) {
      console.log(pc.yellow(`  ⚠️  ${g}`));
    }
  }

  // Confirm or modify
  const confirmConfig = await p.confirm({
    message: 'Is this configuration correct?',
    initialValue: true,
  });

  if (p.isCancel(confirmConfig)) {
    p.cancel('Cancelled');
    return null;
  }

  if (!confirmConfig) {
    // Allow overrides
    const overrides = await p.group({
      packageManager: () => p.select({
        message: 'Package manager:',
        options: [
          { value: 'pnpm', label: 'pnpm' },
          { value: 'npm', label: 'npm' },
          { value: 'yarn', label: 'yarn' },
          { value: 'bun', label: 'bun' },
        ],
        initialValue: context.packageManager,
      }),
      hasTypeScript: () => p.confirm({
        message: 'Uses TypeScript?',
        initialValue: context.hasTypeScript,
      }),
      isMonorepo: () => p.confirm({
        message: 'Is a monorepo?',
        initialValue: context.isMonorepo,
      }),
      hasDocker: () => p.confirm({
        message: 'Uses Docker?',
        initialValue: context.hasDocker,
      }),
    });

    if (p.isCancel(overrides)) {
      p.cancel('Cancelled');
      return null;
    }

    Object.assign(context, overrides);
  }

  // Initialize git if needed
  if (!fs.existsSync(path.join(resolvedDir, '.git'))) {
    const initGit = await p.confirm({
      message: 'Initialize git repository?',
      initialValue: true,
    });

    if (!p.isCancel(initGit) && initGit) {
      spin.start('Initializing git...');
      await runCommand('git', ['init'], resolvedDir);
      spin.stop('Git initialized');
    }
  }

  // Create feature branch
  const branchName = await p.text({
    message: 'Feature branch name:',
    placeholder: 'feature/bart-dev',
    initialValue: 'feature/bart-dev',
  });

  if (p.isCancel(branchName)) {
    p.cancel('Cancelled');
    return null;
  }

  try {
    // Check if branch exists
    await runCommand('git', ['rev-parse', '--verify', branchName], resolvedDir);
    // Branch exists, check it out
    await runCommand('git', ['checkout', branchName], resolvedDir);
    p.log.info(`Checked out existing branch: ${branchName}`);
  } catch {
    // Create new branch
    try {
      await runCommand('git', ['checkout', '-b', branchName], resolvedDir);
      p.log.success(`Created branch: ${branchName}`);
    } catch (e) {
      p.log.warn(`Could not create branch (git may need initial commit)`);
    }
  }

  return {
    dir: resolvedDir,
    context,
  };
}

function runCommand(cmd, args, cwd) {
  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, args, { cwd, stdio: 'pipe' });
    proc.on('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${cmd} exited with code ${code}`));
    });
    proc.on('error', reject);
  });
}
