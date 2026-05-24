import * as p from '@clack/prompts';
import pc from 'picocolors';
import fs from 'fs';
import path from 'path';
import { spawn } from 'child_process';
import { PROJECT_TEMPLATES } from '../config.js';

/**
 * Setup a new project from scratch with best practices
 */
export async function setupNewProject() {
  // Get project directory
  const projectDir = await p.text({
    message: 'Project directory:',
    placeholder: './my-project',
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

  // Check if directory exists
  if (fs.existsSync(resolvedDir) && fs.readdirSync(resolvedDir).length > 0) {
    const overwrite = await p.confirm({
      message: 'Directory is not empty. Continue anyway?',
      initialValue: false,
    });

    if (p.isCancel(overwrite) || !overwrite) {
      p.cancel('Cancelled');
      return null;
    }
  }

  // Select project template
  const template = await p.select({
    message: 'Project template:',
    options: Object.entries(PROJECT_TEMPLATES).map(([key, value]) => ({
      value: key,
      label: value.name,
    })),
  });

  if (p.isCancel(template)) {
    p.cancel('Cancelled');
    return null;
  }

  let projectConfig = { ...PROJECT_TEMPLATES[template] };

  // For custom, ask additional questions
  if (template === 'custom') {
    const pkgManager = await p.select({
      message: 'Package manager:',
      options: [
        { value: 'pnpm', label: 'pnpm', hint: 'Recommended' },
        { value: 'npm', label: 'npm' },
        { value: 'yarn', label: 'yarn' },
        { value: 'bun', label: 'bun' },
      ],
    });
    if (p.isCancel(pkgManager)) return null;

    const useTs = await p.confirm({
      message: 'Use TypeScript?',
      initialValue: true,
    });
    if (p.isCancel(useTs)) return null;

    const testing = await p.select({
      message: 'Testing framework:',
      options: [
        { value: 'vitest', label: 'Vitest', hint: 'Fast, modern' },
        { value: 'jest', label: 'Jest' },
        { value: 'none', label: 'None (add later)' },
      ],
    });
    if (p.isCancel(testing)) return null;

    projectConfig = {
      ...projectConfig,
      packageManager: pkgManager,
      typescript: useTs,
      testing,
    };
  }

  // Create directory
  fs.mkdirSync(resolvedDir, { recursive: true });

  const spin = p.spinner();
  spin.start('Setting up project structure...');

  // Create project structure
  await createProjectStructure(resolvedDir, projectConfig, template);

  spin.stop('Project structure created');

  // Initialize git
  spin.start('Initializing git...');
  await runCommand('git', ['init'], resolvedDir);
  spin.stop('Git initialized');

  // Install dependencies
  if (projectConfig.packageManager) {
    spin.start(`Installing dependencies with ${projectConfig.packageManager}...`);
    try {
      await runCommand(projectConfig.packageManager, ['install'], resolvedDir);
      spin.stop('Dependencies installed');
    } catch (e) {
      spin.stop('Dependency installation failed (you may need to run it manually)');
    }
  }

  // Initial commit
  try {
    await runCommand('git', ['add', '-A'], resolvedDir);
    await runCommand('git', ['commit', '-m', 'Initial commit (BART setup)'], resolvedDir);
  } catch {}

  p.log.success(`Project created at ${pc.cyan(resolvedDir)}`);

  return {
    dir: resolvedDir,
    context: {
      name: path.basename(resolvedDir),
      packageManager: projectConfig.packageManager || 'npm',
      hasTypeScript: projectConfig.typescript || false,
      isMonorepo: false,
      hasDocker: false,
      hasTests: projectConfig.testing !== 'none',
    },
  };
}

async function createProjectStructure(dir, config, template) {
  // Create .gitignore
  fs.writeFileSync(
    path.join(dir, '.gitignore'),
    `# Dependencies
node_modules/

# Build output
dist/
build/
.next/
out/

# Environment
.env
.env.local
.env.*.local

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Testing
coverage/

# Logs
*.log
npm-debug.log*

# BART
.bart/
`
  );

  // Create src directory
  fs.mkdirSync(path.join(dir, 'src'), { recursive: true });

  // Create tests directory
  fs.mkdirSync(path.join(dir, 'tests'), { recursive: true });

  // Create package.json
  const packageJson = createPackageJson(config, template, path.basename(dir));
  fs.writeFileSync(
    path.join(dir, 'package.json'),
    JSON.stringify(packageJson, null, 2)
  );

  // Create TypeScript config if needed
  if (config.typescript) {
    fs.writeFileSync(
      path.join(dir, 'tsconfig.json'),
      JSON.stringify(createTsConfig(template), null, 2)
    );
  }

  // Create .editorconfig
  fs.writeFileSync(
    path.join(dir, '.editorconfig'),
    `root = true

[*]
indent_style = space
indent_size = 2
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.md]
trim_trailing_whitespace = false
`
  );

  // Create README
  fs.writeFileSync(
    path.join(dir, 'README.md'),
    `# ${path.basename(dir)}

## Setup

\`\`\`bash
${config.packageManager || 'npm'} install
\`\`\`

## Development

\`\`\`bash
${config.packageManager || 'npm'} run dev
\`\`\`

## Testing

\`\`\`bash
${config.packageManager || 'npm'} test
\`\`\`
`
  );

  // Create basic source file
  const ext = config.typescript ? 'ts' : 'js';
  fs.writeFileSync(
    path.join(dir, 'src', `index.${ext}`),
    `// ${path.basename(dir)}
// Created by BART

export function main() {
  console.log('Hello from ${path.basename(dir)}!');
}

main();
`
  );

  // Create basic test file
  fs.writeFileSync(
    path.join(dir, 'tests', `index.test.${ext}`),
    `import { describe, it, expect } from 'vitest';

describe('${path.basename(dir)}', () => {
  it('should work', () => {
    expect(true).toBe(true);
  });
});
`
  );
}

function createPackageJson(config, template, name) {
  const pkg = {
    name: name.toLowerCase().replace(/\s+/g, '-'),
    version: '0.1.0',
    description: '',
    type: 'module',
    main: config.typescript ? 'dist/index.js' : 'src/index.js',
    scripts: {
      dev: 'node --watch src/index.js',
      build: config.typescript ? 'tsc' : 'echo "No build step"',
      start: config.typescript ? 'node dist/index.js' : 'node src/index.js',
    },
    keywords: [],
    author: '',
    license: 'MIT',
    devDependencies: {},
  };

  if (config.typescript) {
    pkg.devDependencies['typescript'] = '^5.4.0';
    pkg.devDependencies['@types/node'] = '^20.0.0';
    pkg.scripts.typecheck = 'tsc --noEmit';
    pkg.scripts.dev = 'tsx watch src/index.ts';
    pkg.devDependencies['tsx'] = '^4.7.0';
  }

  if (config.testing === 'vitest') {
    pkg.devDependencies['vitest'] = '^2.0.0';
    pkg.scripts.test = 'vitest run';
    pkg.scripts['test:watch'] = 'vitest';
  } else if (config.testing === 'jest') {
    pkg.devDependencies['jest'] = '^29.0.0';
    if (config.typescript) {
      pkg.devDependencies['ts-jest'] = '^29.0.0';
      pkg.devDependencies['@types/jest'] = '^29.0.0';
    }
    pkg.scripts.test = 'jest';
  }

  // Add ESLint
  pkg.devDependencies['eslint'] = '^9.0.0';
  pkg.scripts.lint = 'eslint src/';

  return pkg;
}

function createTsConfig(template) {
  return {
    compilerOptions: {
      target: 'ES2022',
      module: 'NodeNext',
      moduleResolution: 'NodeNext',
      lib: ['ES2022'],
      outDir: './dist',
      rootDir: './src',
      strict: true,
      esModuleInterop: true,
      skipLibCheck: true,
      forceConsistentCasingInFileNames: true,
      declaration: true,
      declarationMap: true,
      sourceMap: true,
    },
    include: ['src/**/*'],
    exclude: ['node_modules', 'dist', 'tests'],
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
