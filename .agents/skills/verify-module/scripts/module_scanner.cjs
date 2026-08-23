#!/usr/bin/env node
'use strict';

// module_scanner.cjs — module completeness gate (see ../SKILL.md).
// Self-contained on purpose: skill folders are synced into hosts individually,
// so no cross-skill requires. CommonJS (.cjs) so it runs under any host
// package.json module type.

const fs = require('fs');
const path = require('path');

// --- shared helpers (inlined; keep in sync across verify-* scripts) ---

function parseCliArgs(argv) {
  const args = argv.slice(2);
  const result = { target: '.', verbose: false, json: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '-v' || args[i] === '--verbose') result.verbose = true;
    else if (args[i] === '--json') result.json = true;
    else if (args[i] === '-h' || args[i] === '--help') result.help = true;
    else if (args[i] === '--mode' && args[i + 1]) result.mode = args[++i];
    else if (args[i] === '--exclude') {
      result.exclude = result.exclude || [];
      while (i + 1 < args.length && !args[i + 1].startsWith('-')) result.exclude.push(args[++i]);
    } else if (!args[i].startsWith('-')) result.target = args[i];
  }
  return result;
}

const SEP = '='.repeat(60);
const ICONS = {
  error: '✗', warning: '⚠', info: 'ℹ',
  critical: '\u{1F534}', high: '\u{1F7E0}', medium: '\u{1F7E1}', low: '\u{1F535}',
};

function buildReport(title, fields, issues, verbose) {
  const lines = [SEP, title, SEP];
  for (const [k, v] of Object.entries(fields)) lines.push(`\n${k}: ${v}`);
  if (issues.length) {
    lines.push('\n' + '-'.repeat(40), 'Issues:', '-'.repeat(40));
    for (const i of issues) {
      lines.push(`  ${ICONS[i.severity] || 'ℹ'} [${i.severity.toUpperCase()}] ${i.message}`);
      if (i.path && verbose) lines.push(`    path: ${i.path}`);
    }
  }
  lines.push('\n' + SEP);
  return lines.join('\n');
}

function hasFatal(issues, fatalLevels) {
  const levels = fatalLevels || ['error'];
  return issues.some((i) => levels.includes(i.severity));
}

// --- scanner ---

const REQUIRED_FILES = { 'README.md': 'module documentation', 'DESIGN.md': 'design-decision record' };
const ALT_SRC_DIRS = ['src', 'lib', 'pkg', 'internal', 'cmd', 'app'];
const ALT_TEST_DIRS = ['tests', 'test', '__tests__', 'spec'];
const ROOT_SCRIPT_FILES = new Set([
  'install.sh', 'uninstall.sh', 'install.ps1',
  'uninstall.ps1', 'Dockerfile', 'Makefile',
]);
const CODE_EXTS = new Set(['.py', '.go', '.rs', '.ts', '.js', '.java', '.sh', '.ps1']);
const TEST_PATTERNS = ['test_', '_test.', '.test.', 'spec_', '_spec.'];

function scanStructure(p, depth = 3) {
  const s = { name: path.basename(p), type: 'dir', children: [] };
  if (depth <= 0) return s;
  try {
    for (const name of fs.readdirSync(p).sort()) {
      if (name.startsWith('.')) continue;
      const full = path.join(p, name);
      const stat = fs.statSync(full);
      if (stat.isFile()) s.children.push({ name, type: 'file', size: stat.size });
      else if (stat.isDirectory()) s.children.push(scanStructure(full, depth - 1));
    }
  } catch {}
  return s;
}

function rglob(dir, test) {
  try {
    for (const name of fs.readdirSync(dir)) {
      const full = path.join(dir, name);
      try {
        const stat = fs.statSync(full);
        if (stat.isFile() && test(name)) return true;
        if (stat.isDirectory()) { if (rglob(full, test)) return true; }
      } catch {}
    }
  } catch {}
  return false;
}

function scanModule(target) {
  const modulePath = path.resolve(target);
  const issues = [];
  const add = (severity, message, p) => issues.push({ severity, message, path: p || null });

  if (!fs.existsSync(modulePath)) {
    add('error', `Path does not exist: ${modulePath}`);
    return { modulePath, issues, structure: {} };
  }
  if (!fs.statSync(modulePath).isDirectory()) {
    add('error', `Not a directory: ${modulePath}`);
    return { modulePath, issues, structure: {} };
  }

  const structure = scanStructure(modulePath);

  // required files
  for (const [file, desc] of Object.entries(REQUIRED_FILES)) {
    const fp = path.join(modulePath, file);
    if (!fs.existsSync(fp)) add('error', `Missing required doc: ${file} (${desc})`, fp);
    else if (fs.statSync(fp).size < 50) add('warning', `Doc nearly empty: ${file} (< 50 bytes)`, fp);
  }

  // source dirs
  let srcFound = ALT_SRC_DIRS.some((d) => {
    try { return fs.statSync(path.join(modulePath, d)).isDirectory(); }
    catch { return false; }
  });
  const entries = fs.readdirSync(modulePath);
  const rootCode = entries.filter((n) => {
    try {
      const s = fs.statSync(path.join(modulePath, n));
      return s.isFile() && CODE_EXTS.has(path.extname(n));
    } catch { return false; }
  });
  const rootScript = entries.filter((n) => {
    try {
      return fs.statSync(path.join(modulePath, n)).isFile()
        && ROOT_SCRIPT_FILES.has(n);
    } catch { return false; }
  });
  if (rootCode.length || rootScript.length) {
    srcFound = true;
    if (rootCode.length > 5) {
      add('warning', `Too many code files at module root (${rootCode.length}) — consider moving them into src/`);
    }
  }
  if (!srcFound) add('warning', 'No source directory or code files found');

  // test dirs
  let testFound = ALT_TEST_DIRS.some((d) => {
    try { return fs.statSync(path.join(modulePath, d)).isDirectory(); }
    catch { return false; }
  });
  if (!testFound) testFound = rglob(modulePath, (n) => TEST_PATTERNS.some((p) => n.includes(p)));
  if (!testFound) add('warning', 'No test directory or test files found');

  // doc quality
  const readme = path.join(modulePath, 'README.md');
  if (fs.existsSync(readme)) {
    const c = fs.readFileSync(readme, 'utf-8');
    if (!c.includes('#')) add('warning', 'README.md has no heading', readme);
    const docKeys = ['usage', 'install', 'example', 'quick start', 'getting started'];
    if (!docKeys.some((k) => c.toLowerCase().includes(k)))
      add('info', 'README.md should include usage notes or an example', readme);
  }
  const design = path.join(modulePath, 'DESIGN.md');
  if (fs.existsSync(design)) {
    const c = fs.readFileSync(design, 'utf-8');
    const designKeys = ['decision', 'choice', 'trade', 'alternative', 'rationale'];
    if (!designKeys.some((k) => c.toLowerCase().includes(k)))
      add('info', 'DESIGN.md should record design decisions and trade-offs', design);
  }

  return { modulePath, issues, structure };
}

function formatStructure(s, indent = 0) {
  const pre = '  '.repeat(indent);
  if (s.type === 'dir') {
    const lines = [`${pre}\u{1F4C1} ${s.name}/`];
    for (const ch of (s.children || [])) lines.push(formatStructure(ch, indent + 1));
    return lines.join('\n');
  }
  const sz = (s.size || 0) < 1024 ? `(${s.size} B)` : `(${Math.floor(s.size / 1024)} KB)`;
  return `${pre}\u{1F4C4} ${s.name} ${sz}`;
}

function formatReport(r, verbose) {
  const errs = r.issues.filter((i) => i.severity === 'error').length;
  const warns = r.issues.filter((i) => i.severity === 'warning').length;
  const passed = !hasFatal(r.issues);
  const fields = {
    'Module path': r.modulePath,
    'Result': passed ? '✓ pass' : '✗ fail',
    'Counts': `errors: ${errs} | warnings: ${warns}`,
  };
  let report = buildReport('Module Completeness Report', fields, r.issues, verbose);
  if (verbose && r.structure.name) {
    report += '\n' + '-'.repeat(40) + '\nStructure:\n' + '-'.repeat(40) + '\n' + formatStructure(r.structure);
  }
  return report;
}

// CLI
const opts = parseCliArgs(process.argv);
const result = scanModule(opts.target);
const passed = !hasFatal(result.issues);

if (opts.json) {
  console.log(JSON.stringify({
    module_path: result.modulePath, passed,
    error_count: result.issues.filter((i) => i.severity === 'error').length,
    warning_count: result.issues.filter((i) => i.severity === 'warning').length,
    issues: result.issues,
  }, null, 2));
} else {
  console.log(formatReport(result, opts.verbose));
}

process.exit(passed ? 0 : 1);
