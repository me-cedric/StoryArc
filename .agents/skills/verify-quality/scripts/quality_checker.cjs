#!/usr/bin/env node
'use strict';

// quality_checker.cjs — code quality gate (see ../SKILL.md).
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
    else if (!args[i].startsWith('-')) result.target = args[i];
  }
  return result;
}

const SEP = '='.repeat(60);
const DASH = '-'.repeat(40);
const ICONS = { error: '✗', warning: '⚠', info: 'ℹ' };

function buildReport(title, fields, issues, verbose, groupBy) {
  const lines = [SEP, title, SEP];
  for (const [k, v] of Object.entries(fields)) lines.push(`\n${k}: ${v}`);
  if (issues.length) {
    lines.push('\n' + DASH, 'Issues:', DASH);
    if (groupBy) {
      const groups = {};
      for (const i of issues) (groups[i[groupBy]] || (groups[i[groupBy]] = [])).push(i);
      for (const cat of Object.keys(groups).sort()) {
        const items = groups[cat];
        lines.push(`\n[${cat}] (${items.length})`);
        for (const i of items.slice(0, 10)) {
          lines.push(`  ${ICONS[i.severity] || 'ℹ'} ${i.file_path || ''}${i.line_number ? ':' + i.line_number : ''}`);
          lines.push(`    ${i.message}`);
          if (verbose && i.suggestion) lines.push(`    💡 ${i.suggestion}`);
        }
        if (items.length > 10) lines.push(`  ... and ${items.length - 10} more`);
      }
    } else {
      for (const i of issues) lines.push(`  ${ICONS[i.severity] || 'ℹ'} [${i.severity.toUpperCase()}] ${i.message}`);
    }
  }
  lines.push('\n' + SEP);
  return lines.join('\n');
}

function hasFatal(issues, fatalLevels) {
  const levels = fatalLevels || ['error'];
  return issues.some((i) => levels.includes(i.severity));
}

// --- quality rules ---

const MAX_LINE_LENGTH = 120;
const MAX_FUNCTION_LENGTH = 50;
const MAX_FILE_LENGTH = 500;
const MAX_COMPLEXITY = 10;
const MAX_PARAMETERS = 5;
const MIN_FUNCTION_NAME_LENGTH = 2;

const EXCLUDE_DIRS = new Set(['.git', 'node_modules', '__pycache__', '.venv', 'venv', 'dist', 'build', '.tox']);
const CODE_EXTENSIONS = new Set(['.py', '.js', '.cjs', '.mjs', '.ts', '.go', '.java', '.rs', '.c', '.cpp']);

const COMMENT_PREFIXES = {
  '.js': '//', '.cjs': '//', '.mjs': '//', '.ts': '//', '.go': '//', '.java': '//',
  '.c': '//', '.cpp': '//', '.rs': '//',
};

// --- Analysis ---

function analyzeGenericFile(filePath) {
  const metrics = {
    path: filePath, lines: 0, code_lines: 0, comment_lines: 0,
    blank_lines: 0, functions: 0, classes: 0,
    max_complexity: 0, avg_function_length: 0,
  };
  const issues = [];
  let content;
  try {
    content = fs.readFileSync(filePath, 'utf-8');
  } catch { return { metrics, issues }; }

  const lines = content.split('\n');
  metrics.lines = lines.length;
  const prefix = COMMENT_PREFIXES[
    path.extname(filePath).toLowerCase()
  ] || '//';

  for (let i = 0; i < lines.length; i++) {
    const stripped = lines[i].trim();
    if (!stripped) metrics.blank_lines++;
    else if (
      stripped.startsWith(prefix) ||
      stripped.startsWith('/*') ||
      stripped.startsWith('*')
    ) metrics.comment_lines++;
    else metrics.code_lines++;

    if (lines[i].length > MAX_LINE_LENGTH) {
      issues.push({
        severity: 'info', category: 'format',
        message: `Line too long (${lines[i].length} > ${MAX_LINE_LENGTH})`,
        file_path: filePath, line_number: i + 1,
        suggestion: null,
      });
    }
  }

  if (metrics.code_lines > MAX_FILE_LENGTH) {
    issues.push({
      severity: 'warning', category: 'complexity',
      message: `File too long (${metrics.code_lines} code lines > ${MAX_FILE_LENGTH})`,
      file_path: filePath, suggestion: 'Consider splitting into multiple modules',
      line_number: null,
    });
  }

  return { metrics, issues };
}

function analyzePythonFile(filePath) {
  const metrics = {
    path: filePath, lines: 0, code_lines: 0, comment_lines: 0,
    blank_lines: 0, functions: 0, classes: 0,
    max_complexity: 0, avg_function_length: 0,
  };
  const issues = [];
  let content;
  try {
    content = fs.readFileSync(filePath, 'utf-8');
  } catch (e) {
    issues.push({
      severity: 'error', category: 'file',
      message: `Cannot read file: ${e.message}`,
      file_path: filePath, line_number: null, suggestion: null,
    });
    return { metrics, issues };
  }

  const lines = content.split('\n');
  metrics.lines = lines.length;
  let inMultiline = false;

  for (let i = 0; i < lines.length; i++) {
    const stripped = lines[i].trim();
    if (!stripped) { metrics.blank_lines++; }
    else if (stripped.startsWith('#')) { metrics.comment_lines++; }
    else if (stripped.includes('"""') || stripped.includes("'''")) {
      const dq = (stripped.match(/"""/g) || []).length;
      const sq = (stripped.match(/'''/g) || []).length;
      if (dq === 2 || sq === 2) { metrics.comment_lines++; }
      else { inMultiline = !inMultiline; metrics.comment_lines++; }
    } else if (inMultiline) { metrics.comment_lines++; }
    else { metrics.code_lines++; }

    if (lines[i].length > MAX_LINE_LENGTH) {
      issues.push({
        severity: 'info', category: 'format',
        message: `Line too long (${lines[i].length} > ${MAX_LINE_LENGTH})`,
        file_path: filePath, line_number: i + 1,
        suggestion: null,
      });
    }
  }

  if (metrics.code_lines > MAX_FILE_LENGTH) {
    issues.push({
      severity: 'warning', category: 'complexity',
      message: `File too long (${metrics.code_lines} code lines > ${MAX_FILE_LENGTH})`,
      file_path: filePath, suggestion: 'Consider splitting into multiple modules',
      line_number: null,
    });
  }

  // Regex-based Python analysis (no AST available in Node)
  const funcRegex = /^( *)(?:async\s+)?def\s+(\w+)\s*\(([^)]*)\)/gm;
  const classRegex = /^( *)class\s+(\w+)/gm;
  const functions = [];
  let match;

  while ((match = funcRegex.exec(content)) !== null) {
    const lineNum = content.substring(0, match.index).split('\n').length;
    const name = match[2];
    const indent = match[1].length;
    const params = match[3].trim()
      ? match[3].split(',').map(p => p.trim())
        .filter(p => p && p !== 'self' && p !== 'cls')
      : [];

    // Calculate function length by finding next line at same or lesser indent
    const funcLines = lines.slice(lineNum); // lines after def
    let length = 1;
    for (let j = 1; j < funcLines.length; j++) {
      const l = funcLines[j];
      if (l.trim() === '') { length++; continue; }
      const curIndent = l.match(/^(\s*)/)[1].length;
      if (curIndent <= indent && l.trim() !== '') break;
      length++;
    }

    // Estimate complexity from function body
    const bodyLines = lines.slice(lineNum, lineNum + length - 1);
    let complexity = 1;
    for (const bl of bodyLines) {
      const s = bl.trim();
      if (/^(if|elif|while|for)\s/.test(s) || /^(if|elif|while|for)\(/.test(s)) complexity++;
      if (/^except(\s|:)/.test(s)) complexity++;
      if (/\s(and|or)\s/.test(s)) complexity++;
      if (/\sfor\s/.test(s) && /\sin\s/.test(s) && (s.includes('[') || s.includes('('))) complexity++;
    }

    functions.push({ name, line: lineNum, length, complexity, parameters: params.length });
    metrics.max_complexity = Math.max(metrics.max_complexity, complexity);

    // Check function length
    if (length > MAX_FUNCTION_LENGTH) {
      issues.push({
        severity: 'warning', category: 'complexity',
        message: `Function '${name}' too long (${length} lines > ${MAX_FUNCTION_LENGTH})`,
        file_path: filePath, line_number: lineNum,
        suggestion: 'Consider splitting into smaller functions',
      });
    }
    // Check complexity
    if (complexity > MAX_COMPLEXITY) {
      issues.push({
        severity: 'warning', category: 'complexity',
        message: `Function '${name}' cyclomatic complexity too high (${complexity} > ${MAX_COMPLEXITY})`,
        file_path: filePath, line_number: lineNum,
        suggestion: 'Reduce nesting; extract helper functions',
      });
    }
    // Check parameter count
    if (params.length > MAX_PARAMETERS) {
      issues.push({
        severity: 'warning', category: 'design',
        message: `Function '${name}' has too many parameters (${params.length} > ${MAX_PARAMETERS})`,
        file_path: filePath, line_number: lineNum,
        suggestion: 'Consider an options object or dataclass',
      });
    }
    // Check naming
    const SPECIAL = new Set([
      'setUp', 'tearDown', 'setUpClass',
      'tearDownClass', 'setUpModule', 'tearDownModule',
    ]);
    if (!name.startsWith('_') && !SPECIAL.has(name) && !name.startsWith('visit_')) {
      if (!/^[a-z][a-z0-9_]*$/.test(name)) {
        issues.push({
          severity: 'info', category: 'naming',
          message: `Function name '${name}' is not snake_case`,
          file_path: filePath, line_number: lineNum,
          suggestion: 'Use snake_case for function names',
        });
      }
    }
    if (name.length < MIN_FUNCTION_NAME_LENGTH) {
      issues.push({
        severity: 'warning', category: 'naming',
        message: `Function name '${name}' too short`,
        file_path: filePath, line_number: lineNum,
        suggestion: 'Use a more descriptive function name',
      });
    }
  }

  while ((match = classRegex.exec(content)) !== null) {
    const lineNum = content.substring(0, match.index).split('\n').length;
    const name = match[2];
    metrics.classes++;
    if (!/^[A-Z][a-zA-Z0-9]*$/.test(name)) {
      issues.push({
        severity: 'warning', category: 'naming',
        message: `Class name '${name}' is not PascalCase`,
        file_path: filePath, line_number: lineNum,
        suggestion: 'Use PascalCase for class names, e.g. MyClassName',
      });
    }
  }

  metrics.functions = functions.length;
  if (functions.length > 0) {
    metrics.avg_function_length = functions.reduce((s, f) => s + f.length, 0) / functions.length;
  }

  return { metrics, issues };
}

// --- Directory scan ---

function scanDirectory(scanPath, excludeDirs) {
  const resolved = path.resolve(scanPath);
  const exclude = excludeDirs || EXCLUDE_DIRS;
  const result = {
    scan_path: resolved, files_scanned: 0,
    total_lines: 0, total_code_lines: 0,
    issues: [], file_metrics: [],
  };

  function walk(dir) {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      if (exclude.has(entry.name)) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) { walk(full); continue; }
      const ext = path.extname(entry.name).toLowerCase();
      if (!CODE_EXTENSIONS.has(ext)) continue;

      result.files_scanned++;
      const { metrics, issues } = ext === '.py' ? analyzePythonFile(full) : analyzeGenericFile(full);
      result.file_metrics.push(metrics);
      result.issues.push(...issues);
      result.total_lines += metrics.lines;
      result.total_code_lines += metrics.code_lines;
    }
  }

  walk(resolved);
  return result;
}

// --- Reporting ---

function passed(result) { return !hasFatal(result.issues); }

function formatReport(result, verbose) {
  const errs = result.issues.filter(i => i.severity === 'error').length;
  const warns = result.issues.filter(i => i.severity === 'warning').length;
  const fields = {
    'Scan path': result.scan_path,
    'Files scanned': result.files_scanned,
    'Total lines': result.total_lines,
    'Code lines': result.total_code_lines,
    'Result': passed(result) ? '✓ pass' : '✗ needs attention',
    'Counts': `errors: ${errs} | warnings: ${warns}`,
  };
  let report = buildReport(
    'Code Quality Report', fields, result.issues, verbose, 'category'
  );

  if (verbose && result.file_metrics.length) {
    const complex = result.file_metrics
      .filter(m => m.max_complexity > 0)
      .sort((a, b) => b.max_complexity - a.max_complexity)
      .slice(0, 5);
    if (complex.length) {
      const lines = ['\n' + DASH, 'Most complex files:', DASH];
      for (const m of complex) lines.push(`  ${m.path}: complexity ${m.max_complexity}, ${m.functions} function(s)`);
      report += '\n' + lines.join('\n');
    }
  }
  return report;
}

// --- CLI ---

function main() {
  const opts = parseCliArgs(process.argv);

  const result = scanDirectory(opts.target);

  if (opts.json) {
    const output = {
      scan_path: result.scan_path,
      files_scanned: result.files_scanned,
      total_lines: result.total_lines,
      total_code_lines: result.total_code_lines,
      passed: passed(result),
      error_count: result.issues.filter(i => i.severity === 'error').length,
      warning_count: result.issues.filter(i => i.severity === 'warning').length,
      issues: result.issues
    };
    console.log(JSON.stringify(output, null, 2));
  } else {
    console.log(formatReport(result, opts.verbose));
  }

  process.exit(passed(result) ? 0 : 1);
}

main();
