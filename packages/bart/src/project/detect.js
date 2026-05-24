import fs from 'fs';
import path from 'path';

/**
 * Detect project configuration from existing files
 */
export function detectProject(projectDir) {
  const context = {
    name: path.basename(projectDir),
    packageManager: detectPackageManager(projectDir),
    isMonorepo: detectMonorepo(projectDir),
    hasDocker: detectDocker(projectDir),
    hasTypeScript: detectTypeScript(projectDir),
    hasTests: detectTests(projectDir),
    framework: detectFramework(projectDir),
    testCommand: null,
    buildCommand: null,
    typecheckCommand: null,
  };

  // Set commands based on detection
  const pkg = context.packageManager;
  context.testCommand = `${pkg} test`;
  context.buildCommand = `${pkg} run build`;
  
  if (context.hasTypeScript) {
    context.typecheckCommand = `${pkg} run typecheck`;
  }

  return context;
}

function detectPackageManager(dir) {
  if (fs.existsSync(path.join(dir, 'pnpm-lock.yaml'))) return 'pnpm';
  if (fs.existsSync(path.join(dir, 'yarn.lock'))) return 'yarn';
  if (fs.existsSync(path.join(dir, 'bun.lockb'))) return 'bun';
  if (fs.existsSync(path.join(dir, 'package-lock.json'))) return 'npm';
  if (fs.existsSync(path.join(dir, 'package.json'))) return 'npm';
  return 'npm';
}

function detectMonorepo(dir) {
  const indicators = [
    'pnpm-workspace.yaml',
    'lerna.json',
    'turbo.json',
    'nx.json',
    'rush.json',
  ];

  for (const file of indicators) {
    if (fs.existsSync(path.join(dir, file))) return true;
  }

  // Check package.json for workspaces
  const pkgPath = path.join(dir, 'package.json');
  if (fs.existsSync(pkgPath)) {
    try {
      const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf-8'));
      if (pkg.workspaces) return true;
    } catch {}
  }

  return false;
}

function detectDocker(dir) {
  const indicators = [
    'Dockerfile',
    'docker-compose.yml',
    'docker-compose.yaml',
    'compose.yml',
    'compose.yaml',
  ];

  for (const file of indicators) {
    if (fs.existsSync(path.join(dir, file))) return true;
  }

  return fs.existsSync(path.join(dir, 'docker'));
}

function detectTypeScript(dir) {
  return fs.existsSync(path.join(dir, 'tsconfig.json'));
}

function detectTests(dir) {
  const pkgPath = path.join(dir, 'package.json');
  if (fs.existsSync(pkgPath)) {
    try {
      const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf-8'));
      if (pkg.scripts && pkg.scripts.test) return true;
    } catch {}
  }

  // Check for test directories
  const testDirs = ['test', 'tests', '__tests__', 'spec'];
  for (const d of testDirs) {
    if (fs.existsSync(path.join(dir, d))) return true;
  }

  return false;
}

function detectFramework(dir) {
  const pkgPath = path.join(dir, 'package.json');
  if (!fs.existsSync(pkgPath)) return null;

  try {
    const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf-8'));
    const deps = { ...pkg.dependencies, ...pkg.devDependencies };

    if (deps['next']) return 'nextjs';
    if (deps['express']) return 'express';
    if (deps['fastify']) return 'fastify';
    if (deps['hono']) return 'hono';
    if (deps['react']) return 'react';
    if (deps['vue']) return 'vue';
    if (deps['svelte']) return 'svelte';
  } catch {}

  return null;
}

/**
 * Get project-specific gotchas
 */
export function getProjectGotchas(context) {
  const gotchas = [];

  if (context.isMonorepo) {
    gotchas.push('MONOREPO: Check for duplicate type definitions across packages');
    gotchas.push('MONOREPO: Build shared packages before consumers');
    gotchas.push('MONOREPO: Each package may have its own tsconfig');
  }

  if (context.hasDocker) {
    gotchas.push('DOCKER: Regenerate lockfile after adding deps (frozen-lockfile in build)');
    gotchas.push('DOCKER: Run docker compose build before marking phase complete');
    gotchas.push('DOCKER: Verify UI components exist before importing');
  }

  if (context.hasTypeScript && context.isMonorepo) {
    gotchas.push('TYPESCRIPT: Run tsc --noEmit in ALL packages');
    gotchas.push('TYPESCRIPT: Path aliases resolve differently per package');
  }

  return gotchas;
}
