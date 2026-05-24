/**
 * Parse a markdown PRD into structured data
 */
export function parsePRD(content, filename = 'prd') {
  const lines = content.split('\n');
  
  let title = '';
  let currentSection = 'description';
  const sections = {
    description: [],
    requirements: [],
    acceptanceCriteria: [],
    technicalNotes: [],
  };

  for (const line of lines) {
    // Extract title from first H1
    if (!title && line.startsWith('# ')) {
      title = line.replace(/^#\s+/, '').replace(/^(Feature|PRD|Spec):\s*/i, '').trim();
      continue;
    }

    // Detect section headers
    const sectionMatch = line.match(/^##\s+(.+)/);
    if (sectionMatch) {
      const name = sectionMatch[1].toLowerCase();
      
      if (name.includes('overview') || name.includes('description') || name.includes('summary') || name.includes('background')) {
        currentSection = 'description';
      } else if (name.includes('requirement') || name.includes('feature') || name.includes('scope')) {
        currentSection = 'requirements';
      } else if (name.includes('acceptance') || name.includes('criteria') || name.includes('done') || name.includes('success')) {
        currentSection = 'acceptanceCriteria';
      } else if (name.includes('technical') || name.includes('note') || name.includes('implementation') || name.includes('constraint')) {
        currentSection = 'technicalNotes';
      }
      continue;
    }

    // Add content to current section
    if (line.trim()) {
      const cleanLine = line.replace(/^[-*]\s*(\[.\])?\s*/, '').trim();
      if (cleanLine) {
        sections[currentSection].push(cleanLine);
      }
    }
  }

  // Default title from filename
  if (!title) {
    title = filename.replace(/[-_]/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
  }

  return {
    title,
    description: sections.description.join('\n'),
    requirements: sections.requirements,
    acceptanceCriteria: sections.acceptanceCriteria,
    technicalNotes: sections.technicalNotes,
    raw: content,
  };
}

/**
 * Format PRD for prompts
 */
export function formatPRDForPrompt(prd) {
  let result = `# PRD: ${prd.title}\n\n`;

  if (prd.description) {
    result += `## Description\n${prd.description}\n\n`;
  }

  if (prd.requirements.length > 0) {
    result += `## Requirements\n${prd.requirements.map(r => `- ${r}`).join('\n')}\n\n`;
  }

  if (prd.acceptanceCriteria.length > 0) {
    result += `## Acceptance Criteria\n${prd.acceptanceCriteria.map(c => `- [ ] ${c}`).join('\n')}\n\n`;
  }

  if (prd.technicalNotes.length > 0) {
    result += `## Technical Notes\n${prd.technicalNotes.map(n => `- ${n}`).join('\n')}\n\n`;
  }

  return result;
}
