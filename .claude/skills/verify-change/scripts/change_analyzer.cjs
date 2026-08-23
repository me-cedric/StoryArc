#!/usr/bin/env node
'use strict';

// change_analyzer.cjs — change verification gate (see ../SKILL.md).
// Self-contained on purpose: skill folders are synced into hosts individually,
// so no cross-skill requires. CommonJS (.cjs) so it runs under any host
// package.json module type.

const { execFileSync } = require('child_process');
const path = require('path');
const fs = require('fs');

// --- shared helpers (inlined; keep in sync across verify-* scripts) ---

function parseCliArgs(argv) {
  const args = argv.slice(2);
  const result = { target: '.', verbose: false, json: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '-v' || args[i] === '--verbose') result.verbose = true;
    else if (args[i] === '--json') result.json = true;
    else if (args[i] === '-h' || args[i] === '--help') result.help = true;
    else if (args[i] === '--mode' && args[i + 1]) result.mode = args[++i];
    else if (!args[i].startsWith('-')) result.target = args[i];
  }
  return result;
}

const SEP = '='.repeat(60);
const DASH = '-'.repeat(40);
const ICONS = { error: '✗', warning: '⚠', info: 'ℹ' };

function buildReport(title, fields, issues, verbose) {
  const lines = [SEP, title, SEP];
  for (const [k, v] of Object.entries(fields)) lines.push(`\n${k}: ${v}`);
  if (issues.length) {
    lines.push('\n' + DASH, 'Issues:', DASH);
    for (const i of issues) {
      lines.push(`  ${ICONS[i.severity] || 'ℹ'} [${i.severity.toUpperCase()}] ${i.message}`);
      if (verbose && i.related_files) {
        for (const f of i.related_files.slice(0, 10)) lines.push(`    - ${f}`);
      }
    }
  }
  lines.push('\n' + SEP);
  return lines.join('\n');
}

// --- analyzer ---

const CODE_EXT = new Set(['.py', '.go', '.rs', '.ts', '.js', '.jsx', '.tsx', '.java', '.c', '.cpp', '.h', '.hpp']);
const DOC_EXT = new Set(['.md', '.rst', '.txt', '.adoc']);
const TEST_PATTERNS = ['test_', '_test.', '.test.', 'spec_', '_spec.', '/tests/', '/test/', '/__tests__/'];
const CONFIG_FILES = new Set(['package.json', 'pyproject.toml', 'go.mod', 'cargo.toml', 'pom.xml', 'makefile', 'dockerfile']);
const CONFIG_EXT = new Set(['.yaml', '.yml', '.json', '.toml', '.ini']);

function normalizePath(p) {
  let s = p.trim();
  if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
    s = s.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  }
  if (s.startsWith('./')) s = s.slice(2);
  return s;
}

function classifyFile(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  const name = path.basename(filePath).toLowerCase();
  const lower = filePath.toLowerCase();
  return {
    path: filePath, type: 'modified', additions: 0, deletions: 0,
    is_code: CODE_EXT.has(ext), is_doc: DOC_EXT.has(ext),
    is_test: TEST_PATTERNS.some((p) => lower.includes(p)),
    is_config: CONFIG_FILES.has(name) || CONFIG_EXT.has(ext),
  };
}

function parseNameStatusLine(line) {
  const parts = line.split('\t');
  if (parts.length < 2) return null;
  const status = parts[0][0];
  const p = normalizePath(parts[parts.length - 1]);
  if (!p) return null;
  const c = classifyFile(p);
  const map = { A: 'added', M: 'modified', D: 'deleted', R: 'renamed' };
  if (map[status]) c.type = map[status];
  return c;
}

function parsePorcelainLine(line) {
  if (line.length < 3) return null;
  const status = line.slice(0, 2);
  let raw = line.slice(3);
  if (!raw) return null;
  if (raw.includes(' -> ')) raw = raw.split(' -> ')[1];
  const p = normalizePath(raw);
  if (!p) return null;
  const c = classifyFile(p);
  if (status.includes('?') || status.includes('A')) c.type = 'added';
  else if (status.includes('R')) c.type = 'renamed';
  else if (status.includes('M')) c.type = 'modified';
  else if (status.includes('D')) c.type = 'deleted';
  return c;
}

function git(...args) {
  try { return execFileSync('git', args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }); }
  catch { return ''; }
}

function getGitChanges(base = 'HEAD~1', target = 'HEAD') {
  const changes = [];
  for (const line of git('diff', '--name-status', base, target).split('\n')) {
    if (!line) continue;
    const c = parseNameStatusLine(line);
    if (c) changes.push(c);
  }
  const statMap = {};
  for (const line of git('diff', '--numstat', base, target).split('\n')) {
    if (!line) continue;
    const parts = line.split('\t');
    if (parts.length >= 3) {
      statMap[normalizePath(parts[2])] = [
        parts[0] === '-' ? 0 : parseInt(parts[0], 10),
        parts[1] === '-' ? 0 : parseInt(parts[1], 10),
      ];
    }
  }
  for (const c of changes) {
    if (statMap[c.path]) { [c.additions, c.deletions] = statMap[c.path]; }
  }
  return changes;
}

function getStagedChanges() {
  const changes = [];
  for (const line of git('diff', '--cached', '--name-status').split('\n')) {
    if (!line) continue;
    const c = parseNameStatusLine(line);
    if (c) changes.push(c);
  }
  return changes;
}

function getWorkingChanges() {
  const changes = [];
  for (const line of git('status', '--porcelain').split('\n')) {
    if (!line) continue;
    const c = parsePorcelainLine(line);
    if (c) changes.push(c);
  }
  return changes;
}

function isPathInModule(filePath, mod) {
  const np = normalizePath(filePath);
  if (mod === '.') return !np.includes('/');
  return np === mod || np.startsWith(mod + '/');
}

function identifyModules(changes) {
  const modules = new Set();
  for (const c of changes) {
    const np = normalizePath(c.path);
    const parts = np.split('/').filter(Boolean);
    if (parts.length === 1) { modules.add('.'); continue; }
    let found = false;
    for (let i = 0; i < parts.length; i++) {
      const mp = parts.slice(0, i + 1).join('/');
      if (fs.existsSync(path.join(mp, 'README.md')) || fs.existsSync(path.join(mp, 'DESIGN.md'))) {
        modules.add(mp); found = true; break;
      }
    }
    if (!found && parts.length > 1) modules.add(parts[0]);
  }
  return modules;
}

function checkDocSync(changes, modules) {
  const docStatus = {};
  const issues = [];
  const codeChanges = changes.filter((c) => c.is_code && c.type !== 'deleted');
  const docPaths = new Set(changes.filter((c) => c.is_doc).map((c) => normalizePath(c.path)));

  for (const mod of modules) {
    const readme = normalizePath(mod === '.' ? 'README.md' : `${mod}/README.md`);
    const design = normalizePath(mod === '.' ? 'DESIGN.md' : `${mod}/DESIGN.md`);
    const modCode = codeChanges.filter((c) => isPathInModule(c.path, mod));
    if (!modCode.length) continue;
    const total = modCode.reduce((s, c) => s + c.additions + c.deletions, 0);
    if (total > 50 && !docPaths.has(design)) {
      issues.push({
        severity: 'warning',
        message: `Module ${mod} has a large code change (${total} lines) but DESIGN.md was not updated`,
        related_files: modCode.map((c) => c.path),
      });
      docStatus[`${mod}/DESIGN.md`] = false;
    } else {
      docStatus[`${mod}/DESIGN.md`] = true;
    }
    const newFiles = modCode.filter((c) => c.type === 'added');
    if (newFiles.length && !docPaths.has(readme)) {
      issues.push({
        severity: 'info',
        message: `Module ${mod} gained new files — consider updating README.md`,
        related_files: newFiles.map((c) => c.path),
      });
    }
  }
  return { docStatus, issues };
}

function analyzeImpact(changes) {
  const issues = [];
  const code = changes.filter((c) => c.is_code && !c.is_test);
  const tests = changes.filter((c) => c.is_test);
  if (code.length && !tests.length) {
    const total = code.reduce((s, c) => s + c.additions + c.deletions, 0);
    if (total > 30) {
      issues.push({
        severity: 'warning',
        message: `${total} lines of code changed without a matching test update`,
        related_files: code.map((c) => c.path),
      });
    }
  }
  const configs = changes.filter((c) => c.is_config);
  if (configs.length) {
    issues.push({
      severity: 'info',
      message: 'Config files changed — confirm whether docs need an update',
      related_files: configs.map((c) => c.path),
    });
  }
  const deleted = changes.filter((c) => c.type === 'deleted');
  if (deleted.length) {
    issues.push({
      severity: 'info',
      message: `${deleted.length} file(s) deleted — confirm references are cleaned up`,
      related_files: deleted.map((c) => c.path),
    });
  }
  return issues;
}

function analyzeChanges(mode = 'working') {
  let changes;
  if (mode === 'staged') changes = getStagedChanges();
  else if (mode === 'committed') changes = getGitChanges();
  else changes = getWorkingChanges();

  const issues = [];
  let modules = new Set();
  let docStatus = {};
  if (changes.length) {
    modules = identifyModules(changes);
    const ds = checkDocSync(changes, modules);
    docStatus = ds.docStatus;
    issues.push(...ds.issues, ...analyzeImpact(changes));
  }
  const passed = !issues.some((i) => i.severity === 'error');
  const totalAdd = changes.reduce((s, c) => s + c.additions, 0);
  const totalDel = changes.reduce((s, c) => s + c.deletions, 0);
  return { changes, issues, modules, docStatus, passed, totalAdd, totalDel };
}

function formatReport(r, verbose) {
  const fields = {
    'Files changed': r.changes.length,
    'Lines added': `+${r.totalAdd}`,
    'Lines deleted': `-${r.totalDel}`,
    'Affected modules': [...r.modules].join(', ') || 'none',
    'Result': r.passed ? '✓ pass' : '✗ needs attention',
  };
  let report = buildReport('Change Analysis Report', fields, r.issues, verbose);

  if (r.changes.length && verbose) {
    const lines = ['\n' + DASH, 'Changed files:', DASH];
    const icons = { added: '➕', modified: '📝', deleted: '➖', renamed: '📋' };
    for (const c of r.changes) {
      const tags = [];
      if (c.is_code) tags.push('code');
      if (c.is_doc) tags.push('doc');
      if (c.is_test) tags.push('test');
      if (c.is_config) tags.push('config');
      const t = tags.length ? ` [${tags.join(', ')}]` : '';
      lines.push(`  ${icons[c.type] || '📝'} ${c.path}${t} (+${c.additions}/-${c.deletions})`);
    }
    report += '\n' + lines.join('\n');
  }

  if (Object.keys(r.docStatus).length) {
    const lines = ['\n' + DASH, 'Doc sync status:', DASH];
    for (const [doc, synced] of Object.entries(r.docStatus)) {
      lines.push(`  ${synced ? '✓' : '✗'} ${doc}`);
    }
    report += '\n' + lines.join('\n');
  }

  return report;
}

// CLI
if (require.main === module) {
  const opts = parseCliArgs(process.argv);
  const result = analyzeChanges(opts.mode || 'working');

  if (opts.json) {
    console.log(JSON.stringify({
      passed: result.passed,
      total_additions: result.totalAdd,
      total_deletions: result.totalDel,
      affected_modules: [...result.modules],
      changes: result.changes.map((c) => ({
        path: c.path, type: c.type, additions: c.additions,
        deletions: c.deletions, is_code: c.is_code,
        is_doc: c.is_doc, is_test: c.is_test,
      })),
      issues: result.issues.map((i) => ({
        severity: i.severity, message: i.message,
        related_files: i.related_files,
      })),
      doc_sync_status: result.docStatus,
    }, null, 2));
  } else {
    console.log(formatReport(result, opts.verbose));
  }

  process.exit(result.passed ? 0 : 1);
}

module.exports = { normalizePath, classifyFile, parsePorcelainLine, parseNameStatusLine, identifyModules };
