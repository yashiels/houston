// Default configuration
export const DEFAULT_CONFIG = {
  models: {
    supervisor: 'opus',
    coder: 'sonnet',
    reviewer: 'sonnet',
    tester: 'haiku',
  },
  timeouts: {
    story: 30 * 60 * 1000,    // 30 minutes per story
    phase: 60 * 60 * 1000,    // 1 hour per phase
    review: 30 * 60 * 1000,   // 30 minutes for review
    finalReview: 45 * 60 * 1000, // 45 minutes for final E2E
  },
  retries: {
    maxPerStory: 3,
    maxPerPhase: 5,
  },
  progressInterval: 5 * 60 * 1000, // 5 minutes
};

// Project templates for new projects
export const PROJECT_TEMPLATES = {
  'node-api': {
    name: 'Node.js API',
    packageManager: 'pnpm',
    typescript: true,
    framework: 'express',
    testing: 'vitest',
  },
  'next-app': {
    name: 'Next.js App',
    packageManager: 'pnpm',
    typescript: true,
    framework: 'nextjs',
    testing: 'vitest',
  },
  'node-cli': {
    name: 'Node.js CLI Tool',
    packageManager: 'pnpm',
    typescript: true,
    framework: 'commander',
    testing: 'vitest',
  },
  'custom': {
    name: 'Custom Setup',
    packageManager: null,
    typescript: null,
    framework: null,
    testing: null,
  },
};
