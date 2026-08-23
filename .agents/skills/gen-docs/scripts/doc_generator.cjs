#!/usr/bin/env node
'use strict';

// doc_generator.cjs — README.md / DESIGN.md skeleton generator (see ../SKILL.md).
// Self-contained on purpose: skill folders are synced into hosts individually,
// so no cross-skill requires. CommonJS (.cjs) so it runs under any host
// package.json module type.

const fs = require('fs');
const path = require('path');

// --- Utilities ---

function parseGitignore(modPath) {
  const patterns = [];
  const hardcoded = ['node_modules', '.git', '__pycache__', '.vscode', '.idea', 'dist', 'build', '.DS_Store'];

  // hardcoded common excludes
  hardcoded.forEach(p => patterns.push({ pattern: p, negate: false }));

  // parse .gitignore
  try {
    const gitignorePath = path.join(modPath, '.gitignore');
    const content = fs.readFileSync(gitignorePath, 'utf8');
    content.split('\n').forEach(line => {
      line = line.trim();
      if (line && !line.startsWith('#')) {
        const negate = line.startsWith('!');
        if (negate) line = line.slice(1);
        patterns.push({ pattern: line, negate });
      }
    });
  } catch {}

  return patterns;
}

function shouldIgnore(filePath, basePath, patterns) {
  const relPath = path.relative(basePath, filePath);
  const parts = relPath.split(path.sep);
  const name = path.basename(filePath);

  let ignored = false;
  for (const { pattern, negate } of patterns) {
    let match = false;
    const cleanPattern = pattern.replace(/\/$/, '');

    if (cleanPattern.includes('*')) {
      // wildcard → regex: escape specials, then turn \* back into [^/]*
      const escaped = cleanPattern.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '[^/]*');
      const regex = new RegExp('^' + escaped + '$');
      match = regex.test(name) || parts.some(p => regex.test(p));
    } else if (cleanPattern.includes('/')) {
      // path match: must match from the start or a whole segment
      match = relPath === cleanPattern || relPath.startsWith(cleanPattern + '/');
    } else {
      // exact directory/file name match
      match = name === cleanPattern || parts.includes(cleanPattern);
    }

    if (match) ignored = !negate;
  }
  return ignored;
}

function rglob(dir, filter, basePath = dir) {
  const patterns = parseGitignore(basePath);
  const results = [];

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);

    if (shouldIgnore(full, basePath, patterns)) continue;

    if (entry.isDirectory()) {
      results.push(...rglob(full, filter, basePath));
    } else if (!filter || filter(entry.name, full)) {
      results.push(full);
    }
  }
  return results;
}

// --- Language Detection ---

const LANG_MAP = {
  '.py': 'Python', '.go': 'Go', '.rs': 'Rust', '.ts': 'TypeScript',
  '.js': 'JavaScript', '.java': 'Java', '.c': 'C', '.cpp': 'C++',
};

function detectLanguage(modPath) {
  const exts = {};
  try {
    for (const f of rglob(modPath)) {
      const ext = path.extname(f).toLowerCase();
      if (ext) exts[ext] = (exts[ext] || 0) + 1;
    }
  } catch { return 'Unknown'; }
  const codeExts = Object.entries(exts).filter(([k]) => k in LANG_MAP);
  if (codeExts.length) {
    const best = codeExts.reduce((a, b) => b[1] > a[1] ? b : a);
    return LANG_MAP[best[0]] || 'Unknown';
  }
  return 'Unknown';
}

// --- Python AST-lite extraction via regex ---

function analyzePythonModule(modPath) {
  const info = makeInfo(modPath, 'Python');
  const pyFiles = rglob(modPath, (name) => name.endsWith('.py'));
  info.files = pyFiles.map(f => path.relative(modPath, f));

  for (const pyFile of pyFiles) {
    const basename = path.basename(pyFile);
    if (basename.startsWith('test_') || basename.includes('_test')) continue;
    let content;
    try { content = fs.readFileSync(pyFile, 'utf-8'); } catch { continue; }

    // Module docstring (triple-quoted at top)
    if (!info.description) {
      const docM = content.match(/^(?:#[^\n]*\n)*\s*(?:"""([\s\S]*?)"""|'''([\s\S]*?)''')/);
      if (docM) info.description = (docM[1] || docM[2]).split('\n')[0].trim();
    }

    const rel = path.relative(modPath, pyFile);

    // Functions
    for (const m of content.matchAll(/^def\s+([A-Za-z]\w*)\s*\(/gm)) {
      info.functions.push({ name: m[1], file: rel, doc: '' });
    }
    // Classes
    for (const m of content.matchAll(/^class\s+([A-Za-z]\w*)\s*[:(]/gm)) {
      info.classes.push({ name: m[1], file: rel, doc: '' });
    }

    // Entry points
    if (['main.py', '__main__.py', 'cli.py', 'app.py'].includes(basename)) {
      info.entry_points.push(rel);
    }
  }

  // Dependencies
  const reqPath = path.join(modPath, 'requirements.txt');
  try {
    const content = fs.readFileSync(reqPath, 'utf-8');
    for (const line of content.split('\n')) {
      const trimmed = line.trim();
      if (trimmed && !trimmed.startsWith('#')) {
        info.dependencies.push(trimmed.split(/[=><]/)[0]);
      }
    }
  } catch {}

  return info;
}

// --- Generic analysis (regex fallback) ---

const LANG_PATTERNS = {
  'Go':         [/^\s*func\s+(\w+)/,              /^\s*type\s+(\w+)\s+struct\b/],
  'Rust':       [/^\s*(?:pub\s+)?fn\s+(\w+)/,     /^\s*(?:pub\s+)?struct\s+(\w+)/],
  'TypeScript': [/^\s*(?:export\s+)?(?:async\s+)?function\s+(\w+)/, /^\s*(?:export\s+)?class\s+(\w+)/],
  'JavaScript': [/^\s*(?:export\s+)?(?:async\s+)?function\s+(\w+)/, /^\s*(?:export\s+)?class\s+(\w+)/],
  'Java':       [/^\s*(?:public|private|protected)?\s*(?:static\s+)?\w+\s+(\w+)\s*\(/,
                  /^\s*(?:public\s+)?class\s+(\w+)/],
  'C++':        [/^\s*(?:\w+\s+)+(\w+)\s*\([^;]*$/, /^\s*class\s+(\w+)/],
  'C':          [/^\s*(?:\w+\s+)+(\w+)\s*\([^;]*$/, null],
};

const CODE_EXTS = new Set(['.py', '.go', '.rs', '.ts', '.js', '.java', '.c', '.cpp']);

function analyzeModule(modPath) {
  const language = detectLanguage(modPath);
  if (language === 'Python') return analyzePythonModule(modPath);

  const info = makeInfo(modPath, language);
  const [funcPat, clsPat] = LANG_PATTERNS[language] || [null, null];

  try {
    for (const f of rglob(modPath)) {
      if (!CODE_EXTS.has(path.extname(f).toLowerCase())) continue;
      const rel = path.relative(modPath, f);
      info.files.push(rel);

      if (!funcPat && !clsPat) continue;
      let content;
      try { content = fs.readFileSync(f, 'utf-8'); } catch { continue; }
      for (const line of content.split('\n')) {
        if (funcPat) {
          const m = line.match(funcPat);
          if (m && !m[1].startsWith('_')) info.functions.push({ name: m[1], file: rel, doc: '' });
        }
        if (clsPat) {
          const m = line.match(clsPat);
          if (m && !m[1].startsWith('_')) info.classes.push({ name: m[1], file: rel, doc: '' });
        }
      }
    }
  } catch {}

  return info;
}

function makeInfo(modPath, language) {
  return {
    name: path.basename(modPath), path: modPath, description: '', language,
    files: [], functions: [], classes: [], dependencies: [], entry_points: [],
  };
}

// --- README Generation ---

function generateReadme(info) {
  const L = [];
  L.push(`# ${info.name}`, '');
  if (info.description) {
    L.push(info.description);
  } else {
    L.push('> TODO: describe the module\'s core purpose, the problem it solves, and its main use.');
    L.push('> Example: this module provides X, used to solve Y.');
  }
  L.push('', '## Overview', '', '<!-- What this module is and which problem it solves -->', '');
  L.push('## Features', '', '<!-- List the main features, each with a short description -->', '');
  L.push('- **Feature 1**: TODO describe the first main feature');
  L.push('- **Feature 2**: TODO describe the second main feature');
  L.push('- **Feature 3**: TODO describe the third main feature', '');

  if (info.dependencies.length) {
    L.push('## Dependencies', '', '```');
    info.dependencies.slice(0, 10).forEach(d => L.push(d));
    if (info.dependencies.length > 10) L.push(`# ... and ${info.dependencies.length - 10} more`);
    L.push('```', '');
  }

  L.push('## Usage', '');
  if (info.entry_points.length) {
    L.push('### Run', '', '```bash');
    const cmds = {
      Python: `python -m ${info.name}`, Go: 'go run ./cmd/main.go',
      Rust: 'cargo run', TypeScript: 'npm start', JavaScript: 'npm start'
    };
    L.push(cmds[info.language] || `# TODO: add the run command for this ${info.language} project`);
    L.push('```', '');
  }

  L.push('### Example', '');
  const EXAMPLES = {
    Python: `from ${info.name.toLowerCase()} import main\n\n` +
      `# initialize\nobj = main()\n\n# run\nresult = obj.process()\nprint(result)`,
    Go: `package main\n\nimport "${info.name.toLowerCase()}"\n\nfunc main() {\n` +
      `    // initialize\n    obj := ${info.name.toLowerCase()}.New()\n` +
      `\n    // run\n    result := obj.Process()\n    println(result)\n}`,
    Rust: `use ${info.name.toLowerCase()}::*;\n\nfn main() {\n` +
      `    // initialize\n    let obj = Object::new();\n\n` +
      `    // run\n    let result = obj.process();\n` +
      `    println!("{}", result);\n}`,
    TypeScript: `import { main } from "./${info.name.toLowerCase()}";\n\n` +
      `// initialize\nconst obj = new main();\n\n` +
      `// run\nconst result = obj.process();\nconsole.log(result);`,
    JavaScript: `const { main } = require("./${info.name.toLowerCase()}");\n\n` +
      `// initialize\nconst obj = new main();\n\n` +
      `// run\nconst result = obj.process();\nconsole.log(result);`,
  };
  if (EXAMPLES[info.language]) {
    L.push('```' + info.language.toLowerCase(), EXAMPLES[info.language], '```');
  } else {
    L.push('```' + info.language.toLowerCase());
    L.push(`<!-- TODO: provide a usage example idiomatic to ${info.language} -->`);
    L.push(`<!-- The example should cover: initialization, a basic operation, handling the result -->`);
    L.push('```');
  }
  L.push('');

  if (info.classes.length || info.functions.length) {
    L.push('## API Overview', '');
    if (info.classes.length) {
      L.push('### Classes', '', '| Class | Description |', '|------|------|');
      info.classes.slice(0, 10).forEach(c => L.push(`| \`${c.name}\` | ${c.doc || 'TODO: describe this class'} |`));
      L.push('');
    }
    if (info.functions.length) {
      L.push('### Functions', '', '| Function | Description |', '|------|------|');
      info.functions.slice(0, 10).forEach(f => L.push(`| \`${f.name}()\` | ${f.doc || 'TODO: describe this function'} |`));
      L.push('');
    }
  }

  L.push('## Structure', '', '```', `${info.name}/`);
  info.files.sort().slice(0, 15).forEach(f => L.push(`├── ${f}`));
  if (info.files.length > 15) L.push(`└── ... (${info.files.length - 15} more files)`);
  L.push('```', '');
  L.push('## Related docs', '', '- [Design document](DESIGN.md)', '');
  return L.join('\n');
}

// --- DESIGN Generation ---

function generateDesign(info) {
  const today = new Date().toISOString().slice(0, 10);
  const L = [];
  L.push(`# ${info.name} — Design`, '');
  L.push('## Overview', '', '### Goals', '', '<!-- What problem does this module solve? -->', '');
  L.push('### Non-goals', '', '<!-- What does this module deliberately NOT do? -->', '');
  L.push('## Architecture', '', '### Overall shape', '', '```');
  L.push('┌─────────────────────────────────────┐');
  L.push('│  TODO: sketch the overall architecture │');
  L.push('│  main components, data flow, deps      │');
  L.push('│  ASCII art or a Mermaid diagram        │');
  L.push('└─────────────────────────────────────┘');
  L.push('```', '');
  L.push('### Core components', '');
  if (info.classes.length) {
    info.classes.slice(0, 5).forEach(c => L.push(`- **${c.name}**: ${c.doc || 'TODO: describe this component\'s responsibility'}`));
  } else {
    L.push('<!-- List the core components and their responsibilities -->');
    L.push('- **Component 1**: TODO describe the first core component');
    L.push('- **Component 2**: TODO describe the second core component');
    L.push('- **Component 3**: TODO describe the third core component');
  }
  L.push('');
  L.push('## Design decisions', '', '### Decision record', '');
  L.push('| Date | Decision | Rationale | Impact |', '|------|------|------|------|');
  L.push(`| ${today} | Initial design | - | - |`, '');
  L.push('### Technology choices', '', `- **Language**: ${info.language}`);
  if (info.dependencies.length) L.push(`- **Main dependencies**: ${info.dependencies.slice(0, 5).join(', ')}`);
  L.push('- **Rationale**: <!-- TODO: why this stack — performance, maintainability, ecosystem -->', '');
  L.push('## Trade-offs', '', '### Known limitations', '');
  L.push('<!-- List the known limitations and constraints -->');
  L.push('- **Limitation 1**: TODO describe the first known limitation and its cause');
  L.push('- **Limitation 2**: TODO describe the second known limitation and its cause', '');
  L.push('### Technical debt', '');
  L.push('<!-- Record deliberately incurred debt, temporary approaches, and why -->');
  L.push('- **Debt 1**: description | reason: performance first | planned repayment: v2.0', '');
  L.push('## Security considerations', '', '### Threat model', '');
  L.push('<!-- Identify potential threats: authentication, authorization, data leaks, ... -->');
  L.push('- **Threat 1**: TODO describe the threat and its impact');
  L.push('- **Threat 2**: TODO describe the threat and its impact', '');
  L.push('### Mitigations', '');
  L.push('<!-- List the mitigations in place: input validation, encryption, access control, ... -->');
  L.push('- **Mitigation 1**: TODO describe the mitigation');
  L.push('- **Mitigation 2**: TODO describe the mitigation', '');
  // Cross-cutting and open questions are the two sections authors skip, and
  // verify-module blocks delivery on both. Scaffold them so the gate is passable.
  L.push('## Cross-cutting concerns', '');
  L.push('<!-- Name a consequence in each of the four, or say "none, because ..." -->');
  L.push('- **Security**: TODO — see the threat model above');
  L.push('- **Privacy**: TODO — personal data touched, retention, and lawful basis');
  L.push('- **Observability**: TODO — the signal that shows a new failure mode');
  L.push('- **Cost**: TODO — what grows with traffic or storage', '');
  L.push('## Open questions', '');
  L.push('<!-- Decisions that are not yet made. An empty list means finished. -->');
  L.push('- **Question 1**: TODO describe the undecided point and who decides it', '');
  L.push('## Change history', '', `### ${today} - Initial version`, '');
  L.push('**What changed**: module created', '', '**Why**: initial development', '');
  return L.join('\n');
}

// --- Core: generate_docs ---

function generateDocs(targetPath, force) {
  const modPath = path.resolve(targetPath);
  const result = { readme: null, design: null, status: 'success', messages: [] };

  if (!fs.existsSync(modPath)) {
    result.status = 'error';
    result.messages.push(`Path does not exist: ${modPath}`);
    return result;
  }

  const info = analyzeModule(modPath);

  const readmePath = path.join(modPath, 'README.md');
  if (fs.existsSync(readmePath) && !force) {
    result.messages.push('README.md already exists, skipped (use --force to overwrite)');
  } else {
    fs.writeFileSync(readmePath, generateReadme(info));
    result.readme = readmePath;
    result.messages.push('Generated README.md');
  }

  const designPath = path.join(modPath, 'DESIGN.md');
  if (fs.existsSync(designPath) && !force) {
    result.messages.push('DESIGN.md already exists, skipped (use --force to overwrite)');
  } else {
    fs.writeFileSync(designPath, generateDesign(info));
    result.design = designPath;
    result.messages.push('Generated DESIGN.md');
  }

  return result;
}

// --- CLI ---

function parseArgs(argv) {
  const args = { path: '.', force: false, json: false, readmeOnly: false, designOnly: false };
  const rest = argv.slice(2);
  const positional = [];
  for (const a of rest) {
    if (a === '-f' || a === '--force') args.force = true;
    else if (a === '--json') args.json = true;
    else if (a === '--readme-only') args.readmeOnly = true;
    else if (a === '--design-only') args.designOnly = true;
    else if (a === '-h' || a === '--help') {
      console.log('Usage: doc_generator.cjs [path] [-f|--force] [--json] [--readme-only] [--design-only]');
      process.exit(0);
    } else positional.push(a);
  }
  if (positional.length) args.path = positional[0];
  return args;
}

function main() {
  const args = parseArgs(process.argv);
  const result = generateDocs(args.path, args.force);

  if (args.json) {
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  } else {
    console.log('='.repeat(50));
    console.log('Documentation Generation Report');
    console.log('='.repeat(50));
    for (const msg of result.messages) {
      console.log(`  • ${msg}`);
    }
    console.log('='.repeat(50));
  }

  process.exitCode = result.status === 'success' ? 0 : 1;
}

if (require.main === module) {
  main();
}

module.exports = {
  parseGitignore,
  shouldIgnore,
  rglob,
  detectLanguage,
  analyzeModule,
  generateReadme,
  generateDesign,
  generateDocs,
  parseArgs,
  main,
};
