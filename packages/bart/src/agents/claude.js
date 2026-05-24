import { spawn } from 'child_process';

/**
 * Run Claude Code with a prompt
 */
export async function runClaude({ prompt, model = 'sonnet', cwd, timeout = 30 * 60 * 1000 }) {
  return new Promise((resolve, reject) => {
    const args = [
      '-p', prompt,
      '--output-format', 'text',
    ];

    // Add model if specified
    if (model && model !== 'default') {
      args.push('--model', model);
    }

    const proc = spawn('claude', args, {
      cwd,
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout,
    });

    let stdout = '';
    let stderr = '';

    proc.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    proc.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    proc.on('close', (code) => {
      if (code === 0) {
        resolve(stdout);
      } else {
        reject(new Error(`Claude exited with code ${code}: ${stderr || stdout}`));
      }
    });

    proc.on('error', (err) => {
      reject(new Error(`Failed to run Claude: ${err.message}`));
    });
  });
}

/**
 * Run Claude Code with dangerously-skip-permissions for autonomous execution
 */
export async function runClaudeAutonomous({ prompt, model = 'sonnet', cwd, timeout = 30 * 60 * 1000 }) {
  return new Promise((resolve, reject) => {
    const args = [
      '--dangerously-skip-permissions',
      '-p', prompt,
    ];

    // Add model if specified
    if (model && model !== 'default') {
      args.push('--model', model);
    }

    const proc = spawn('claude', args, {
      cwd,
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout,
    });

    let stdout = '';
    let stderr = '';

    proc.stdout.on('data', (data) => {
      stdout += data.toString();
      // Echo progress to console
      process.stdout.write(data);
    });

    proc.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    proc.on('close', (code) => {
      if (code === 0) {
        resolve({ success: true, output: stdout });
      } else {
        resolve({ success: false, output: stdout, error: stderr || 'Unknown error' });
      }
    });

    proc.on('error', (err) => {
      reject(new Error(`Failed to run Claude: ${err.message}`));
    });
  });
}
